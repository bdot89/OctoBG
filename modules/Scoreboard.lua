-- OctoBG :: the scoreboard
-- Everything the game's end-of-game frame shows (killing blows, honorable
-- kills, deaths, honor, the battleground's own columns such as flag captures),
-- plus damage and healing per player, in a table that sorts on any column and
-- whose columns can be reordered or hidden. It opens by itself when the game
-- ends and on the game's scoreboard key; the last game stays readable after
-- you leave (db.lastGame).
--
-- The server does not send damage or healing (patch-4's WorldStateFrame.lua has
-- no such column; its TW_BG channel carries only Thorn Gorge's flag captures).
-- So they are counted here from what nampower reports of each combat packet:
--   AUTO_ATTACK_SELF / _OTHER     attacker, target, damage
--   SPELL_DAMAGE_EVENT_SELF / _OTHER  target, caster, spell, amount (DoT ticks too)
--   DAMAGE_SHIELD_SELF / _OTHER   owner, attacker, damage
--   SPELL_HEAL_BY_SELF / _OTHER   target, caster, spell, amount (raw: 1.12's heal
--                                 log has no overheal; NP_EnableSpellHealEvents)
-- A pet's or totem's numbers go to its owner (nampower's summonedBy / charmedBy /
-- createdBy fields). A client only gets packets from fights in its server
-- range, so every OctoBG in the game shares its counts (Sync.lua "D") and the
-- highest count of each player wins: your own numbers are exact, others' are
-- as exact as someone with OctoBG was near them. The window says how many counted.
--
-- Eviction: everything clears on entering a battleground; owner lookups wiped at
-- 2000; unnamed GUIDs at most 200 and dropped when the zone changes.

local B = OctoBG
local U = B.U
local W = B.W
local BS = { totals = {}, actor = {}, nactor = 0, pending = {}, npending = 0, sendNext = 1 }
B.BGStats = BS
local BD = { rows = {}, heads = {}, list = {}, offset = 0, tab = "all" }
B.Scoreboard = BD

B.DEFAULTS.board = { auto = true, replace = true, sort = "damage", desc = true, order = {}, hide = {}, rows = 20, group = true,
                     dark = 0.62, shortNumbers = true,
                     fontHead = "Interface\\AddOns\\OctoBG\\media\\fonts\\BigNoodleTitling.ttf",
                     fontName = "Interface\\AddOns\\OctoBG\\media\\fonts\\PT-Sans-Narrow-Bold.ttf",
                     fontNum = "Interface\\AddOns\\OctoBG\\media\\fonts\\Expressway.ttf" }

local VISIBLE_MAX = 30
local ROW_H, HEAD_H = 19, 24

-- ---------------------------------------------------------------- counting

-- Who a damage or heal counts for: a player's name, a pet's owner, false for an
-- NPC, nil when the client cannot look at that GUID yet.
local function Actor(guid)
  if not U.IsGuid(guid) then return false end
  local known = BS.actor[guid]
  if known ~= nil then return known end
  if guid == U.GuidOf("player") then return UnitName("player") end
  if not U.GuidExists(guid) then return nil end
  local who = false
  if UnitIsPlayer(guid) then
    who = UnitName(guid) or nil
    if not who then return nil end
  else
    local Field = B.Tracker.Field
    local keys = { "summonedBy", "charmedBy", "createdBy" }
    for i = 1, 3 do
      local o = Field(guid, keys[i])
      if type(o) == "string" and U.IsGuid(o) and U.GuidExists(o) and UnitIsPlayer(o) then
        who = UnitName(o) or false
        break
      end
    end
  end
  if BS.nactor >= 2000 then BS.actor, BS.pet, BS.nactor = {}, {}, 0 end
  BS.actor[guid] = who
  if who and not UnitIsPlayer(guid) then BS.pet[guid] = true end
  BS.nactor = BS.nactor + 1
  return who
end

local function Add(name, dmg, heal)
  local t = BS.totals[name]
  if not t then
    t = { d = 0, h = 0 }
    BS.totals[name] = t
  end
  t.d, t.h = t.d + dmg, t.h + heal
  t.changed = true
end

function BS:Count(guid, dmg, heal)
  if self.over or not B:IsBG() then return end
  local who = Actor(guid)
  if who then
    Add(who, dmg, heal)
  elseif who == nil and U.IsGuid(guid) then
    -- not visible yet: hold it until the name is known
    local p = self.pending[guid]
    if not p then
      if self.npending >= 200 then return end
      p = { d = 0, h = 0 }
      self.pending[guid] = p
      self.npending = self.npending + 1
    end
    p.d, p.h = p.d + dmg, p.h + heal
  end
end

-- A player's numbers: the highest of this client's count and what other OctoBG users counted.
function BS:Get(name)
  local t = self.totals[name]
  local m = self.merged and self.merged[name]
  local d, h = t and t.d or 0, t and t.h or 0
  if m then
    if m.d > d then d = m.d end
    if m.h > h then h = m.h end
  end
  return d, h
end

function BS:Merge(name, d, h)
  if not name or string.len(name) < 2 or string.len(name) > 30 or not d or not h then return end
  self.merged = self.merged or {}
  self.mergedN = self.mergedN or 0
  local m = self.merged[name]
  if not m then
    if self.mergedN >= 200 then return end
    m = { d = 0, h = 0 }
    self.merged[name] = m
    self.mergedN = self.mergedN + 1
  end
  if d > m.d then m.d = d end
  if h > m.h then m.h = h end
end

function BS:Reset()
  self.totals, self.actor, self.pet, self.nactor, self.pending, self.npending = {}, {}, {}, 0, {}, 0
  self.merged, self.mergedN, self.over, self.endedAt = nil, 0, nil, nil
  self.x, self.mx, self.mxN, self.casting = {}, {}, 0, {}
  self.startAt = GetTime()
end

-- The rest of a player's game, for the hover panel: what each did besides raw
-- numbers. All plain adds on a table per player, on events already handled, so
-- counting costs next to nothing; nothing is worked out until a row is hovered.
--   cleanse  a dispel that took something off a teammate
--   purge    a dispel that took something off an enemy
--   dispel   a dispel when the two sides couldn't be told apart
--   int      an interrupt spell that landed on someone casting
--   cc       a stun, fear, root, sheep... landed (data\DR.lua names them)
local function X(name)
  local x = BS.x[name]
  if not x then
    x = { cleanse = 0, purge = 0, dispel = 0, int = 0, cc = 0, taken = 0, healIn = 0, bigHit = 0, bigHeal = 0, sd = {}, sh = {} }
    BS.x[name] = x
  end
  return x
end

-- Damage or a heal with who and what, on top of BS:Count's totals.
function BS:Hit(att, tgt, id, amt)
  if not amt or amt <= 0 then return end
  self:Count(att, amt, 0)
  if self.over or not B:IsBG() then return end
  local who = Actor(att)
  if who then
    local x = X(who)
    x.sd[id] = (x.sd[id] or 0) + amt
    if amt > x.bigHit then x.bigHit, x.bigHitId, x.send = amt, id, true end
  end
  local v = Actor(tgt)
  if v and not self.pet[tgt] then X(v).taken = X(v).taken + amt end
end

function BS:Mend(tgt, cas, id, amt)
  if not amt or amt <= 0 then return end
  self:Count(cas, 0, amt)
  if self.over or not B:IsBG() then return end
  local who = Actor(cas)
  if who then
    local x = X(who)
    x.sh[id] = (x.sh[id] or 0) + amt
    if amt > x.bigHeal then x.bigHeal, x.bigHealId, x.send = amt, id, true end
  end
  local v = Actor(tgt)
  if v and not self.pet[tgt] then X(v).healIn = X(v).healIn + amt end
end

function BS:OnDispel(caster, target)
  if self.over or not B:IsBG() then return end
  local who = Actor(caster)
  if not who then return end
  local x = X(who)
  local a, b = B:SideOf(caster), B:SideOf(target)
  if caster == target or (a and a == b) then x.cleanse = x.cleanse + 1
  elseif a and b then x.purge = x.purge + 1
  else x.dispel = x.dispel + 1 end
  x.send = true
end

-- Which spells count: id -> "int", "cc" or false, each worked out once.
local INTERRUPTS = { Kick = true, Pummel = true, ["Shield Bash"] = true, Counterspell = true, ["Spell Lock"] = true,
                     ["Deadly Throw"] = true, ["Earth Shock"] = true, ["Feral Charge"] = true }
BS.kind = {}
function BS:Kind(spell)
  local k = self.kind[spell]
  if k ~= nil then return k end
  local ok, name = pcall(SpellInfo or function() end, spell)
  local D = B.CDData
  if ok and name and INTERRUPTS[name] then k = "int"
  elseif D and D.DR_SPELLS and D.DR_SPELLS[spell] then k = "cc"
  else k = false end
  self.kind[spell] = k
  return k
end

function BS:OnGo(spell, caster, target, hit)
  local k = self:Kind(spell)
  if not k or caster == target or self.over or not B:IsBG() then return end
  if hit == 0 then return end     -- missed, resisted, immune
  local who = Actor(caster)
  if not who then return end
  local x = X(who)
  if k == "int" then
    local e = self.casting[target]
    if not e or GetTime() > e then return end
    x.int = x.int + 1
  else
    x.cc = x.cc + 1
  end
  x.send = true
end

-- Counts from another OctoBG: the highest of each, as for damage and healing.
function BS:MergeX(name, cleanse, purge, int, cc, taken, bigHit, bigHeal)
  if not name or string.len(name) < 2 or string.len(name) > 30 then return end
  local m = self.mx[name]
  if not m then
    if self.mxN >= 200 then return end
    m = {}
    self.mx[name] = m
    self.mxN = self.mxN + 1
  end
  m.cleanse, m.purge = math.max(m.cleanse or 0, cleanse or 0), math.max(m.purge or 0, purge or 0)
  m.int, m.cc = math.max(m.int or 0, int or 0), math.max(m.cc or 0, cc or 0)
  m.taken, m.bigHit = math.max(m.taken or 0, taken or 0), math.max(m.bigHit or 0, bigHit or 0)
  m.bigHeal = math.max(m.bigHeal or 0, bigHeal or 0)
end

local function SpellName(id)
  if id == 0 then return "Melee" end
  if id == -1 then return "Thorns" end
  local ok, name = pcall(SpellInfo or function() end, id)
  return ok and name or nil
end

-- The three biggest of a spell table, largest first.
local function Top(t)
  local list = {}
  for id, amt in pairs(t) do table.insert(list, { id, amt }) end
  table.sort(list, function(a, b) return a[2] > b[2] end)
  local out = {}
  for i = 1, math.min(3, table.getn(list)) do
    table.insert(out, { SpellName(list[i][1]) or "?", list[i][2] })
  end
  return out
end

-- Everything known about a player's game, ready to show.
function BS:Detail(name)
  local x = self.x[name] or X(name)
  local m = self.mx[name] or {}
  return { cleanse = math.max(x.cleanse, m.cleanse or 0), purge = math.max(x.purge, m.purge or 0), dispel = x.dispel,
           int = math.max(x.int, m.int or 0), cc = math.max(x.cc, m.cc or 0), taken = math.max(x.taken, m.taken or 0),
           healIn = x.healIn, bigHit = math.max(x.bigHit, m.bigHit or 0), bigHeal = math.max(x.bigHeal, m.bigHeal or 0),
           bigHitName = x.bigHitId and SpellName(x.bigHitId) or nil, bigHealName = x.bigHealId and SpellName(x.bigHealId) or nil,
           topD = Top(x.sd), topH = Top(x.sh) }
end

BS.x, BS.mx, BS.mxN, BS.pet, BS.casting = {}, {}, 0, {}, {}

-- Who is casting, on BOTH teams (Casts.lua keeps enemies only): guid -> when it ends.
-- A cast that failed stays for a moment: its failure can arrive just before the
-- kick that caused it. Cleared with the rest on entering a battleground.
B:On("UNIT_CASTEVENT", function(ev, caster, target, kind, spell, ms)
  if not caster then return end
  if kind == "START" or kind == "CHANNEL" then
    if ms and ms > 0 then BS.casting[caster] = GetTime() + ms / 1000 end
  elseif kind == "FAIL" then
    if BS.casting[caster] then BS.casting[caster] = GetTime() + 0.25 end
  elseif kind == "CAST" and BS.casting[caster] then
    BS.casting[caster] = nil
  end
end, true)

B:On("AUTO_ATTACK_SELF", function(ev, att, tgt, dmg) if tgt ~= att then BS:Hit(att, tgt, 0, dmg) end end, true)
B:On("AUTO_ATTACK_OTHER", function(ev, att, tgt, dmg) if tgt ~= att then BS:Hit(att, tgt, 0, dmg) end end, true)
B:On("SPELL_DAMAGE_EVENT_SELF", function(ev, tgt, cas, id, amt) if tgt ~= cas then BS:Hit(cas, tgt, id, amt) end end, true)
B:On("SPELL_DAMAGE_EVENT_OTHER", function(ev, tgt, cas, id, amt) if tgt ~= cas then BS:Hit(cas, tgt, id, amt) end end, true)
B:On("DAMAGE_SHIELD_SELF", function(ev, own, att, dmg) BS:Hit(own, att, -1, dmg) end, true)
B:On("DAMAGE_SHIELD_OTHER", function(ev, own, att, dmg) BS:Hit(own, att, -1, dmg) end, true)
-- BY_SELF and BY_OTHER cover every heal once (ON_SELF would count those on you twice)
B:On("SPELL_HEAL_BY_SELF", function(ev, tgt, cas, id, amt) BS:Mend(tgt, cas, id, amt) end, true)
B:On("SPELL_HEAL_BY_OTHER", function(ev, tgt, cas, id, amt) BS:Mend(tgt, cas, id, amt) end, true)
B:On("SPELL_DISPEL_BY_SELF", function(ev, cas, tgt) BS:OnDispel(cas, tgt) end, true)
B:On("SPELL_DISPEL_BY_OTHER", function(ev, cas, tgt) BS:OnDispel(cas, tgt) end, true)
B:On("SPELL_GO_SELF", function(ev, item, spell, cas, tgt, fl, hit) BS:OnGo(spell, cas, tgt, hit) end, true)
B:On("SPELL_GO_OTHER", function(ev, item, spell, cas, tgt, fl, hit) BS:OnGo(spell, cas, tgt, hit) end, true)

-- Held numbers find their names, and the counts go out to the team: yours
-- every time, then the ones that changed, a few at a time.
B:Every(4, function()
  if not B:IsBG() then return end
  for guid, p in pairs(BS.pending) do
    local who = Actor(guid)
    if who then Add(who, p.d, p.h) end
    if who ~= nil then
      BS.pending[guid] = nil
      BS.npending = BS.npending - 1
    end
  end
  BS:Share(5)
end, true)

function BS:Share(most)
  local SY = B.Sync
  if not SY or not SY:Worth() then return end
  local me = UnitName("player")
  local mine = self.totals[me]
  if mine then
    SY:Push("D", me .. "," .. mine.d .. "," .. mine.h)
    mine.changed = nil
  end
  local n = 0
  for name, t in pairs(self.totals) do
    if t.changed and name ~= me then
      SY:Push("D", name .. "," .. t.d .. "," .. t.h)
      t.changed = nil
      n = n + 1
      if n >= most then break end
    end
  end
  -- the hover panel's counts, those that changed, sent the same way
  n = 0
  for name, x in pairs(self.x) do
    if x.send or (name == me and x.taken ~= x.sentTaken) then
      SY:Push("X", name .. "," .. x.cleanse .. "," .. x.purge .. "," .. x.int .. "," .. x.cc .. "," .. x.taken .. "," .. x.bigHit .. "," .. x.bigHeal)
      x.send, x.sentTaken = nil, x.taken
      n = n + 1
      if n >= most then break end
    end
  end
end

local cvarDone
B:On("PLAYER_ENTERING_WORLD", function()
  if cvarDone or not GetNampowerVersion then return end
  cvarDone = true
  local ok, v = pcall(GetCVar, "NP_EnableSpellHealEvents")
  if ok and v ~= nil and v ~= "1" then pcall(SetCVar, "NP_EnableSpellHealEvents", "1") end
end)

-- ---------------------------------------------------------------- the data

-- The fixed columns; the battleground's own ones (flag captures...) are added
-- from GetBattlefieldStatInfo as "s1", "s2"...
local COLUMNS = {
  { key = "name", label = "Name", w = 195, left = true },
  { key = "kb", label = "KB", w = 38, tip = "Killing blows" },
  { key = "hk", label = "HK", w = 38, tip = "Honorable kills" },
  { key = "deaths", label = "Deaths", w = 52 },
  { key = "honor", label = "Honor", w = 52, tip = "Honor gained" },
  { key = "damage", label = "Damage", w = 76, tip = "Damage done (with pets and totems), counted by OctoBG" },
  { key = "healing", label = "Healing", w = 76, tip = "Healing done including overheal, counted by OctoBG" },
}

-- The game's data now: rows and the extra columns.
function BD:ReadGame()
  local rows, stats = {}, {}
  local nstat = GetNumBattlefieldStats and GetNumBattlefieldStats() or 0
  for j = 1, math.min(nstat, 7) do
    local text, _, tip = GetBattlefieldStatInfo(j)
    if text and text ~= "" then
      table.insert(stats, { key = "s" .. j, label = text, w = math.max(40, string.len(text) * 6 + 6), tip = tip, stat = j })
    end
  end
  -- how many rows share a name without its realm: two players called the same on
  -- different realms must not get each other's numbers
  local same = {}
  for i = 1, GetNumBattlefieldScores() do
    local s = U.ShortName((GetBattlefieldScore(i)))
    if s then same[s] = (same[s] or 0) + 1 end
  end
  for i = 1, GetNumBattlefieldScores() do
    local name, kb, hk, deaths, honor, fac, rank, race, class = GetBattlefieldScore(i)
    if name then
      local d, h = BS:Get(name)
      local short = U.ShortName(name)
      local key = name
      if d == 0 and h == 0 and short ~= name and same[short] == 1 then
        -- "Name-Realm" on one list and "Name" on the other
        d, h = BS:Get(short)
        key = short
      end
      -- the team played for (the raid overrules a row that disagrees, Core.lua), never the race
      local team = B:IsBG() and B:TeamOf(name) or ((fac == 0) and "Horde" or "Alliance")
      local r = { name = name, key = key, kb = kb or 0, hk = hk or 0, deaths = deaths or 0, honor = honor or 0, damage = d, healing = h,
                  fac = team, rank = rank, race = race, class = U.ClassToken(class), classText = class }
      if GetPVPRankInfo and rank then
        local rankName, rankNum = GetPVPRankInfo(rank, fac)
        r.rankName, r.rankNum = rankName, rankNum
      end
      for j = 1, table.getn(stats) do
        r[stats[j].key] = GetBattlefieldStatData(i, stats[j].stat) or 0
      end
      table.insert(rows, r)
    end
  end
  return rows, stats
end

-- A copy of the game for after you leave (one game kept).
function BD:Snapshot()
  local rows, stats = self:ReadGame()
  if not rows[1] then return end
  for i = 1, table.getn(rows) do rows[i].detail = BS:Detail(rows[i].key) end     -- the hover panel, after you leave
  local score, t = self:LiveScore()
  B.db.lastGame = { zone = B.zoneName, zoneKey = B.zone, winner = GetBattlefieldWinner and GetBattlefieldWinner() or nil,
                    rows = rows, stats = stats, when = date and date("%H:%M") or nil, score = score, time = t }
end

-- The sides' score now and the game's time as text.
function BD:LiveScore()
  local TM = B.Timers
  local P = TM.score
  local score = { Alliance = P.Alliance.cur, Horde = P.Horde.cur }
  local secs
  if BS.endedAt and TM.obj.begunAt then
    secs = BS.endedAt - TM.obj.begunAt
  elseif TM.obj.begunAt then
    secs = GetTime() - TM.obj.begunAt
  elseif GetBattlefieldInstanceRunTime then
    secs = (GetBattlefieldInstanceRunTime() or 0) / 1000
  end
  return score, (secs and secs > 0) and ("Time " .. B.BGScore.Clock(secs)) or nil
end

-- What the window shows: a preview, live in a battleground, else the last game.
-- Returns rows, extra columns, winner, name, live, zone key, score, time text.
function BD:Data()
  if self.preview then
    local sc = (self.preview == "WSG") and { Alliance = 3, Horde = 1 } or { Alliance = 2000, Horde = 1430 }
    return self:Sample(), {}, 1, nil, false, self.preview, sc, "Time 18:42"
  end
  if B:IsBG() and GetNumBattlefieldScores() > 0 then
    local rows, stats = self:ReadGame()
    local score, t = self:LiveScore()
    return rows, stats, GetBattlefieldWinner and GetBattlefieldWinner() or nil, B.zoneName, true, B.zone, score, t
  end
  local g = B.db.lastGame
  if g then return g.rows, g.stats or {}, g.winner, g.zone, false, g.zoneKey, g.score, g.time end
  return {}, {}, nil, nil, false
end

-- The visible columns in the saved order; columns not named yet go at the end.
function BD:Columns(stats)
  local db = B.db.board
  local all, byKey = {}, {}
  for i = 1, table.getn(COLUMNS) do
    table.insert(all, COLUMNS[i])
    byKey[COLUMNS[i].key] = COLUMNS[i]
  end
  for i = 1, table.getn(stats) do
    table.insert(all, stats[i])
    byKey[stats[i].key] = stats[i]
  end
  local out, seen = { COLUMNS[1] }, { name = true }
  for i = 1, table.getn(db.order) do
    local c = byKey[db.order[i]]
    if c and not seen[c.key] then
      seen[c.key] = true
      if not db.hide[c.key] then table.insert(out, c) end
    end
  end
  for i = 1, table.getn(all) do
    local c = all[i]
    if not seen[c.key] then
      seen[c.key] = true
      if not db.hide[c.key] then table.insert(out, c) end
    end
  end
  return out, all
end

-- Moves a column one place along the saved order (dir -1 left, 1 right).
function BD:MoveColumn(key, dir)
  local db = B.db.board
  local order = {}
  for _, c in ipairs(self.cols or {}) do
    if c.key ~= "name" then table.insert(order, c.key) end
  end
  for i = 1, table.getn(order) do
    if order[i] == key then
      local j = i + dir
      if order[j] then order[i], order[j] = order[j], order[i] end
      break
    end
  end
  -- hidden columns keep their place at the end
  for i = 1, table.getn(db.order) do
    local k = db.order[i]
    if db.hide[k] then table.insert(order, k) end
  end
  db.order = order
  self:Refresh()
end

function BD:SortBy(key)
  local db = B.db.board
  if db.sort == key then
    db.desc = not db.desc
  else
    db.sort, db.desc = key, key ~= "name"
  end
  self.offset = 0
  self:Refresh()
end

local function Short(n)
  n = n or 0
  if B.db.board.shortNumbers and n >= 10000 then
    return string.format("%.1fk", n / 1000)
  end
  return tostring(n)
end

-- ---------------------------------------------------------------- the window

-- Each battleground's look: its loading-screen picture behind the window (BGScore.lua's
-- list), the mark you earn there as its emblem, and an accent colour.
local THEMES = {
  WSG = { emblem = "Interface\\Icons\\INV_Misc_Rune_07", accent = { 0.62, 0.92, 0.45 }, name = "Warsong Gulch" },
  AB = { emblem = "Interface\\Icons\\INV_Jewelry_Amulet_07", accent = { 1, 0.82, 0.35 }, name = "Arathi Basin" },
  AV = { emblem = "Interface\\Icons\\INV_Jewelry_Necklace_21", accent = { 0.62, 0.85, 1 }, name = "Alterac Valley" },
  TG = { emblem = "Interface\\Icons\\INV_BannerPVP_02", accent = { 0.95, 0.62, 0.35 }, name = "Thorn Gorge" },
}
local NO_THEME = { emblem = "Interface\\Icons\\INV_BannerPVP_02", accent = { 1, 0.82, 0 }, name = "Scoreboard" }

-- The game's class icons (Blizzard's coordinates in the character create sheet).
local CLASS_SHEET = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"
local CLASS_TC = {
  WARRIOR = { 0, 0.25, 0, 0.25 }, MAGE = { 0.25, 0.49609375, 0, 0.25 }, ROGUE = { 0.49609375, 0.7421875, 0, 0.25 },
  DRUID = { 0.7421875, 0.98828125, 0, 0.25 }, HUNTER = { 0, 0.25, 0.25, 0.5 }, SHAMAN = { 0.25, 0.49609375, 0.25, 0.5 },
  PRIEST = { 0.49609375, 0.7421875, 0.25, 0.5 }, WARLOCK = { 0.7421875, 0.98828125, 0.25, 0.5 }, PALADIN = { 0, 0.25, 0.5, 0.75 },
}
local BAR_COL = { damage = { 1, 0.48, 0.12 }, healing = { 0.2, 0.85, 0.4 } }
local TEXT_COL = { damage = { 1, 0.78, 0.55 }, healing = { 0.6, 1, 0.7 } }
local HERO_H, FOOT_H = 84, 78

-- Sets a font from the settings; a file that doesn't load falls back.
local function Fnt(fs, key, size, outline)
  fs:SetFont(B.SpyData.Font(B.db.board[key], "Fonts\\FRIZQT__.TTF"), size, outline or "OUTLINE")
  return fs
end

function BD:Build()
  local f = CreateFrame("Frame", "OctoBGScoreboard", UIParent)
  f:SetWidth(680)
  f:SetHeight(500)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 30)
  f:SetFrameStrata("DIALOG")
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:EnableMouseWheel(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function() this:StartMoving() end)
  f:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
  f:SetScript("OnMouseWheel", function()
    BD.offset = BD.offset - arg1 * 3
    BD:Refresh()
  end)
  f:SetScript("OnHide", function()
    BD.preview = nil
    if BD.tip then BD.tip:Hide() end
  end)
  f:Hide()
  W.Skin(f, "window", 1)
  table.insert(UISpecialFrames, "OctoBGScoreboard")   -- Esc closes it
  self.frame = f

  -- the picture, on its own child frame (a texture sharing a layer with the
  -- backdrop has no set order); everything else on a child above it
  local art = CreateFrame("Frame", nil, f)
  art:SetPoint("TOPLEFT", f, "TOPLEFT", 11, -11)
  art:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -11, 11)
  art:SetFrameLevel(f:GetFrameLevel() + 1)
  self.pic = B.BGScore.MapArt(art)
  self.artFrame = art
  -- light over the top band so the map shows, darker over the table
  self.dimTop = U.Tex(art, U.WHITE, "BORDER")
  self.dimTop:SetVertexColor(0, 0, 0, 0.45)
  self.dimTop:SetPoint("TOPLEFT", art, "TOPLEFT", 0, 0)
  self.dimTop:SetPoint("TOPRIGHT", art, "TOPRIGHT", 0, 0)
  self.dimTop:SetHeight(HERO_H - 11)
  self.dimBody = U.Tex(art, U.WHITE, "BORDER")
  self.dimBody:SetVertexColor(0, 0, 0, 0.62)
  self.dimBody:SetPoint("TOPLEFT", self.dimTop, "BOTTOMLEFT", 0, 0)
  self.dimBody:SetPoint("BOTTOMRIGHT", art, "BOTTOMRIGHT", 0, 0)

  local c = CreateFrame("Frame", nil, f)
  c:SetAllPoints(f)
  c:SetFrameLevel(f:GetFrameLevel() + 3)
  self.c = c

  -- the plaque, over the gold edge
  self.plaque = U.Tex(c, "Interface\\DialogFrame\\UI-DialogBox-Header", "ARTWORK")
  self.plaque:SetWidth(400)
  self.plaque:SetHeight(64)
  self.plaque:SetPoint("TOP", f, "TOP", 0, 12)
  self.titleText = c:CreateFontString(nil, "OVERLAY")
  self.titleText:SetPoint("TOP", self.plaque, "TOP", 0, -13)

  -- the template hides its parent, here only the contents: this closes the window
  local close = CreateFrame("Button", nil, c, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)
  close:SetScript("OnClick", function() BD.frame:Hide() end)

  -- a dark plate behind the score, so it reads over any map
  local plate = CreateFrame("Frame", nil, c)
  plate:SetWidth(170)
  plate:SetHeight(44)
  plate:SetPoint("CENTER", f, "TOP", 0, -50)
  W.Skin(plate, "panel", 0.85)
  self.scorePlate = plate

  -- the band: emblem and result on the left, the score in the middle, tabs on the right
  self.emblem = U.Tex(c, nil, "ARTWORK")
  self.emblem:SetWidth(40)
  self.emblem:SetHeight(40)
  self.emblem:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -28)
  self.emblem:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  self.emblemRim = U.Tex(c, "Interface\\Buttons\\UI-Quickslot2", "OVERLAY")
  self.emblemRim:SetWidth(68)
  self.emblemRim:SetHeight(68)
  self.emblemRim:SetPoint("CENTER", self.emblem, "CENTER", 0, 0)
  self.result = c:CreateFontString(nil, "OVERLAY")
  self.result:SetPoint("TOPLEFT", self.emblem, "TOPRIGHT", 8, -2)
  self.elapsed = c:CreateFontString(nil, "OVERLAY")
  self.elapsed:SetPoint("TOPLEFT", self.result, "BOTTOMLEFT", 0, -3)

  self.scoreA = plate:CreateFontString(nil, "OVERLAY")
  self.scoreH = plate:CreateFontString(nil, "OVERLAY")
  self.scoreSep = plate:CreateFontString(nil, "OVERLAY")
  self.scoreSep:SetPoint("CENTER", f, "TOP", 0, -50)
  self.scoreA:SetPoint("RIGHT", self.scoreSep, "LEFT", -8, 0)
  self.scoreH:SetPoint("LEFT", self.scoreSep, "RIGHT", 8, 0)

  local tabs = { { "all", "All" }, { "Alliance", "Alliance" }, { "Horde", "Horde" } }
  self.tabs = {}
  for i = 1, 3 do
    local b = CreateFrame("Button", "OctoBGBoardTab" .. i, c, "UIPanelButtonTemplate")
    b:SetWidth((i == 1) and 44 or 66)
    b:SetHeight(20)
    if i == 1 then
      b:SetPoint("TOPRIGHT", f, "TOPRIGHT", -176, -56)
    else
      b:SetPoint("LEFT", self.tabs[i - 1], "RIGHT", 2, 0)
    end
    b:SetText(tabs[i][2])
    b.key = tabs[i][1]
    b:SetScript("OnClick", function()
      BD.tab, BD.offset = this.key, 0
      BD:Refresh()
    end)
    self.tabs[i] = b
  end

  self.orn = W.Ornament(c, 400)
  self.orn:SetPoint("TOP", f, "TOP", 0, -HERO_H + 8)

  -- the table on a dark panel
  local body = CreateFrame("Frame", nil, c)
  body:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -HERO_H)
  body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -18, FOOT_H)
  W.Skin(body, "panel", 0.55)
  self.body = body
  for i = 1, VISIBLE_MAX do
    local r = CreateFrame("Button", nil, body)
    r:SetHeight(ROW_H)
    r:SetPoint("TOPLEFT", body, "TOPLEFT", 6, -6 - HEAD_H - (i - 1) * ROW_H)
    r:SetPoint("TOPRIGHT", body, "TOPRIGHT", -6, -6 - HEAD_H - (i - 1) * ROW_H)
    r.bg = U.Tex(r, U.WHITE, "BACKGROUND")
    r.bg:SetAllPoints(r)
    -- the team: the whole row tinted, and a bold edge
    r.stripe = U.Tex(r, U.WHITE, "BORDER")
    r.stripe:SetWidth(5)
    r.stripe:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 0)
    r.stripe:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 0)
    r.icon = U.Tex(r, CLASS_SHEET, "ARTWORK")
    r.icon:SetWidth(ROW_H - 3)
    r.icon:SetHeight(ROW_H - 3)
    r.rank = U.Tex(r, nil, "ARTWORK")          -- the game's PvP rank badge
    r.rank:SetWidth(ROW_H - 3)
    r.rank:SetHeight(ROW_H - 3)
    r.rank:SetPoint("LEFT", r, "LEFT", 7 + ROW_H - 1, 0)
    -- you: gold lines over the team's tint, which stays
    r.meTop = U.Tex(r, U.WHITE, "OVERLAY")
    r.meTop:SetVertexColor(1, 0.82, 0.1, 0.9)
    r.meTop:SetHeight(1)
    r.meTop:SetPoint("TOPLEFT", r, "TOPLEFT", 5, 0)
    r.meTop:SetPoint("TOPRIGHT", r, "TOPRIGHT", 0, 0)
    r.meBot = U.Tex(r, U.WHITE, "OVERLAY")
    r.meBot:SetVertexColor(1, 0.82, 0.1, 0.9)
    r.meBot:SetHeight(1)
    r.meBot:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 5, 0)
    r.meBot:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", 0, 0)
    r.hl = U.Tex(r, W.ART.glow, "HIGHLIGHT")
    r.hl:SetAllPoints(r)
    r.hl:SetBlendMode("ADD")
    r.cells, r.bars = {}, {}
    r:SetScript("OnEnter", function() BD:RowTip(this) end)
    r:SetScript("OnLeave", function() if BD.tip then BD.tip:Hide() end end)
    r:Hide()
    self.rows[i] = r
  end

  -- the footer, three clear lines: team totals, how it was counted, buttons
  self.totalA = c:CreateFontString(nil, "OVERLAY")
  self.totalA:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 22, 56)
  self.totalH = c:CreateFontString(nil, "OVERLAY")
  self.totalH:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -22, 56)
  self.note = W.Font(c:CreateFontString(nil, "OVERLAY"), 10, 0.72, 0.72, 0.75)
  self.note:SetPoint("BOTTOM", f, "BOTTOM", 0, 40)
  self.note:SetHeight(12)

  local leave = CreateFrame("Button", "OctoBGBoardLeave", c, "UIPanelButtonTemplate")
  leave:SetWidth(150)
  leave:SetHeight(22)
  leave:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -18, 14)
  leave:SetText("Leave battleground")
  W.Font(getglobal("OctoBGBoardLeaveText"), 11, 1, 0.82, 0)
  leave:SetScript("OnClick", function()
    if LeaveBattlefield then LeaveBattlefield() end
    BD.frame:Hide()
  end)
  self.leave = leave
  local game = CreateFrame("Button", "OctoBGBoardGame", c, "UIPanelButtonTemplate")
  game:SetWidth(120)
  game:SetHeight(22)
  game:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 18, 14)
  game:SetText("The game's own")
  W.Font(getglobal("OctoBGBoardGameText"), 11, 1, 0.82, 0)
  game:SetScript("OnClick", function()
    BD.useGame = true
    BD:GameButton()
    BD.frame:Hide()
    if BD.origToggle then BD.origToggle() elseif WorldStateScoreFrame then ShowUIPanel(WorldStateScoreFrame) end
  end)
  self.gameBtn = game
  local hint = W.Font(c:CreateFontString(nil, "OVERLAY"), 10, 0.6, 0.6, 0.62)
  hint:SetPoint("BOTTOM", f, "BOTTOM", 0, 20)
  hint:SetText("Click a heading to sort, right-click to move it (Shift: left)")
end

function BD:Head(i)
  local h = self.heads[i]
  if h then return h end
  h = CreateFrame("Button", nil, self.body)
  h:SetHeight(HEAD_H - 2)
  h:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  h.text = h:CreateFontString(nil, "OVERLAY")
  h.arrow = U.Tex(h, "Interface\\Buttons\\UI-SortArrow", "OVERLAY")
  h.arrow:SetWidth(9)
  h.arrow:SetHeight(9)
  h.hl = U.Tex(h, W.ART.glow, "HIGHLIGHT")
  h.hl:SetAllPoints(h)
  h.hl:SetBlendMode("ADD")
  h:SetScript("OnClick", function()
    local key = this.key
    if arg1 == "RightButton" then
      if key ~= "name" then BD:MoveColumn(key, IsShiftKeyDown() and -1 or 1) end
    else
      BD:SortBy(key)
    end
  end)
  h:SetScript("OnEnter", function()
    if not this.tip then return end
    GameTooltip:SetOwner(this, "ANCHOR_BOTTOM")
    GameTooltip:AddLine(this.tip, 1, 1, 1, 1)
    GameTooltip:Show()
  end)
  h:SetScript("OnLeave", function() GameTooltip:Hide() end)
  self.heads[i] = h
  return h
end

-- The hover panel: one frame made once, its lines reused, shown on the same
-- frame the mouse arrives. Label on the left, number on the right, under plain headings.
local TIP_W, TIP_LINE, TIP_MAX = 250, 14, 40

function BD:BuildTip()
  local t = CreateFrame("Frame", "OctoBGBoardTip", UIParent)
  t:SetWidth(TIP_W)
  t:SetFrameStrata("TOOLTIP")
  t:SetClampedToScreen(true)
  t:EnableMouse(false)
  W.Skin(t, "panel", 0.96)
  t:Hide()
  t.lines = {}
  for i = 1, TIP_MAX do
    local l = t:CreateFontString(nil, "OVERLAY")
    local v = t:CreateFontString(nil, "OVERLAY")
    l:SetFont(B.SpyData.Font(B.db.board.fontName, "Fonts\\FRIZQT__.TTF"), 12, "")
    v:SetFont(B.SpyData.Font(B.db.board.fontNum, "Fonts\\FRIZQT__.TTF"), 12, "")
    l:SetPoint("TOPLEFT", t, "TOPLEFT", 10, -8 - (i - 1) * TIP_LINE)
    v:SetPoint("TOPRIGHT", t, "TOPRIGHT", -10, -8 - (i - 1) * TIP_LINE)
    t.lines[i] = { l = l, v = v }
  end
  self.tip = t
end

function BD:RowTip(r)
  local e = r.entry
  if not self.tip then self:BuildTip() end
  local t = self.tip
  if not e then
    t:Hide()
    return
  end
  local d = e.detail or BS:Detail(e.key or e.name)
  local n = 0
  local function Line(left, right, lr, lg, lb, vr, vg, vb)
    if n >= TIP_MAX then return end
    n = n + 1
    local L = t.lines[n]
    L.l:SetText(left)
    L.l:SetTextColor(lr or 0.82, lg or 0.82, lb or 0.85)
    L.v:SetText(right or "")
    L.v:SetTextColor(vr or 1, vg or 1, vb or 1)
    L.l:Show()
    L.v:Show()
  end
  -- a number, grey when nothing happened yet
  local function Num(label, v)
    v = v or 0
    if v == 0 then Line(label, "0", 0.55, 0.55, 0.58, 0.45, 0.45, 0.47) else Line(label, Short(v)) end
  end
  local function Head(text, cr, cg, cb) Line(text, "", cr or 1, cg or 0.82, cb or 0) end
  local cr, cg, cb = U.ClassColor(e.class)
  local fc = U.FACTION[e.fac] or U.FACTION.Alliance
  Line(e.name, e.fac, cr, cg, cb, math.min(1, fc[1] + 0.25), math.min(1, fc[2] + 0.25), math.min(1, fc[3] + 0.25))
  local who = (e.race and (e.race .. " ") or "") .. (e.classText or "")
  if e.rankName and e.rankName ~= "" then who = who .. " - " .. e.rankName end
  Line(who, "", 0.6, 0.6, 0.62)
  Head("Score")
  Num("Killing blows", e.kb)
  Num("Honorable kills", e.hk)
  Num("Deaths", e.deaths)
  Num("Honor", e.honor)
  for j = 1, table.getn(self.cols or {}) do
    local c = self.cols[j]
    if c.stat then Num(c.label, e[c.key]) end
  end
  Head("Damage", 1, 0.62, 0.3)
  Num("Done", e.damage)
  Num("Taken", d.taken)
  Line("Biggest hit" .. (d.bigHitName and (" (" .. d.bigHitName .. ")") or ""), Short(d.bigHit or 0))
  for i = 1, table.getn(d.topD or {}) do
    Line("   " .. d.topD[i][1], Short(d.topD[i][2]), 0.65, 0.65, 0.68, 0.8, 0.8, 0.8)
  end
  Head("Healing", 0.45, 0.95, 0.55)
  Num("Done", e.healing)
  Num("Received", d.healIn)
  Line("Biggest heal" .. (d.bigHealName and (" (" .. d.bigHealName .. ")") or ""), Short(d.bigHeal or 0))
  for i = 1, table.getn(d.topH or {}) do
    Line("   " .. d.topH[i][1], Short(d.topH[i][2]), 0.65, 0.65, 0.68, 0.8, 0.8, 0.8)
  end
  Head("Control and support", 0.55, 0.8, 1)
  Num("Interrupts", d.int)
  Num("Crowd control", d.cc)
  Num("Cleanses (off allies)", d.cleanse)
  Num("Purges (off enemies)", d.purge)
  if (d.dispel or 0) > 0 then Num("Other dispels", d.dispel) end
  for i = n + 1, TIP_MAX do
    t.lines[i].l:Hide()
    t.lines[i].v:Hide()
  end
  t:SetHeight(n * TIP_LINE + 16)
  t:ClearAllPoints()
  t:SetPoint("TOPLEFT", r, "TOPRIGHT", 14, 6)
  t:Show()
end

local function Cell(r, j)
  local c = r.cells[j]
  if not c then
    c = r:CreateFontString(nil, "OVERLAY")
    r.cells[j] = c
  end
  return c
end

local function ValueBar(r, j)
  local b = r.bars[j]
  if not b then
    b = U.Tex(r, U.WHITE, "BORDER")
    r.bars[j] = b
  end
  return b
end

-- Sample rows for the preview of a battleground's look.
local SAMPLE = {
  { "Brightshield", "PALADIN", "Alliance", 5, 6, 3, 247, 19732, 1620 }, { "Shadowpact-NZ", "WARLOCK", "Horde", 3, 3, 2, 247, 27291, 2599 },
  { "Frostcog", "MAGE", "Alliance", 2, 4, 1, 247, 15425, 1681 }, { "Quickblade-NZ", "ROGUE", "Horde", 6, 5, 2, 247, 23442, 0 },
  { "Bloomroot-NZ", "DRUID", "Horde", 0, 5, 3, 247, 2914, 21852 }, { "Stormcall-NZ", "SHAMAN", "Alliance", 1, 4, 0, 247, 8100, 14770 },
  { "Lightwell", "PRIEST", "Alliance", 0, 3, 2, 247, 1200, 28832 }, { "Longshot", "HUNTER", "Horde", 2, 4, 4, 247, 12050, 0 },
  { "Ironhide-NZ", "WARRIOR", "Horde", 3, 4, 1, 247, 16300, 0 }, { "Daggerdusk", "ROGUE", "Alliance", 4, 6, 2, 247, 21070, 0 },
}
function BD:Sample()
  local rows = {}
  for i = 1, table.getn(SAMPLE) do
    local s = SAMPLE[i]
    table.insert(rows, { name = s[1], class = s[2], classText = s[2], fac = s[3], kb = s[4], hk = s[5], deaths = s[6],
                         honor = s[7], damage = s[8], healing = s[9],
                         detail = { cleanse = math.mod(i * 3, 7), purge = math.mod(i * 5, 6), int = math.mod(i, 4), cc = math.mod(i * 2, 9),
                                    taken = 9000 + i * 1200, healIn = 4000 + i * 700, bigHit = math.floor(s[8] / 12), bigHitName = "Sample Strike",
                                    bigHeal = math.floor(s[9] / 10), bigHealName = (s[9] > 0) and "Sample Heal" or nil,
                                    topD = { { "Sample Strike", math.floor(s[8] / 2) }, { "Melee", math.floor(s[8] / 3) } }, topH = {} } })
  end
  return rows
end

-- Previews a battleground's look with sample players.
function BD:Preview(key)
  if not self.frame then self:Build() end
  self.preview = key
  self.frame:Show()
  self:Refresh()
end

-- A team's heading row: its flag and name in a solid band, its totals in the columns.
function BD:PaintHeading(r, e, cols, meFac)
  local fc = U.FACTION[e.header]
  r.entry = nil
  r.bg:SetVertexColor(fc[1], fc[2], fc[3], 0.55)
  r.stripe:SetVertexColor(fc[1], fc[2], fc[3], 1)
  r.icon:Hide()
  r.rank:Hide()
  r.meTop:Hide()
  r.meBot:Hide()
  for j = 1, table.getn(cols) do
    local c = cols[j]
    local cell = Cell(r, j)
    cell:ClearAllPoints()
    if r.bars[j] then r.bars[j]:Hide() end
    if c.key == "name" then
      Fnt(cell, "fontHead", 15)
      cell:SetPoint("LEFT", r, "LEFT", 10, 0)
      cell:SetWidth(c.dw - 12)
      cell:SetHeight(ROW_H)
      cell:SetJustifyH("LEFT")
      local label = string.upper(e.header)
      if meFac then label = label .. ((e.header == meFac) and " - YOUR TEAM" or " - ENEMY") end
      cell:SetText(label)
      cell:SetTextColor(1, 1, 1)
    else
      Fnt(cell, "fontNum", 13)
      cell:SetPoint("RIGHT", r, "LEFT", c.x - 6 + c.dw - 3, 0)
      cell:SetWidth(c.dw)
      cell:SetJustifyH("RIGHT")
      local v = e.sums[c.key] or 0
      cell:SetText(BAR_COL[c.key] and Short(v) or tostring(v))
      cell:SetTextColor(1, 1, 1)
    end
    cell:Show()
  end
  for j = table.getn(cols) + 1, table.getn(r.cells) do r.cells[j]:Hide() end
  for j = table.getn(cols) + 1, table.getn(r.bars) do
    if r.bars[j] then r.bars[j]:Hide() end
  end
  r:Show()
end

function BD:Refresh()
  local f = self.frame
  if not f or not f:IsShown() then return end
  local db = B.db.board
  local rows, stats, winner, zone, live, zoneKey, score, timeText = self:Data()
  local cols = self:Columns(stats)
  self.cols = cols
  local theme = THEMES[zoneKey or ""] or NO_THEME
  local ac = theme.accent
  -- the battleground's picture, emblem and title
  local mapData = zoneKey and B.Map.DATA[zoneKey]
  self.pic:Set(mapData and mapData.file or nil)
  self.dimBody:SetVertexColor(0, 0, 0, db.dark or 0.62)
  self.emblem:SetTexture(theme.emblem)
  Fnt(self.titleText, "fontHead", 16)
  self.titleText:SetText((zone or theme.name) .. " Scoreboard")
  self.titleText:SetTextColor(ac[1], ac[2], ac[3])
  -- result
  Fnt(self.result, "fontHead", 20)
  if winner == 0 or winner == 1 then
    local side = (winner == 0) and "Horde" or "Alliance"
    self.result:SetText(side .. " wins" .. ((not live and not self.preview) and " (last game)" or ""))
    local c = U.FACTION[side]
    self.result:SetTextColor(math.min(1, c[1] + 0.25), math.min(1, c[2] + 0.25), math.min(1, c[3] + 0.25))
  elseif live then
    self.result:SetText("In progress")
    self.result:SetTextColor(ac[1], ac[2], ac[3])
  else
    self.result:SetText(rows[1] and "Last game" or "No game yet")
    self.result:SetTextColor(ac[1], ac[2], ac[3])
  end
  Fnt(self.elapsed, "fontNum", 12)
  self.elapsed:SetText(timeText or "")
  self.elapsed:SetTextColor(0.85, 0.85, 0.85)
  -- the score
  local sa, sh = score and score.Alliance, score and score.Horde
  if sa or sh then
    Fnt(self.scoreA, "fontHead", 30, "THICKOUTLINE")
    Fnt(self.scoreH, "fontHead", 30, "THICKOUTLINE")
    Fnt(self.scoreSep, "fontHead", 22)
    self.scoreA:SetText(sa or 0)
    self.scoreA:SetTextColor(0.5, 0.75, 1)
    self.scoreH:SetText(sh or 0)
    self.scoreH:SetTextColor(1, 0.45, 0.4)
    self.scoreSep:SetText(":")
    self.scoreSep:SetTextColor(ac[1], ac[2], ac[3])
  else
    Fnt(self.scoreSep, "fontHead", 22)
    self.scoreSep:SetText("")
    self.scoreA:SetText("")
    self.scoreH:SetText("")
  end
  -- tabs: the chosen one lit
  for i = 1, 3 do
    local b = self.tabs[i]
    local t = getglobal(b:GetName() .. "Text")
    if b.key == self.tab then
      b:LockHighlight()
      W.Font(t, 11, 1, 1, 1)
    else
      b:UnlockHighlight()
      if b.key == "Alliance" then W.Font(t, 11, 0.55, 0.78, 1)
      elseif b.key == "Horde" then W.Font(t, 11, 1, 0.5, 0.45)
      else W.Font(t, 11, 1, 0.82, 0) end
    end
  end
  -- filter and sort
  local list = {}
  local totals = { Alliance = { n = 0, d = 0, h = 0, kb = 0 }, Horde = { n = 0, d = 0, h = 0, kb = 0 } }
  local best = { damage = 0, healing = 0, kb = 0, hk = 0, honor = 0 }
  for i = 1, table.getn(rows) do
    local e = rows[i]
    local t = totals[e.fac]
    t.n, t.d, t.h, t.kb = t.n + 1, t.d + e.damage, t.h + e.healing, t.kb + e.kb
    if self.tab == "all" or self.tab == e.fac then table.insert(list, e) end
    for k in pairs(best) do
      if (e[k] or 0) > best[k] then best[k] = e[k] end
    end
  end
  local key, desc = db.sort, db.desc
  table.sort(list, function(a, b)
    local x, y = a[key], b[key]
    if x == nil then x = 0 end
    if y == nil then y = 0 end
    if x == y then return a.name < b.name end
    if type(x) ~= type(y) then return tostring(x) < tostring(y) end
    if desc then return x > y end
    return x < y
  end)
  self.list = list
  -- what the rows show: each team under its own heading, or (setting off) all mixed
  local shown = list
  local meFac
  local me = UnitName("player")
  for i = 1, table.getn(rows) do
    if rows[i].name == me then meFac = rows[i].fac end
  end
  if self.tab == "all" and db.group then
    shown = {}
    for _, fac in ipairs({ "Alliance", "Horde" }) do
      local head
      for i = 1, table.getn(list) do
        if list[i].fac == fac then
          if not head then
            head = { header = fac, sums = {} }
            table.insert(shown, head)
          end
          for j = 1, table.getn(cols) do
            local k = cols[j].key
            if k ~= "name" then head.sums[k] = (head.sums[k] or 0) + (tonumber(list[i][k]) or 0) end
          end
          table.insert(shown, list[i])
        end
      end
    end
  end
  self.shown = shown
  -- sizes: the window fits the columns and the players (up to the rows setting)
  local used = 0
  for j = 1, table.getn(cols) do used = used + cols[j].w end
  local wide = math.max(680, used + 54)
  f:SetWidth(wide)
  local vis = math.max(10, math.min(VISIBLE_MAX, db.rows or 20, table.getn(shown)))
  local tall = HERO_H + 12 + HEAD_H + vis * ROW_H + FOOT_H
  f:SetHeight(tall)
  self.pic:Fit(wide - 22, tall - 22)     -- inside the frame's edge; covers it, never stretched
  self.orn:SetWidth(wide - 80)
  -- headings
  local x = 6
  local spare = wide - 54 - used
  for j = 1, table.getn(cols) do
    local c = cols[j]
    local h = self:Head(j)
    local w = c.w + ((j == 1) and spare or 0)
    h.key, h.tip = c.key, c.tip or c.label
    h:SetWidth(w)
    h:ClearAllPoints()
    h:SetPoint("TOPLEFT", self.body, "TOPLEFT", x, -5)
    Fnt(h.text, "fontHead", 15, "")
    h.text:SetTextColor(ac[1], ac[2], ac[3])
    h.text:ClearAllPoints()
    h.arrow:ClearAllPoints()
    if c.left then
      h.text:SetPoint("LEFT", h, "LEFT", 4, 0)
      h.arrow:SetPoint("LEFT", h.text, "RIGHT", 3, 0)
    else
      h.text:SetPoint("RIGHT", h, "RIGHT", -3, 0)
      h.arrow:SetPoint("RIGHT", h.text, "LEFT", -3, 0)
    end
    h.text:SetText(c.label)
    if key == c.key then
      if desc then h.arrow:SetTexCoord(0, 0.5625, 0, 1) else h.arrow:SetTexCoord(0, 0.5625, 1, 0) end
      h.arrow:Show()
    else
      h.arrow:Hide()
    end
    h:Show()
    c.x, c.dw = x, w
    x = x + w
  end
  for j = table.getn(cols) + 1, table.getn(self.heads) do self.heads[j]:Hide() end
  -- rows
  local n = table.getn(shown)
  local maxOff = math.max(0, n - vis)
  if self.offset > maxOff then self.offset = maxOff end
  if self.offset < 0 then self.offset = 0 end
  for i = 1, VISIBLE_MAX do
    local r = self.rows[i]
    local e = (i <= vis) and shown[i + self.offset]
    if e and e.header then
      self:PaintHeading(r, e, cols, meFac)
    elseif e then
      r.entry = e
      local fc = U.FACTION[e.fac] or U.FACTION.Alliance
      -- the whole row in its team's colour, every second one a touch stronger
      r.bg:SetVertexColor(fc[1], fc[2], fc[3], (math.mod(i, 2) == 0) and 0.26 or 0.18)
      r.stripe:SetVertexColor(fc[1], fc[2], fc[3], 1)
      if e.name == me then
        r.meTop:Show()
        r.meBot:Show()
      else
        r.meTop:Hide()
        r.meBot:Hide()
      end
      for j = 1, table.getn(cols) do
        local c = cols[j]
        local cell = Cell(r, j)
        cell:ClearAllPoints()
        local bar = r.bars[j]
        if c.key == "name" then
          local cr, cg, cb = U.ClassColor(e.class)
          local tc = CLASS_TC[e.class or ""]
          r.icon:ClearAllPoints()
          r.icon:SetPoint("LEFT", r, "LEFT", 7, 0)
          if tc then
            r.icon:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
            r.icon:Show()
          else
            r.icon:Hide()
          end
          if e.rankNum and e.rankNum > 0 then
            r.rank:SetTexture(string.format("Interface\\PvPRankBadges\\PvPRank%02d", e.rankNum))
            r.rank:Show()
          else
            r.rank:Hide()
          end
          Fnt(cell, "fontName", 14)
          cell:SetPoint("LEFT", r, "LEFT", 8 + 2 * ROW_H, 0)
          cell:SetWidth(c.dw - 2 * ROW_H - 8)
          cell:SetHeight(ROW_H)
          cell:SetJustifyH("LEFT")
          cell:SetText(e.name)
          cell:SetTextColor(cr, cg, cb)
          if bar then bar:Hide() end
        else
          Fnt(cell, "fontNum", 13)
          cell:SetPoint("RIGHT", r, "LEFT", c.x - 6 + c.dw - 3, 0)
          cell:SetWidth(c.dw)
          cell:SetJustifyH("RIGHT")
          local v = e[c.key] or 0
          local isMeter = BAR_COL[c.key]
          cell:SetText(isMeter and Short(v) or tostring(v))
          -- the best in a column in gold, nothing yet greyed out, damage and healing in their colours
          if v == 0 then
            cell:SetTextColor(0.45, 0.45, 0.47)
          elseif best[c.key] and v == best[c.key] and c.key ~= "honor" then
            cell:SetTextColor(1, 0.82, 0.2)
          elseif isMeter then
            local tc = TEXT_COL[c.key]
            cell:SetTextColor(tc[1], tc[2], tc[3])
          else
            cell:SetTextColor(1, 1, 1)
          end
          -- damage and healing: a bar behind the number, against the column's best
          if isMeter and v > 0 and best[c.key] > 0 then
            bar = ValueBar(r, j)
            bar:ClearAllPoints()
            bar:SetPoint("BOTTOMRIGHT", r, "BOTTOMLEFT", c.x - 6 + c.dw - 1, 1)
            bar:SetHeight(ROW_H - 2)
            bar:SetWidth(math.max(1, (c.dw - 6) * v / best[c.key]))
            bar:SetVertexColor(isMeter[1], isMeter[2], isMeter[3], 0.3)
            bar:Show()
          elseif bar then
            bar:Hide()
          end
        end
        cell:Show()
      end
      for j = table.getn(cols) + 1, table.getn(r.cells) do r.cells[j]:Hide() end
      for j = table.getn(cols) + 1, table.getn(r.bars) do
        if r.bars[j] then r.bars[j]:Hide() end
      end
      r:Show()
    else
      r:Hide()
    end
  end
  -- footer
  local A, H = totals.Alliance, totals.Horde
  Fnt(self.totalA, "fontNum", 12)
  Fnt(self.totalH, "fontNum", 12)
  self.totalA:SetTextColor(0.55, 0.78, 1)
  self.totalH:SetTextColor(1, 0.5, 0.45)
  self.totalA:SetText(string.format("Alliance: %d players, %s damage, %s healing", A.n, Short(A.d), Short(A.h)))
  self.totalH:SetText(string.format("Horde: %d players, %s damage, %s healing", H.n, Short(H.d), Short(H.h)))
  local users = (B.Sync and B.Sync.nusers or 0) + 1
  if not B.env.nampower then
    self.note:SetText("Damage and healing need nampower, which isn't running.")
  elseif users > 1 then
    self.note:SetText("Damage and healing as seen by you and " .. (users - 1) .. " other OctoBG user" .. ((users > 2) and "s" or "") .. " (hover a player for more)")
  else
    self.note:SetText("Damage and healing as seen by your client: far-off fights can be missing (hover a player for more)")
  end
  if live and winner ~= nil and LeaveBattlefield then self.leave:Show() else self.leave:Hide() end
  if WorldStateScoreFrame and B:IsBG() and not self.preview then self.gameBtn:Show() else self.gameBtn:Hide() end
end

function BD:Open()
  if not self.frame then self:Build() end
  self.useGame = nil
  -- the scoreboard's own filter could leave one side out (the game's tabs set it)
  if SetBattlefieldScoreFaction and B:IsBG() then SetBattlefieldScoreFaction(nil) end
  if RequestBattlefieldScoreData and B:IsBG() then RequestBattlefieldScoreData() end
  self.frame:Show()
  self:Refresh()
end

-- The way back: a button on the game's own frame that returns to this one.
function BD:GameButton()
  if self.backBtn or not WorldStateScoreFrame then return end
  local b = CreateFrame("Button", "OctoBGBoardBack", WorldStateScoreFrame, "UIPanelButtonTemplate")
  b:SetWidth(140)
  b:SetHeight(22)
  b:SetPoint("BOTTOMRIGHT", WorldStateScoreFrame, "BOTTOMRIGHT", -14, 12)
  b:SetFrameLevel(WorldStateScoreFrame:GetFrameLevel() + 8)
  b:SetText("OctoBG scoreboard")
  W.Font(getglobal("OctoBGBoardBackText"), 11, 1, 0.82, 0)
  b:SetScript("OnClick", function()
    BD.useGame = nil
    if HideUIPanel then HideUIPanel(WorldStateScoreFrame) else WorldStateScoreFrame:Hide() end
    BD:Open()
  end)
  self.backBtn = b
end

function BD:Toggle()
  if self.frame and self.frame:IsShown() then self.frame:Hide() else self:Open() end
end

function OctoBG_ToggleScoreboard() BD:Toggle() end

-- ---------------------------------------------------------------- wiring

B:On("UPDATE_BATTLEFIELD_SCORE", function() BD:Refresh() end)

B:On("OBG_ZONE", function(ev, z, old)
  if B:IsBG() then
    BS:Reset()
  elseif old and old ~= "ARENA" and not BS.over then
    -- left before the end: nothing more to read; the last snapshot stands
    BS.over = true
  end
  if BD.frame and BD.frame:IsShown() then BD:Refresh() end
end)

-- The game ended: the numbers freeze, the team gets the final counts, the board
-- opens in place of the game's frame. While open it keeps asking the server.
B:Every(0.5, function()
  if not B:IsBG() then return end
  local winner = GetBattlefieldWinner and GetBattlefieldWinner()
  local db = B.db.board
  if winner ~= nil and not BS.over then
    BS.over, BS.endedAt = true, GetTime()
    BS:Share(100)
    if RequestBattlefieldScoreData then RequestBattlefieldScoreData() end
    BD.pendingOpen = db.auto
    BD.openAt = GetTime() + 1    -- a moment for the last score and counts to arrive
  end
  if BD.pendingOpen and GetTime() >= (BD.openAt or 0) then
    BD.pendingOpen = nil
    BD:Snapshot()
    BD:Open()
  end
  if winner ~= nil and db.replace and not BD.useGame and BD.frame and BD.frame:IsShown()
     and WorldStateScoreFrame and WorldStateScoreFrame:IsVisible() then
    HideUIPanel(WorldStateScoreFrame)
  end
end, true)

B:Every(5, function()
  if B:IsBG() and BD.frame and BD.frame:IsShown() then
    if RequestBattlefieldScoreData then RequestBattlefieldScoreData() end
  end
end, true)
-- kept up to date, so leaving early or disconnecting still leaves a last game to read
B:Every(15, function()
  if B:IsBG() then BD:Snapshot() end
end, true)

-- The game's scoreboard key opens this one (option; the window has a button to the game's own).
B:On("OBG_INIT", function()
  BD:GameButton()
  if ToggleWorldStateScoreFrame and not BD.origToggle then
    BD.origToggle = ToggleWorldStateScoreFrame
    ToggleWorldStateScoreFrame = function()
      if B.db.board.replace and B:IsBG() and not BD.useGame then
        BD:Toggle()
      else
        BD.useGame = nil
        BD.origToggle()
      end
    end
  end
end)

B:Command("score", "the scoreboard: this game, or the last one", function() BD:Toggle() end)
