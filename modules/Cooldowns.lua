-- OctoBG :: enemy cooldowns (engine)
-- Merged from EnemyCooldowns 2.0 by Nivhalla. Tracks every enemy's cooldowns
-- from their casts (SuperWoW UNIT_CASTEVENT: caster, target, kind, spell id),
-- with the duration from nampower's GetSpellIdCooldown, the curated list in
-- data\Spells.lua, or durations harvested earlier. Also:
--   * learns each enemy's real (talented) cooldown from early recasts and
--     remembers it per player name,
--   * applies cooldown resets (Cold Snap, Preparation),
--   * diminishing returns on whoever gets crowd-controlled,
--   * immunities on whoever RECEIVES them (Hand of Protection lands on the
--     paladin's target), ended early when the aura drops (nampower),
--   * alerts for notable cooldowns, and a special one for the enemy carrier.
-- Runs everywhere (battlegrounds, world PvP, duels). The enemy list, flag rows,
-- HUD, bars and nameplate icons all read from here; every cast seen here also
-- feeds the enemy tracker.

local B = OctoBG
local U = B.U
local D = B.CDData
local CD = {
  cache = {},        -- guid -> spell name -> { spellName, duration, endTime, startTime, texture, spellID }
  drCache = {},      -- guid -> category -> { level, expires, lastSpellID }
  learnedGuid = {},  -- guid -> spell name -> seconds (this session)
  immune = {},       -- guid -> { ends, name }
  blocked = {},      -- spell name -> true (flat lookup of db.cd.blockedSpells)
  seenLocal = {},    -- "caster:spellID" -> time this client saw the cast (team sync dedupe, 5 s)
  seenTeam = {},     -- "caster:spellID" -> time a teammate's OctoBG reported it (5 s)
}
B.CD = CD

local LEARN_FLOOR_RATIO = 0.4    -- an early recast below 40 % of base is a reset we missed
local LEARNED_MAX = 800          -- players remembered; the oldest 100 go beyond that
local ALERT_THROTTLE = 1.5

-- ---------------------------------------------------------------- settings

CD.SOUNDS = {
  { key = "RaidWarning", label = "Raid Warning", file = "Sound\\Interface\\RaidWarning.wav" },
  { key = "BellToll",    label = "Bell Toll",    file = "Sound\\Doodad\\BellTollHorde.wav" },
  { key = "Gong",        label = "Gong",         file = "Sound\\Doodad\\G_GongTroll01.wav" },
  { key = "Whisper",     label = "Whisper Ping", file = "Sound\\Interface\\iTellMessage.wav" },
  { key = "Murloc",      label = "Murloc",       file = "Sound\\Creature\\Murloc\\mMurlocAggroOld.wav" },
}

-- Same keys as EnemyCooldowns' ECD_CONFIG so its settings carry straight over.
B.DEFAULTS.cd = {
  -- cooldown bars (your target's cooldowns)
  bars = true, showWho = true, stickyTarget = false, efcFallback = true,
  barWidth = 198, barHeight = 20, maxBars = 8, showIcon = true, iconOnly = false,
  growUp = false, invertFill = false, classColors = false, fontSize = 10, alpha = 1.0,
  interactiveBars = true,
  -- immunity sub-bar
  showImmuneBars = true, immuneBarHeight = 8, immuneAlwaysShowTimer = false,
  -- tracking
  minDuration = 1.5, learnCooldowns = true, showUncertainty = true,
  -- diminishing returns
  showDR = true, drWidth = 44, drHeight = 14,
  -- alerts
  alertSound = false, alertSoundFile = "RaidWarning", alertFlash = false, alertText = false,
  alertEFC = true, alertAnnounce = false, alertChannel = "PARTY",
  -- nameplate icons
  nameplates = true, nameplateIconSize = 18, nameplateMaxIcons = 5, nameplateSpacing = 2,
  nameplateXOffset = 0, nameplateYOffset = 12, nameplateAnchor = "TOP", nameplateGrow = "CENTER",
  nameplateAlpha = 1.0, nameplateImportantOnly = false,
  nameplateBackdrop = false, nameplateBgR = 0, nameplateBgG = 0, nameplateBgB = 0, nameplateBgA = 0.5,
  nameplateBorder = true, nameplateBorderClass = false, nameplateBorderR = 0, nameplateBorderG = 0,
  nameplateBorderB = 0, nameplateBorderA = 0.85, nameplateBorderSize = 1,
  nameplateShowTimer = true, nameplateTimerSize = 10, nameplateTimerPos = "BOTTOM",
  -- debug
  debugSpellID = false,
  -- spell filter: class -> spell name -> true (hidden)
  blockedSpells = {},
}
B.DEFAULTS.cdLearned = {}     -- player name -> spell name -> seconds
B.DEFAULTS.cdSeen = {}        -- player name -> time() last learned (eviction)
B.DEFAULTS.cdCollected = {}   -- spell name -> { duration, texture, spellID } (base durations seen)

-- Sliders clamp to these, so a damaged saved file cannot break the UI.
CD.LIMITS = {
  barWidth = { 120, 400 }, barHeight = { 12, 40 }, maxBars = { 1, 20 }, immuneBarHeight = { 4, 20 },
  alpha = { 0.1, 1.0 }, fontSize = { 7, 20 }, minDuration = { 0, 30 }, drWidth = { 24, 80 },
  drHeight = { 8, 24 }, nameplateIconSize = { 8, 40 }, nameplateMaxIcons = { 1, 10 },
  nameplateSpacing = { 0, 12 }, nameplateXOffset = { -150, 150 }, nameplateYOffset = { -80, 120 },
  nameplateAlpha = { 0.1, 1.0 }, nameplateBorderSize = { 0, 4 }, nameplateTimerSize = { 6, 20 },
}

function CD.Clamp(key, v)
  local l = CD.LIMITS[key]
  if not l or type(v) ~= "number" then return v end
  return math.max(l[1], math.min(l[2], v))
end

function CD.SoundFile(key)
  for i = 1, table.getn(CD.SOUNDS) do
    if CD.SOUNDS[i].key == key then return CD.SOUNDS[i].file end
  end
  return CD.SOUNDS[1].file
end

-- Colours are four number keys (<prefix>R/G/B/A), like EnemyCooldowns.
function CD.GetColor(prefix)
  local c = B.db.cd
  return c[prefix .. "R"] or 1, c[prefix .. "G"] or 1, c[prefix .. "B"] or 1, c[prefix .. "A"] or 1
end

function CD.SetColor(prefix, r, g, b, a)
  local c = B.db.cd
  c[prefix .. "R"], c[prefix .. "G"], c[prefix .. "B"], c[prefix .. "A"] = r, g, b, a
end

-- ---------------------------------------------------------------- spell filter

-- spell name -> class (first class listing it wins)
CD.SPELL_CLASS = {}
for class, spells in pairs(D.CLASS_SPELLS) do
  for i = 1, table.getn(spells) do
    if not CD.SPELL_CLASS[spells[i]] then CD.SPELL_CLASS[spells[i]] = class end
  end
end

function CD.SpellColor(spellName)
  local class = CD.SPELL_CLASS[spellName]
  if class and class ~= "OTHERS" then return U.ClassColor(class) end
  return 0.6, 0.6, 0.6
end

function CD:RebuildBlocked()
  local lookup = {}
  for _, t in pairs(B.db.cd.blockedSpells) do
    if type(t) == "table" then
      for name, on in pairs(t) do
        if on == true then lookup[name] = true end
      end
    end
  end
  self.blocked = lookup
end

function CD:IsBlocked(name)
  return self.blocked[name] == true
end

-- Hiding is by name (covers every rank), so un-hiding clears it under every class.
function CD:SetBlocked(name, blocked, class)
  if not name then return end
  local bs = B.db.cd.blockedSpells
  class = class or self.SPELL_CLASS[name] or "OTHERS"
  if blocked then
    if not bs[class] then bs[class] = {} end
    bs[class][name] = true
    for _, spells in pairs(self.cache) do spells[name] = nil end
  else
    for _, t in pairs(bs) do t[name] = nil end
  end
  self:RebuildBlocked()
end

function CD:SetClassBlocked(class, blocked)
  local spells = D.CLASS_SPELLS[class]
  if not spells then return end
  for i = 1, table.getn(spells) do self:SetBlocked(spells[i], blocked, class) end
end

-- ---------------------------------------------------------------- learning

function CD:LearnCooldown(guid, spellName, observed)
  if not self.learnedGuid[guid] then self.learnedGuid[guid] = {} end
  local cur = self.learnedGuid[guid][spellName]
  if cur and cur <= observed then return end
  self.learnedGuid[guid][spellName] = observed
  -- remembered by player name (mobs share names and have no talents)
  if not U.IsGuid(guid) or not UnitIsPlayer(guid) then return end
  local name = UnitName(guid)
  if not name then return end
  local db = B.db
  if not db.cdLearned[name] then
    self:EvictLearned()
    db.cdLearned[name] = {}
  end
  local saved = db.cdLearned[name][spellName]
  if not saved or saved > observed then db.cdLearned[name][spellName] = observed end
  db.cdSeen[name] = time()
end

function CD:EvictLearned()
  local n = 0
  for _ in pairs(B.db.cdLearned) do n = n + 1 end
  if n < LEARNED_MAX then return end
  local list = {}
  for name in pairs(B.db.cdLearned) do table.insert(list, name) end
  local seen = B.db.cdSeen
  table.sort(list, function(a, b) return (seen[a] or 0) < (seen[b] or 0) end)
  for i = 1, 100 do
    B.db.cdLearned[list[i]] = nil
    seen[list[i]] = nil
  end
end

function CD:GetLearned(guid, spellName)
  local g = self.learnedGuid[guid]
  if g and g[spellName] then return g[spellName] end
  if not U.IsGuid(guid) then return nil end   -- sample data
  local name = U.GuidExists(guid) and UnitName(guid)
  if not name then   -- out of range (a teammate's report): the tracker may know the name
    local u = B.Tracker.units[guid]
    name = u and u.name
  end
  local p = name and B.db.cdLearned[name]
  return p and p[spellName]
end

function CD:ForgetLearned()
  self.learnedGuid = {}
  B.db.cdLearned = {}
  B.db.cdSeen = {}
end

-- ---------------------------------------------------------------- cache

-- team: reported by a teammate's OctoBG (Sync.lua) - it never teaches durations
-- (the report arrives late, so the gap to a recast would be wrong).
function CD:Add(guid, spellName, duration, texture, spellID, team)
  if not guid or not spellName or self:IsBlocked(spellName) then return false end
  local db = B.db.cd
  if not self.cache[guid] then self.cache[guid] = {} end
  local now = GetTime()
  local entry = self.cache[guid][spellName]
  local base = duration
  -- a recast while we still had time on the clock bounds their real cooldown
  if db.learnCooldowns and not team and entry and entry.endTime > now then
    local observed = now - entry.startTime
    if observed >= duration * LEARN_FLOOR_RATIO and observed < entry.duration then
      self:LearnCooldown(guid, spellName, observed)
    end
  end
  if db.learnCooldowns then
    local learned = self:GetLearned(guid, spellName)
    if learned and learned < duration then duration = learned end
  end
  if not entry then
    entry = {}
    self.cache[guid][spellName] = entry
  end
  entry.endTime, entry.duration, entry.spellName = now + duration, duration, spellName
  entry.texture, entry.spellID, entry.startTime = texture, spellID, now
  if self.SAMPLES[guid] or team then return true end   -- sample / team data never becomes a known duration
  -- base durations double as the fallback for spells the server reports none for
  local known = B.db.cdCollected[spellName]
  if not known then
    B.db.cdCollected[spellName] = { duration = base, texture = texture, spellID = spellID }
  else
    known.duration = base
    known.texture = texture or known.texture
    known.spellID = spellID or known.spellID
  end
  return true
end

-- Everything keyed by GUID goes on a zone change (and on /obg cd reset);
-- learned cooldowns stay saved by player name.
function CD:Clear()
  self.cache, self.drCache, self.immune, self.learnedGuid = {}, {}, {}, {}
  self.seenLocal, self.seenTeam = {}, {}
  self:ResetAlertThrottle()
end

function CD:Cleanup(now)
  for guid, spells in pairs(self.cache) do
    local any = false
    for name, data in pairs(spells) do
      if data.endTime <= now then spells[name] = nil else any = true end
    end
    if not any then self.cache[guid] = nil end
  end
  for guid, im in pairs(self.immune) do
    if im.ends <= now then self.immune[guid] = nil end
  end
  for k, t in pairs(self.seenLocal) do
    if now - t > 5 then self.seenLocal[k] = nil end
  end
  for k, t in pairs(self.seenTeam) do
    if now - t > 5 then self.seenTeam[k] = nil end
  end
end

function CD:HandleResets(guid, spellID)
  local list = D.SPELL_RESETS[spellID]
  if not list or not self.cache[guid] then return end
  for i = 1, table.getn(list) do
    local name = SpellInfo and SpellInfo(list[i])
    if name then self.cache[guid][name] = nil end
  end
end

-- Active cooldowns of a GUID, soonest ready first. Returns a SHARED table:
-- copy what you need before the next call.
local scratch, pool, poolN = {}, {}, 0

local function ByRemaining(a, b)
  if a.remaining == b.remaining then return a.spellName < b.spellName end
  return a.remaining < b.remaining
end

function CD:GetActiveCooldowns(guid)
  for i = table.getn(scratch), 1, -1 do scratch[i] = nil end
  poolN = 0
  local spells = guid and self.cache[guid]
  if not spells then return scratch end
  local now, n = GetTime(), 0
  for _, data in pairs(spells) do
    if data.endTime > now then
      poolN = poolN + 1
      local e = pool[poolN]
      if not e then
        e = {}
        pool[poolN] = e
      end
      e.spellName, e.endTime, e.duration, e.texture = data.spellName, data.endTime, data.duration, data.texture
      e.spellID, e.startTime, e.remaining = data.spellID, data.startTime, data.endTime - now
      n = n + 1
      scratch[n] = e
    end
  end
  if n > 1 then table.sort(scratch, ByRemaining) end
  return scratch
end

-- Up to max cooldowns copied into out (notable ones first, then by time left):
-- out[i] = { tex, rem, name }; returns the count.
function CD:Important(guid, max, out)
  local list = self:GetActiveCooldowns(guid)
  local n = 0
  for pass = 1, 2 do
    for i = 1, table.getn(list) do
      local e = list[i]
      local notable = D.ALERT_SPELLS[e.spellName]
      if n < max and ((pass == 1 and notable) or (pass == 2 and not notable)) then
        n = n + 1
        if not out[n] then out[n] = {} end
        out[n].tex, out[n].rem, out[n].name = e.texture, e.remaining, e.spellName
      end
    end
  end
  return n
end

-- Seconds of immunity left on a GUID (Ice Block, Divine Shield, ...), and its name.
function CD:ImmuneLeft(guid)
  local im = guid and self.immune[guid]
  if not im then return nil end
  local left = im.ends - GetTime()
  if left <= 0 then return nil end
  return left, im.name
end

-- True immunities only (Hand of Freedom and Free Action are in the effect
-- table for the bar, but they do not stop damage).
CD.IMMUNE_NAMES = { ["Ice Block"] = true, ["Divine Shield"] = true, ["Hand of Protection"] = true,
                    ["Divine Protection"] = true, ["Invulnerability"] = true }

-- ---------------------------------------------------------------- diminishing returns

-- Only the cast is seen, so the effect end is estimated (base duration times
-- the level it landed at) and the window runs DR_WINDOW seconds after that.
function CD:ApplyDR(guid, spellID)
  local info = D.DR_SPELLS[spellID]
  if not info or not guid then return end
  if not self.drCache[guid] then self.drCache[guid] = {} end
  local now = GetTime()
  local entry = self.drCache[guid][info.cat]
  if not entry or entry.expires <= now then
    entry = { level = 0, expires = 0 }
    self.drCache[guid][info.cat] = entry
  end
  local landed = entry.level + 1
  local mult = D.DR_MULTIPLIERS[landed] or 0
  entry.level = math.min(landed, table.getn(D.DR_MULTIPLIERS))
  entry.expires = now + info.duration * mult + D.DR_WINDOW
  entry.lastSpellID = spellID
end

-- Multiplier the NEXT application would land at (1 / 0.5 / 0.25 / 0) and seconds left.
function CD:GetDR(guid, cat)
  local t = guid and self.drCache[guid]
  local e = t and t[cat]
  if not e then return 1, 0 end
  local now = GetTime()
  if e.expires <= now then
    t[cat] = nil
    return 1, 0
  end
  return D.DR_MULTIPLIERS[e.level + 1] or 0, e.expires - now
end

-- out[i] = { key, label, multiplier, remaining, r, g, b }; returns the count.
function CD:CollectDR(guid, out)
  local n = 0
  if guid and self.drCache[guid] then
    for i = 1, table.getn(D.DR_CATEGORIES) do
      local cat = D.DR_CATEGORIES[i]
      local mult, rem = self:GetDR(guid, cat.key)
      if rem > 0 then
        n = n + 1
        if not out[n] then out[n] = {} end
        local e = out[n]
        e.key, e.label, e.multiplier, e.remaining, e.r, e.g, e.b = cat.key, cat.label, mult, rem, cat.r, cat.g, cat.b
      end
    end
  end
  for i = table.getn(out), n + 1, -1 do out[i] = nil end
  return n
end

function CD.FormatDR(mult)
  if mult <= 0 then return "IMM" end
  return math.floor(mult * 100 + 0.5) .. "%"
end

function CD:CleanupDR(now)
  for guid, cats in pairs(self.drCache) do
    local any = false
    for cat, e in pairs(cats) do
      if e.expires <= now then cats[cat] = nil else any = true end
    end
    if not any then self.drCache[guid] = nil end
  end
end

-- "1:35", "41", "9.4"
function CD.Time(s)
  if s >= 60 then
    local m = math.floor(s / 60)
    return string.format("%d:%02d", m, math.floor(s - m * 60))
  elseif s >= 10 then
    return tostring(math.floor(s + 0.5))
  end
  return string.format("%.1f", s)
end

-- ---------------------------------------------------------------- casts

-- (name, duration, texture, category) for a spell id: items first, then the
-- server's cooldown (nampower), the curated list, durations harvested earlier.
function CD:Resolve(spellID, faction)
  local item = D.ITEMS_SPELLS[spellID]
  if item then
    local name = item.name
    if spellID == 52317 then
      name = (faction == "Horde") and "Insignia of the Horde" or "Insignia of the Alliance"
    end
    return name, item.duration, item.texture, nil
  end
  if not SpellInfo then return nil end
  local name, _, texture = SpellInfo(spellID)
  if not name then return nil end
  local duration, cat = 0, nil
  if GetSpellIdCooldown then
    local ok, info = pcall(GetSpellIdCooldown, spellID)
    if ok and type(info) == "table" then
      cat = info.categoryId
      if info.categoryDurationMs and info.categoryDurationMs > 0 then
        duration = info.categoryDurationMs / 1000
      elseif info.individualDurationMs and info.individualDurationMs > 0 then
        duration = info.individualDurationMs / 1000
      end
    end
  end
  if duration <= 0 then
    local curated = D.SPELLS[name]
    if curated and curated.duration then
      duration = curated.duration
      texture = texture or curated.texture
    end
  end
  if duration <= 0 then
    local learned = B.db.cdCollected[name]
    if learned and learned.duration then
      duration = learned.duration
      texture = texture or learned.texture
    end
  end
  if not texture and C_Spell and C_Spell.GetSpellTexture then   -- ClassicAPI
    local ok, t = pcall(C_Spell.GetSpellTexture, spellID)
    if ok and type(t) == "string" and t ~= "" then
      texture = string.find(t, "\\", 1, true) and t or ("Interface\\Icons\\" .. t)
    end
  end
  return name, duration, texture, cat
end

-- Tell the team (Sync.lua) about a cast that changed what OctoBG shows.
function CD:Share(key, caster, target, spellID, enemyCaster)
  self.seenLocal[key] = GetTime()
  if B.Sync then B.Sync:Cast(caster, target, spellID, enemyCaster) end
end

function CD:OnCast(caster, target, kind, spellID)
  if not B.db or not caster or not spellID then return end
  if kind ~= "CAST" and kind ~= "CHANNEL" then return end
  if target == "0x0000000000000000" then target = nil end   -- untargeted (Psychic Scream...)
  local db = B.db.cd
  local key = caster .. ":" .. spellID
  -- a teammate's OctoBG reported this very cast first (Sync.lua): DR counts once
  local reported = self.seenTeam[key] and GetTime() - self.seenTeam[key] < 3
  local share = false
  -- DR lands on the receiver, whoever cast it (usually you CCing an enemy)
  if target and D.DR_SPELLS[spellID] then
    if db.showDR and not reported then self:ApplyDR(target, spellID) end
    share = U.GuidExists(target) and UnitCanAttack("player", target) and true or false
  end
  if not UnitCanAttack("player", caster) then
    if share then self:Share(key, caster, target, spellID, false) end
    return
  end
  local casterName = UnitName(caster)
  local name, duration, texture, cat = self:Resolve(spellID, UnitFactionGroup(caster) or "Unknown")
  if not name or not duration then
    if share then self:Share(key, caster, target, spellID, true) end
    return
  end
  if db.debugSpellID then
    B:Print(string.format("cast %s (id %d) by %s -> %.1fs", name, spellID, tostring(casterName), duration))
  end
  -- immunities: on the target of the cast (Hand of Protection), else the caster
  local eff = D.IMMUNITY_SPELLS[spellID]
  if eff and self.IMMUNE_NAMES[name] then
    self.immune[target or caster] = { ends = GetTime() + eff, name = name, spellID = spellID }
    share = true
  end
  if duration > (db.minDuration or 1.5)
    and not ((cat and D.BLACKLISTED_CATEGORIES[cat]) or D.BLACKLISTED_SPELLS[spellID] or D.BLACKLISTED_NAMES[name]) then
    self:HandleResets(caster, spellID)
    if self:Add(caster, name, duration, texture, spellID) then
      self:Alert(caster, casterName, name, duration)
      if B.active then B.Tracker:Consider(caster) end
      share = true
    end
  end
  if share then self:Share(key, caster, target, spellID, true) end
end

-- A cast a teammate's OctoBG saw (Sync.lua): the same marks as OnCast, minus what
-- needs the caster in range (learning, alerts, their faction). A cast this client
-- saw itself, or already got from another teammate, is skipped.
function CD:TeamCast(caster, target, spellID, enemyCaster)
  if not B.db then return end
  local key = caster .. ":" .. spellID
  local now = GetTime()
  if (self.seenLocal[key] and now - self.seenLocal[key] < 3)
    or (self.seenTeam[key] and now - self.seenTeam[key] < 3) then return end
  self.seenTeam[key] = now
  local db = B.db.cd
  if target and db.showDR then self:ApplyDR(target, spellID) end
  if not enemyCaster then return end
  local name, duration, texture, cat = self:Resolve(spellID, B.enemy)
  if not name or not duration then return end
  local eff = D.IMMUNITY_SPELLS[spellID]
  if eff and self.IMMUNE_NAMES[name] then
    self.immune[target or caster] = { ends = now + eff, name = name, spellID = spellID }
  end
  if duration <= (db.minDuration or 1.5) then return end
  if (cat and D.BLACKLISTED_CATEGORIES[cat]) or D.BLACKLISTED_SPELLS[spellID] or D.BLACKLISTED_NAMES[name] then return end
  self:HandleResets(caster, spellID)
  self:Add(caster, name, duration, texture, spellID, true)
end

-- SuperWoW: UNIT_CASTEVENT(casterGUID, targetGUID, "START"/"CAST"/"CHANNEL"/"FAIL", spellID, castDuration)
B:On("UNIT_CASTEVENT", function(ev, caster, target, kind, spellID)
  CD:OnCast(caster, target, kind, spellID)
end)

-- An immunity aura that ends early (cancelled, dispelled) ends the mark.
B:On("BUFF_REMOVED_OTHER", function(ev, guid, a2, spellID)
  local im = guid and CD.immune[guid]
  if im and im.spellID == spellID then CD.immune[guid] = nil end
end)

-- ---------------------------------------------------------------- whose cooldowns

-- The bars follow your target; with sticky on, the last enemy stays (dimmed);
-- in Warsong Gulch with no target they can follow the enemy flag carrier.
function CD:OnTargetChanged()
  if not B.db then return end
  local g = U.GuidOf("target")
  if g and UnitExists("target") then
    self.target, self.lastTarget, self.stale = g, g, false
  elseif B.db.cd.stickyTarget and self.lastTarget then
    self.target, self.stale = self.lastTarget, true
  else
    self.target, self.stale = nil, false
  end
end

B:On("PLAYER_TARGET_CHANGED", function() CD:OnTargetChanged() end)

-- guid, how ("target" / "last" / "efc"), display name
function CD:Subject()
  if self.target then
    local name = U.IsGuid(self.target) and UnitName(self.target) or "Testmage"   -- else the sample enemy
    return self.target, self.stale and "last" or "target", name
  end
  if B.db.cd.efcFallback and B.zone == "WSG" and B.Flags then
    local efc = B.Flags:Enemy()
    if efc and not efc.dropped and efc.guid then return efc.guid, "efc", efc.name end
  end
  return nil
end

-- ---------------------------------------------------------------- alerts

local lastAlert = {}

function CD:ResetAlertThrottle()
  lastAlert = {}
end

local flash
function CD:Flash()
  if not flash then
    flash = CreateFrame("Frame", "OctoBGAlertFlash", UIParent)
    flash:SetAllPoints(UIParent)
    flash:SetFrameStrata("FULLSCREEN_DIALOG")
    flash:EnableMouse(false)
    flash:Hide()
    local t = flash:CreateTexture(nil, "BACKGROUND")
    t:SetAllPoints(flash)
    t:SetTexture("Interface\\FullScreenTextures\\LowHealth")
    t:SetBlendMode("ADD")
    flash:SetScript("OnUpdate", function()
      this.t = this.t + (arg1 or 0)
      if this.t < 0.15 then
        this:SetAlpha(this.t / 0.15)
      elseif this.t < 0.6 then
        this:SetAlpha(1 - (this.t - 0.15) / 0.45)
      else
        this:Hide()
      end
    end)
  end
  flash.t = 0
  flash:SetAlpha(0)
  flash:Show()
end

-- "Auto" picks /bg in a battleground, then raid, then party; nil = say it locally.
local function AnnounceChannel()
  local ch = B.db.cd.alertChannel or "PARTY"
  if ch == "PARTY" then
    if B:IsBG() then return "BATTLEGROUND" end
    if GetNumRaidMembers() > 0 then return "RAID" end
    if GetNumPartyMembers() > 0 then return "PARTY" end
    return nil
  end
  if ch == "BATTLEGROUND" and not B:IsBG() then return nil end
  if ch == "RAID" and GetNumRaidMembers() == 0 then return nil end
  return ch
end

function CD:Announce(who, spellName, duration)
  local msg = string.format("%s used %s (%s cooldown)", who or "Enemy", spellName, CD.Time(duration))
  local ch = AnnounceChannel()
  if ch then SendChatMessage(msg, ch) else B:Print(msg) end
end

function CD:Alert(guid, who, spellName, duration)
  if not D.ALERT_SPELLS[spellName] then return end
  local db = B.db.cd
  local now = GetTime()
  local key = (guid or "?") .. spellName
  if lastAlert[key] and now - lastAlert[key] < ALERT_THROTTLE then return end
  lastAlert[key] = now
  -- also as combat text (pfUI Octo's, through SCTLink.lua) when that message type is on there
  if B.SCT and B.SCT.Notify then
    local cr, cg, cb = 1, 0.82, 0
    if U.IsGuid(guid) and UnitClass(guid) then
      local _, class = UnitClass(guid)
      cr, cg, cb = U.ClassColor(class)
    end
    B.SCT:Notify("obgCd", (who or "Enemy") .. ": " .. spellName, cr, cg, cb)
  end

  -- the enemy flag carrier using a big cooldown always matters
  local efc = B.Flags and B.Flags:Enemy()
  local isEFC = efc and not efc.dropped and who and efc.name == who
  if isEFC and db.alertEFC then
    U.Alert("EFC " .. who .. ": " .. spellName .. "!", 1, 0.3, 0.2, true)
  elseif db.alertText then
    local r, g, b = 1, 0.82, 0
    if guid and UnitClass(guid) then
      local _, class = UnitClass(guid)
      r, g, b = U.ClassColor(class)
    end
    U.Alert((who or "Enemy") .. ": " .. spellName, r, g, b, false)
  end
  if db.alertSound then PlaySoundFile(CD.SoundFile(db.alertSoundFile)) end
  if db.alertFlash then self:Flash() end
  if db.alertAnnounce then self:Announce(who, spellName, duration) end
end

function CD:TestAlert()
  local db = B.db.cd
  self:ResetAlertThrottle()
  if db.alertText then U.Alert("Testmage: Ice Block", 0.41, 0.8, 0.94, false) end
  if db.alertEFC then U.Alert("EFC Testrogue: Vanish!", 1, 0.3, 0.2, true) end
  if db.alertSound then PlaySoundFile(CD.SoundFile(db.alertSoundFile)) end
  if db.alertFlash then self:Flash() end
  if db.alertAnnounce then B:Print("announce would say: \"Testmage used Ice Block (5:00 cooldown)\"") end
  if not (db.alertText or db.alertEFC or db.alertSound or db.alertFlash or db.alertAnnounce) then
    B:Print("no alert type is switched on")
  end
end

StaticPopupDialogs["OCTOBG_CD_ANNOUNCE"] = {
  text = "OctoBG: announce notable enemy cooldowns (Ice Block, Vanish, trinket...) in group chat?\n\nEvery one goes out, at most once per enemy and spell every 1.5 seconds.",
  button1 = YES,
  button2 = NO,
  OnAccept = function()
    B.db.cd.alertAnnounce = true
    if B.Options then B.Options:Refresh() end
  end,
  timeout = 0,
  whileDead = 1,
  hideOnEscape = 1,
}

-- ---------------------------------------------------------------- upkeep

B:Every(0.1, function()
  local now = GetTime()
  CD:Cleanup(now)
  CD:CleanupDR(now)
end)

-- Old zone's enemies are gone; their GUIDs mean nothing in the next one.
B:On("OBG_ZONE", function()
  CD:Clear()
  CD.target, CD.lastTarget, CD.stale = nil, nil, false
end)

-- ---------------------------------------------------------------- profile

-- "OBGCD1;key=value;...;B=CLASS/Spell~CLASS/Spell". EnemyCooldowns' "ECD1;"
-- strings import the same way. Booleans are 1/0.
local SKIP = { blockedSpells = true }

function CD:Export()
  local parts = { "OBGCD1" }
  local db = B.db.cd
  for key, def in pairs(B.DEFAULTS.cd) do
    if not SKIP[key] then
      local v = db[key]
      if type(def) == "boolean" then
        table.insert(parts, key .. "=" .. (v and "1" or "0"))
      elseif type(def) == "number" and type(v) == "number" then
        table.insert(parts, key .. "=" .. string.format("%.4g", v))
      elseif type(def) == "string" and type(v) == "string" then
        table.insert(parts, key .. "=" .. v)
      end
    end
  end
  local hidden = {}
  for class, t in pairs(db.blockedSpells) do
    for name, on in pairs(t) do
      if on == true then table.insert(hidden, class .. "/" .. name) end
    end
  end
  if table.getn(hidden) > 0 then table.insert(parts, "B=" .. table.concat(hidden, "~")) end
  return table.concat(parts, ";")
end

function CD:Import(str)
  str = string.gsub(str or "", "^%s*(.-)%s*$", "%1")
  if str == "" then return false, "Nothing to import." end
  if string.sub(str, 1, 7) ~= "OBGCD1;" and string.sub(str, 1, 5) ~= "ECD1;" then
    return false, "That is not a cooldown profile string."
  end
  local db, applied, hidden = B.db.cd, 0, nil
  for field in string.gfind(str, "[^;]+") do
    local _, _, k, v = string.find(field, "^([^=]+)=(.*)$")
    if k == "B" and v then
      hidden = {}
      for entry in string.gfind(v, "[^~]+") do
        local _, _, class, name = string.find(entry, "^([^/]+)/(.+)$")
        if class and name then
          if not hidden[class] then hidden[class] = {} end
          hidden[class][name] = true
        end
      end
    elseif k and v then
      local def = B.DEFAULTS.cd[k]
      if def ~= nil and not SKIP[k] then
        if type(def) == "boolean" then
          db[k] = (v == "1")
          applied = applied + 1
        elseif type(def) == "number" and tonumber(v) then
          db[k] = CD.Clamp(k, tonumber(v))
          applied = applied + 1
        elseif type(def) == "string" then
          db[k] = v
          applied = applied + 1
        end
      end
    end
  end
  if hidden then db.blockedSpells = hidden end
  self:RebuildBlocked()
  if applied == 0 and not hidden then return false, "The string had no usable settings." end
  return true, "Imported " .. applied .. " setting(s)" .. (hidden and " and the spell filter." or ".")
end

function CD:ResetDefaults()
  B.db.cd = {}
  B.MergeDefaults(B.db.cd, B.DEFAULTS.cd)
  self:RebuildBlocked()
end

-- ---------------------------------------------------------------- the old EnemyCooldowns addon

-- While the separate EnemyCooldowns addon is still enabled its saved data is
-- loaded too (OctoBG lists it as an optional dependency, so it loads first):
-- its settings and spell filter are copied once, learned cooldowns and
-- harvested durations are merged every login. Its saved file is only read.
function CD:ImportOld()
  local imported = false
  if type(ECD_CONFIG) == "table" and not B.db.cdImported then
    for key, def in pairs(B.DEFAULTS.cd) do
      local v = ECD_CONFIG[key]
      if key ~= "blockedSpells" and v ~= nil and type(v) == type(def) then
        B.db.cd[key] = CD.Clamp(key, v)
      end
    end
    if type(ECD_CONFIG.hideMainFrame) == "boolean" then B.db.cd.bars = not ECD_CONFIG.hideMainFrame end
    if type(ECD_CONFIG.blockedSpells) == "table" then
      local copy = {}
      for class, t in pairs(ECD_CONFIG.blockedSpells) do
        if type(t) == "table" then
          copy[class] = {}
          for name, on in pairs(t) do copy[class][name] = (on == true) or nil end
        end
      end
      B.db.cd.blockedSpells = copy
    end
    if type(ECD_CONFIG.minimapPos) == "number" then B.db.minimap.pos = ECD_CONFIG.minimapPos end
    B.db.cdImported = true
    imported = true
  end
  if type(ECD_LEARNED_CD) == "table" then
    local now = time()
    for name, spells in pairs(ECD_LEARNED_CD) do
      if type(spells) == "table" then
        local mine = B.db.cdLearned[name]
        if not mine then
          mine = {}
          B.db.cdLearned[name] = mine
          B.db.cdSeen[name] = B.db.cdSeen[name] or now
        end
        for spell, sec in pairs(spells) do
          if type(sec) == "number" and (not mine[spell] or sec < mine[spell]) then mine[spell] = sec end
        end
      end
    end
    imported = true
  end
  if type(ECD_COLLECTION_DATA) == "table" then
    for name, d in pairs(ECD_COLLECTION_DATA) do
      if type(d) == "table" and type(d.duration) == "number" and not B.db.cdCollected[name] then
        B.db.cdCollected[name] = { duration = d.duration, texture = d.texture, spellID = d.spellID }
      end
    end
    imported = true
  end
  return imported
end

function CD:OldLoaded()
  return IsAddOnLoaded and IsAddOnLoaded("EnemyCooldowns") and true or false
end

StaticPopupDialogs["OCTOBG_OLD_ECD"] = {
  text = "EnemyCooldowns is now built into OctoBG.\n\nYour settings, hidden spells and learned cooldowns have been copied over. Switch the old EnemyCooldowns addon off now? (The interface reloads.)\n\nUntil then OctoBG keeps its own cooldown bars and nameplate icons hidden so nothing shows twice.",
  button1 = "Switch it off",
  button2 = "Not now",
  OnAccept = function()
    DisableAddOn("EnemyCooldowns")
    ReloadUI()
  end,
  timeout = 0,
  whileDead = 1,
  hideOnEscape = 1,
}

B:On("OBG_LOADED", function()
  CD:ImportOld()
  CD:RebuildBlocked()
  -- while the old addon runs, its bars and nameplate icons are the ones on screen
  CD.standDown = CD:OldLoaded()
end)

local asked = false
B:On("PLAYER_ENTERING_WORLD", function()
  if CD.standDown and not asked then
    asked = true
    StaticPopup_Show("OCTOBG_OLD_ECD")
  end
end)

-- ---------------------------------------------------------------- commands and samples

function CD:PrintLearned()
  local n = 0
  for name, spells in pairs(B.db.cdLearned) do
    n = n + 1
    local line = "|cffcccccc" .. name .. "|r:"
    for spell, sec in pairs(spells) do
      local base = D.SPELLS[spell] and D.SPELLS[spell].duration
      line = line .. " " .. spell .. " " .. CD.Time(sec) .. (base and (" |cff888888(" .. CD.Time(base) .. ")|r") or "")
    end
    DEFAULT_CHAT_FRAME:AddMessage(line)
  end
  if n == 0 then
    B:Print("nothing learned yet - an enemy has to recast a spell early for its real cooldown to show")
  else
    B:Print(n .. " players with learned cooldowns")
  end
end

function CD:PrintDebug()
  local now = GetTime()
  B:Print("cooldowns tracked (target " .. tostring(self.target) .. (self.stale and ", last target" or "") .. "):")
  for guid, spells in pairs(self.cache) do
    for _, d in pairs(spells) do
      DEFAULT_CHAT_FRAME:AddMessage("  " .. tostring(U.IsGuid(guid) and UnitName(guid) or guid) .. ": " .. d.spellName
        .. " " .. CD.Time(d.endTime - now) .. " (id " .. tostring(d.spellID) .. ")")
    end
  end
  for guid, cats in pairs(self.drCache) do
    for cat, e in pairs(cats) do
      DEFAULT_CHAT_FRAME:AddMessage("  DR " .. tostring(U.IsGuid(guid) and UnitName(guid) or guid) .. " " .. cat .. ": next "
        .. CD.FormatDR(D.DR_MULTIPLIERS[e.level + 1] or 0) .. ", " .. CD.Time(e.expires - now) .. " left")
    end
  end
end

-- Sample data on a fake GUID (the bars show it in layout mode or after /obg cd test).
CD.SAMPLE = "0xSAMPLE"
CD.SAMPLES = { ["0xSAMPLE"] = true, sample1 = true, sample4 = true }
function CD:LoadSamples()
  local g = self.SAMPLE
  self.cache[g] = nil
  self:Add(g, "Divine Shield", 300, "Interface\\Icons\\Spell_Holy_DivineIntervention", 1020)
  self:Add(g, "Blind", 180, "Interface\\Icons\\Spell_Shadow_MindSteal", 2094)
  self:Add(g, "Scatter Shot", 30, "Interface\\Icons\\Ability_GolemStormBolt", 19503)
  self:Add(g, "Hand of Freedom", 25, "Interface\\Icons\\Spell_Holy_SealOfValor", 1044)
  self:Add(g, "Ice Block", 12, "Interface\\Icons\\Spell_Frost_Frost", 11958)
  self:ApplyDR(g, 2094)
  self:ApplyDR(g, 1776)
  self:ApplyDR(g, 408)
  -- the layout-mode sample enemies (Tracker) get some too, one of them immune
  self:Add("sample1", "Vanish", 300, "Interface\\Icons\\Ability_Vanish", 1856)
  self:Add("sample1", "Insignia of the Horde", 180, "Interface\\Icons\\INV_Jewelry_Trinketpvp_02", 52317)
  self:Add("sample4", "Ice Block", 300, "Interface\\Icons\\Spell_Frost_Frost", 11958)
  self.immune.sample4 = { ends = GetTime() + 600, name = "Ice Block", spellID = 11958 }
end

function CD:ClearSamples()
  for g in pairs(self.SAMPLES) do
    self.cache[g], self.drCache[g], self.immune[g] = nil, nil, nil
  end
end

B:On("OBG_LAYOUT", function(ev, on)
  if on then CD:LoadSamples() else CD:ClearSamples() end
end)

local function CdCommand(rest)
  local _, _, sub = string.find(string.lower(rest or ""), "^(%S*)")
  if sub == "test" then
    CD:LoadSamples()
    CD.target, CD.lastTarget, CD.stale = CD.SAMPLE, CD.SAMPLE, false
    B:Print("sample cooldowns loaded - /obg cd reset clears them")
  elseif sub == "reset" then
    CD:Clear()
    CD:OnTargetChanged()
    B:Print("cooldown tracking cleared")
  elseif sub == "learned" then
    CD:PrintLearned()
  elseif sub == "forget" then
    CD:ForgetLearned()
    B:Print("learned cooldowns forgotten")
  elseif sub == "debug" then
    CD:PrintDebug()
  elseif sub == "alerts" then
    CD:TestAlert()
  elseif sub == "ids" then
    B.db.cd.debugSpellID = not B.db.cd.debugSpellID
    B:Print("printing enemy spell ids " .. (B.db.cd.debugSpellID and "on" or "off"))
  else
    if B.Options then B.Options:Open("cdbars") end
  end
end

B:Command("cd", "enemy cooldowns: test | reset | learned | forget | alerts | debug | ids (no word: settings)", CdCommand)

-- /ecd keeps working for anyone used to it, unless the old addon still owns it.
B:On("OBG_INIT", function()
  if not CD:OldLoaded() then
    SLASH_OCTOBGECD1 = "/ecd"
    SlashCmdList["OCTOBGECD"] = CdCommand
  end
end)
