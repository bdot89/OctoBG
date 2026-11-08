-- OctoBG :: flag carriers (Warsong Gulch and any capture-the-flag map)
-- Who carries which flag, health, distance, where they are in plain words and
-- an arrow pointing at them. Each row is a button:
--   left-click   target the carrier (SuperWoW GUID, else exact name)
--   right-click  target and cast the flag spell (Mind Vision for priests)
--   ctrl-click   post the carrier's health and position to /bg
-- The server sends every carrier's map position to the whole battleground
-- (GetBattlefieldFlagPosition), so the enemy carrier is found even when far
-- out of sight; up close SuperWoW's position adds the height (roof, tunnel).

local B = OctoBG
local U = B.U
local M = B.Map
local W = B.W
local F = { carriers = {}, pos = {}, rows = {}, cdScratch = {} }
B.Flags = F
local raw = {}   -- flag map positions by token faction: { mx, my, t }

local ROW_H = 30
local FAC = { alliance = "Alliance", horde = "Horde" }
local OTHER = { Alliance = "Horde", Horde = "Alliance" }
local CLASS_SPELL = { PRIEST = "Mind Vision", HUNTER = "Hunter's Mark" }

-- System messages, matched lowercased (as LazyPig does on this client). The
-- () captures mark where the name sits so it is cut from the original text
-- with its case intact.
local PICKUP = "the (%a+) flag was picked up by ()(.-)()!"
local DROPPED = "the (%a+) flag was dropped by ()(.-)()!"
local CAPTURED = "^()(.-)() captured the (%a+) flag"
local RETURNED = "the (%a+) flag was returned to its base"
local PLACED_ONE = "the (%a+) flag is now placed at its base"
local PLACED_ALL = "flags are now placed at their bases"

function F:Spell()
  local s = B.db.flags.spell
  if s == nil then
    local _, class = UnitClass("player")
    s = CLASS_SPELL[class or ""] or ""
  end
  return s
end

-- The enemy carries our flag; we carry theirs.
function F:Enemy()
  if B.test and self.samples then return self.samples.enemy end
  return B.faction and self.carriers[B.faction]
end

function F:Friend()
  if B.test and self.samples then return self.samples.friend end
  return B.enemy and self.carriers[B.enemy]
end

-- Our carrier's unit: "Name-NZ" in the flag message can be "Name" in the raid.
local function RaidUnit(name)
  if UnitName("player") == name then return "player" end
  local short = U.ShortName(name)
  for i = 1, GetNumRaidMembers() do
    if U.ShortName(UnitName("raid" .. i)) == short then return "raid" .. i end
  end
  for i = 1, GetNumPartyMembers() do
    if U.ShortName(UnitName("party" .. i)) == short then return "party" .. i end
  end
  return nil
end

-- The class from the scoreboard, from the carrier's own team's rows.
local function ScoreClass(name, team)
  local short = U.ShortName(name)
  for i = 1, GetNumBattlefieldScores() do
    local n, _, _, _, _, _, _, _, class = GetBattlefieldScore(i)
    if n == name or (U.ShortName(n) == short and (not team or B:TeamOf(n) == team)) then
      return U.ClassToken(class)
    end
  end
  return nil
end

-- ---------------------------------------------------------------- state

function F:SetCarrier(flag, name)
  local c = { name = name, flag = flag, faction = OTHER[flag], since = GetTime() }
  c.enemy = (c.faction ~= B.faction)
  self.carriers[flag] = c
  self.any = true
  self:Resolve(c)
  if B.db.flags.alerts then
    if c.enemy then
      local r, g, b = U.ClassColor(c.class)
      U.Alert("EFC: " .. name, r, g, b, true)
    else
      U.Alert("We have their flag: " .. name, 0.3, 1, 0.3, false)
    end
  end
  self:Refresh()
end

-- Our side became known (or changed) mid-game: the EFC is whoever carries OUR
-- flag, so every carrier is judged again and its unit / class looked up anew.
B:On("OBG_TEAM", function()
  for _, c in pairs(F.carriers) do
    c.enemy = (c.faction ~= B.faction)
    c.unit, c.guid = nil, nil
    F:Resolve(c)
  end
  F:Refresh()
end)

-- The flag map tokens were learned before battlegrounds went cross-faction;
-- a game played for the other side could have taught them backwards: learn once more.
B:On("OBG_INIT", function()
  if (B.db.flagTokensV or 0) < 2 then
    B.db.flagTokens, B.db.flagTokensV = nil, 2
  end
end)

function F:Dropped(flag)
  local c = self.carriers[flag]
  if c then
    c.dropped = true
    c.droppedAt = GetTime()
  end
  if B.db.flags.alerts and flag == B.faction then
    U.Alert("Our flag was dropped!", 1, 0.82, 0, false)
  end
  self:Refresh()
end

function F:Clear(flag)
  self.carriers[flag] = nil
  self.pos[flag] = nil
  self:Refresh()
end

function F:Resolve(c)
  if not c.enemy then
    c.unit = RaidUnit(c.name)
    if c.unit then
      c.guid = U.GuidOf(c.unit)
      local _, cl = UnitClass(c.unit)
      c.class = cl
    end
  else
    local u = B.Tracker:FindByName(c.name)
    if u then
      c.guid = u.guid
      c.class = u.class
    end
  end
  if not c.class then c.class = ScoreClass(c.name, c.faction) end
end

local function OnSystem(ev, msg)
  if not msg then return end
  local low = string.lower(msg)
  local _, _, fw, p1, _, p2 = string.find(low, PICKUP)
  if fw and FAC[fw] then
    F:SetCarrier(FAC[fw], string.sub(msg, p1, p2 - 1))
    return
  end
  _, _, fw = string.find(low, DROPPED)
  if fw and FAC[fw] then
    F:Dropped(FAC[fw])
    return
  end
  local _, _, _, _, _, cw = string.find(low, CAPTURED)
  if cw and FAC[cw] then
    F:Clear("Alliance")
    F:Clear("Horde")
    return
  end
  _, _, fw = string.find(low, RETURNED)
  if not fw then _, _, fw = string.find(low, PLACED_ONE) end
  if fw and FAC[fw] then
    F:Clear(FAC[fw])
    return
  end
  if string.find(low, PLACED_ALL, 1, true) then
    F:Clear("Alliance")
    F:Clear("Horde")
  end
end

B:On("CHAT_MSG_BG_SYSTEM_ALLIANCE", OnSystem, true)
B:On("CHAT_MSG_BG_SYSTEM_HORDE", OnSystem, true)
B:On("CHAT_MSG_BG_SYSTEM_NEUTRAL", OnSystem, true)

B:On("OBG_ZONE", function()
  F.carriers = {}
  F.pos = {}
  raw = {}
  F.any = false
  F:Refresh()
end)

-- ---------------------------------------------------------------- live data

function F:Update(c, now, px, py)
  if not c.enemy then
    if not c.unit or UnitName(c.unit) ~= c.name then c.unit = RaidUnit(c.name) end
    if c.unit then c.guid = U.GuidOf(c.unit) end
  elseif not c.guid or not U.GuidExists(c.guid) then
    local u = B.Tracker:FindByName(c.name)
    if u then c.guid = u.guid end
    if UnitName("target") == c.name then c.guid = U.GuidOf("target") end
    if UnitName("mouseover") == c.name then c.guid = U.GuidOf("mouseover") end
  end
  if not c.class then
    if c.guid and U.GuidExists(c.guid) then
      local _, cl = UnitClass(c.guid)
      c.class = cl
    end
    if not c.class then c.class = ScoreClass(c.name, c.faction) end
  end

  local live = c.unit
  if not live and c.guid and U.GuidExists(c.guid) then live = c.guid end
  if live then
    c.hp, c.hpmax = UnitHealth(live), UnitHealthMax(live)
    self:ScanStacks(c, live, now)
    local x, y, z
    if c.unit then x, y, z = M:UnitWorld(c.unit) else x, y, z = U.Position(live) end
    if x then c.x, c.y, c.z, c.posAt = x, y, z, now end
    c.dist = U.Distance(live)
    c.teamBy = nil
  else
    c.hp, c.dist, c.teamBy = nil, nil, nil
    -- out of our sight, but a teammate running OctoBG sees them (Sync.lua)
    local u = c.enemy and ((c.guid and B.Tracker.units[c.guid]) or B.Tracker:FindByName(c.name))
    if u and u.teamAt and now - u.teamAt < B.Tracker.TEAM_FRESH then
      c.hp, c.hpmax, c.teamBy = u.hp, u.hpmax, u.teamBy
      if u.x then c.x, c.y, c.z, c.posAt = u.x, u.y, u.z, u.posAt end
    end
  end

  -- the server-sent map position covers the carrier anywhere on the map
  local p = self.pos[c.flag]
  if p and now - p.t < 6 and (not c.posAt or now - c.posAt > 1) then
    c.x, c.y = M:ToWorld(p.mx, p.my)
    c.z = nil
    c.posAt = p.t
  end
  if c.x then
    c.where = M:Describe(c.x, c.y, c.z)
    if px then c.mapDist = M.Dist(px, py, c.x, c.y) end
  end

  if c.enemy and c.hp and c.hpmax and c.hpmax > 0 and B.db.flags.alerts then
    local pct = c.hp / c.hpmax * 100
    if pct > 0 and pct <= B.db.flags.lowHp and not c.lowWarned then
      c.lowWarned = true
      U.Alert("EFC " .. c.name .. " at " .. math.floor(pct) .. "%", 1, 0.3, 0.2, true)
    elseif pct > B.db.flags.lowHp + 15 then
      c.lowWarned = nil
    end
  end
end

-- GetBattlefieldFlagPosition's token ("AllianceFlag" / "HordeFlag") is read
-- as the flag being carried. That is checked the first time our own team
-- carries a flag: the carrier's raid map position must sit on the token of
-- the flag they hold. B.db.flagTokens: nil = unchecked, "flag" = as assumed,
-- "carrier" = the token names the carrier's faction instead.
local function Near(p, mx, my, now)
  return p and now - p.t < 1 and math.abs(p.mx - mx) < 0.02 and math.abs(p.my - my) < 0.02
end

function F:LearnTokens(now)
  if B.db.flagTokens or not B.enemy then return end
  local fc = self.carriers[B.enemy]
  if not fc or fc.dropped or not fc.unit then return end
  local mx, my = M:UnitMap(fc.unit)
  if not mx then return end
  local asFlag, asCarrier = Near(raw[B.enemy], mx, my, now), Near(raw[B.faction], mx, my, now)
  if asFlag and not asCarrier then
    B.db.flagTokens = "flag"
  elseif asCarrier and not asFlag then
    B.db.flagTokens = "carrier"
    B:Print("flag map tokens name the carrier's faction - adjusted")
  end
end

function F:Tick()
  local now = GetTime()
  if B:IsBG() and M:EnsureMap() then
    local n = GetNumBattlefieldFlagPositions() or 0
    for i = 1, n do
      local x, y, token = GetBattlefieldFlagPosition(i)
      if x and token and not (x == 0 and y == 0) then
        local fac
        if string.find(token, "Alliance", 1, true) then fac = "Alliance"
        elseif string.find(token, "Horde", 1, true) then fac = "Horde" end
        if fac then
          local p = raw[fac]
          if not p then
            p = {}
            raw[fac] = p
          end
          p.mx, p.my, p.t = x, y, now
        end
      end
    end
    self:LearnTokens(now)
    for fac, p in pairs(raw) do
      if B.db.flagTokens == "carrier" then self.pos[OTHER[fac]] = p else self.pos[fac] = p end
    end
  end
  local px, py = M:PlayerWorld()
  for _, c in pairs(self.carriers) do
    if not c.dropped then self:Update(c, now, px, py) end
  end
  self:AutoCall(now)
  self:Refresh()
end

B:Every(0.2, function() F:Tick() end, true)
-- (the scoreboard, which gives the class of carriers never seen up close, is
-- requested every 10 s by the enemy list, Roster.lua)

-- ---------------------------------------------------------------- actions

function F:Target(c)
  if not c or c.fake then return false end
  if c.unit and UnitName(c.unit) == c.name then
    TargetUnit(c.unit)
    return true
  end
  if U.TargetGuidOrName(c.guid, c.name) then
    c.guid = U.GuidOf("target") or c.guid
    return true
  end
  UIErrorsFrame:AddMessage(c.name .. " is out of range", 1, 0.3, 0.2)
  return false
end

function F:CastOn(c)
  local spell = self:Spell()
  if spell == "" or not c then return end
  if UnitName("target") == c.name then CastSpellByName(spell) end
end

-- Enemy players within ESCORT yards of a carrier (not the carrier), from
-- every fresh position OctoBG has: what you see and teammates report. For
-- the enemy carrier these are their escort, for ours the ones chasing him.
local ESCORT = 30
function F:Escort(c)
  if not c or not c.x then return 0 end
  if c.fake then return 3 end
  local now, n = GetTime(), 0
  for _, u in pairs(B.Tracker.units) do
    if u.x and not u.dead and now - (u.posAt or 0) <= 4 and u.name ~= c.name then
      local dx, dy = u.x - c.x, u.y - c.y
      if dx * dx + dy * dy <= ESCORT * ESCORT then n = n + 1 end
    end
  end
  return n
end

-- "EFC Name (Rogue) 64% - Horde base - lower level - with 4"
function F:CallText(c)
  local s = (c.enemy and "EFC " or "Our FC ") .. c.name
  if c.class then s = s .. " (" .. string.upper(string.sub(c.class, 1, 1)) .. string.lower(string.sub(c.class, 2)) .. ")" end
  if c.hp and c.hpmax and c.hpmax > 0 then s = s .. " " .. math.floor(c.hp / c.hpmax * 100) .. "%" end
  if c.dropped then return s .. " - dropped" end
  if c.where then s = s .. " - " .. c.where end
  if c.x then
    local n = self:Escort(c)
    if c.enemy then
      s = s .. ((n > 0) and (" - with " .. n) or " - alone")
    elseif n > 0 then
      s = s .. " - " .. n .. " chasing"
    end
  end
  return s
end

function F:Announce(c)
  if not c or c.fake then return end
  U.SendBG(self:CallText(c))
end

-- Automatic EFC calls (db.flags.autoCall, off by default, asked first like
-- every automatic post): when the carrier is first placed, when they reach a
-- new part of the map (held 2 s, so a border does not flicker), or their
-- escort changes by 2+; at most every 10 s, and again every 30 s while
-- nothing changes.
function F:AutoCall(now)
  if not B.db.flags.autoCall or B.zone ~= "WSG" then return end
  local c = self:Enemy()
  if not c or c.dropped or c.fake or not c.where then
    self.called, self.whereNow = nil, nil
    return
  end
  if c.where ~= self.whereNow then self.whereNow, self.whereSince = c.where, now end
  if now - self.whereSince < 2 then return end
  local n = self:Escort(c)
  local last = self.called
  if last and now - last.t < 10 then return end
  local changed = not last or last.name ~= c.name or last.where ~= c.where or math.abs(last.n - n) >= 2
  if not changed and now - last.t < 30 then return end
  self.called = { name = c.name, where = c.where, n = n, t = now }
  U.SendBG(self:CallText(c))
end

function F:Click(which, button)
  local c = (which == "enemy") and self:Enemy() or self:Friend()
  if not c then return end
  if IsControlKeyDown() then
    self:Announce(c)
    return
  end
  if self:Target(c) and button == "RightButton" then self:CastOn(c) end
end

-- Key bindings (Bindings.xml)
function OctoBG_TargetEFC() F:Target(F:Enemy()) end
function OctoBG_TargetFFC() F:Target(F:Friend()) end
function OctoBG_SpellEFC()
  local c = F:Enemy()
  if F:Target(c) then F:CastOn(c) end
end

-- ---------------------------------------------------------------- UI

-- Two lines per row, each text in its own lane, nothing wrapping:
--   [flag] EFC Name            [cooldowns]  1:01  [arrow]
--          place - 212 yd - with 3  x2 +20%  61%
--   ============ health along the bottom ==========
-- The row is tinted in the carrier's team colour. While the score panel shows a
-- flag game these rows live inside it (F:Dock: one window); with that panel
-- off they stand alone here, in the same look (frame, map, how dark, width).
local PAD_TOP, PAD_SIDE, TEXT_X, RIGHT_X, TIME_W = 12, 6, 28, 24, 38
local BASE_H = 16     -- a flag at its base takes one short line

-- Focused Assault (Spell.dbc, patch-O): the flag auras 23333 / 23335 have a periodic
-- trigger of 44094 every 60 s, +10 % damage taken per stack, 99 at most. So the
-- stacks follow from when the flag was picked up for any carrier, anywhere;
-- auras seen on a carrier in range correct that.
local ASSAULT, STACK_EVERY, STACK_PCT, STACK_MAX = 44094, 60, 10, 99

-- A carrier's stacks now, and the seconds to the next one.
function F:Stacks(c, now)
  local at = c.liveAt or c.since
  if not at then return 0, nil end
  local run = now - at
  if run < 0 then run = 0 end
  local n = math.min(STACK_MAX, (c.liveN or 0) + math.floor(run / STACK_EVERY))
  return n, STACK_EVERY - math.mod(run, STACK_EVERY)
end

local function OnAssault(guid, spell, stacks, state)
  if spell ~= ASSAULT then return end
  local name
  for _, c in pairs(F.carriers) do
    if c.guid == guid then
      name = c
    elseif not name then
      local n = U.GuidExists(guid) and UnitName(guid)
      if n and U.ShortName(n) == U.ShortName(c.name) then name = c end
    end
  end
  if name then
    name.guid = guid
    name.liveN, name.liveAt = (state == 1) and 0 or (stacks or 0), GetTime()
  end
end
B:On("DEBUFF_ADDED_OTHER", function(ev, g, s, id, n, l, r, st) OnAssault(g, id, n, st) end, true)
B:On("DEBUFF_ADDED_SELF", function(ev, g, s, id, n, l, r, st) OnAssault(g, id, n, st) end, true)
B:On("DEBUFF_REMOVED_OTHER", function(ev, g, s, id, n, l, r, st) OnAssault(g, id, n, st) end, true)
B:On("DEBUFF_REMOVED_SELF", function(ev, g, s, id, n, l, r, st) OnAssault(g, id, n, st) end, true)

-- A carrier in range already holding stacks fires no event: looked at once a second.
function F:ScanStacks(c, unit, now)
  if not UnitDebuff or (c.scanAt and now < c.scanAt) then return end
  c.scanAt = now + 1
  for i = 1, 16 do
    local ok, tex, count, _, id = pcall(UnitDebuff, unit, i)
    if not ok or not tex then return end
    if id == ASSAULT then
      if (count or 0) ~= self:Stacks(c, now) then c.liveN, c.liveAt = count or 0, now end
      return
    end
  end
end

-- Is the score panel holding the carrier rows?
function F:Merged()
  local S = B.BGScore
  return (S and S.frame and S.frame:IsShown() and S.mode == "flags" and B.db.bgscore.carriers and B.db.flags.enabled) and true or false
end

-- Into the score panel: the rows from height y, each as tall as it needs; the height below them.
function F:Dock(parent, y, w)
  for i = 1, 2 do
    local r = self.rows[i]
    local c = (i == 1) and self:Enemy() or self:Friend()
    local h = c and ROW_H or BASE_H
    r:ClearAllPoints()
    if not self.docked then
      r:SetParent(parent)
      r:SetFrameLevel(parent:GetFrameLevel() + 1)
      r:Hide()     -- a frame moved out of a hidden parent stays unseen until this
      r:Show()
    end
    r:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD_SIDE, y)
    r:SetWidth(w - 2 * PAD_SIDE)
    r:SetHeight(h)
    y = y - h - 2
  end
  self.rowW = w - 2 * PAD_SIDE
  self.docked = true
  return y
end

function F:Undock()
  self.docked = nil
  for i = 1, 2 do
    local r = self.rows[i]
    r:SetParent(self.c)
    r:SetFrameLevel(self.c:GetFrameLevel() + 1)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", self.frame, "TOPLEFT", PAD_SIDE, -PAD_TOP - (i - 1) * (ROW_H + 2))
    r:SetHeight(ROW_H)
    r:SetWidth(self.rowW or 288)
    r:Hide()
    r:Show()
  end
end

-- One line that fits: cut to the width instead of letting it wrap.
local function Fit(fs, text, maxW)
  if fs.fitText == text and fs.fitW == maxW then return end
  fs.fitText, fs.fitW = text, maxW
  fs:SetText(text)
  if (fs:GetStringWidth() or 0) <= maxW then return end
  local s = text
  while string.len(s) > 1 and (fs:GetStringWidth() or 0) > maxW do
    s = string.sub(s, 1, string.len(s) - 1)
    -- never cut through a letter of a non-English name
    while string.len(s) > 1 and string.byte(s, string.len(s)) >= 128 and string.byte(s, string.len(s)) < 192 do
      s = string.sub(s, 1, string.len(s) - 1)
    end
    if string.len(s) > 1 and string.byte(s, string.len(s)) >= 192 then s = string.sub(s, 1, string.len(s) - 1) end
    fs:SetText(s .. "..")
  end
end
F.Fit = Fit

function F:Restyle()
  local f = self.frame
  if not f then return end
  local db = B.db.bgscore
  local zone = B.zone or "WSG"
  local key = table.concat({ db.border or "", db.art or "", db.dark or 0, db.width or 300, zone,
                             db.plaque and 1 or 0, db.borderColor and db.borderColor[1] or 0,
                             db.borderColor and db.borderColor[2] or 0, db.borderColor and db.borderColor[3] or 0 }, ":")
  if key == self.styleKey then return end
  self.styleKey = key
  local w = db.width or 300
  local h = PAD_TOP + 2 * ROW_H + 2 + PAD_SIDE
  f:SetWidth(w)
  f:SetHeight(h)
  W.ArtFrame(f, db.border, db.borderColor)
  if db.art == "zone" then
    self.bg:Hide()
    self.map:Set((M.DATA[zone] or M.DATA.WSG).file)
    self.map.fw = nil
    self.map:Fit(w, h)
  elseif db.art == "stone" then
    self.map:Set(nil)
    self.bg:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Background")
    self.bg:SetVertexColor(1, 1, 1, 1)
    self.bg:Show()
  else
    self.map:Set(nil)
    self.bg:Hide()
  end
  self.dim:SetVertexColor(0, 0, 0, (db.art == "plain") and math.max(db.dark, 0.7) or db.dark)
  local pw = math.min(w * 0.6, 180)
  self.plaque:ClearAllPoints()
  self.plaque:SetWidth(pw)
  self.plaque:SetHeight(pw * 0.25)
  self.plaque:SetPoint("TOP", f, "TOP", 0, pw * 0.25 * 0.45)
  self.title:ClearAllPoints()
  self.title:SetPoint("TOP", self.plaque, "TOP", 0, -pw * 0.25 * 0.2)
  if db.plaque then
    self.plaque:Show()
    self.title:Show()
  else
    self.plaque:Hide()
    self.title:Hide()
  end
  self.rowW = w - 2 * PAD_SIDE
  local nameFont = B.SpyData.Font(B.db.board.fontName, U.FONT)
  local numFont = B.SpyData.Font(B.db.board.fontNum, U.FONT)
  for i = 1, 2 do
    local r = self.rows[i]
    r:SetWidth(self.rowW)
    r.name:SetFont(nameFont, 13, "OUTLINE")
    r.tag:SetFont(nameFont, 12, "OUTLINE")
    r.time:SetFont(numFont, 12, "OUTLINE")
    r.hpText:SetFont(numFont, 11, "OUTLINE")
    r.stack:SetFont(numFont, 11, "OUTLINE")
    r.name.fitText, r.sub.fitText = nil, nil
  end
end

function F:Build()
  local w = 300
  local f = U.Panel("OctoBGFlags", "flags", "Flag carriers", w, PAD_TOP + 2 * ROW_H + 2 + PAD_SIDE, "TOP", 0, -170)
  f:Hide()
  self.frame = f
  self.bg = U.Tex(f, nil, "BACKGROUND")
  self.bg:SetAllPoints(f)
  self.map = B.BGScore.MapArt(f)
  self.dim = U.Tex(f, U.WHITE, "BORDER")
  self.dim:SetAllPoints(f)
  -- the rows on a child, above the picture and under the frame's edge
  local c = CreateFrame("Frame", nil, f)
  c:SetAllPoints(f)
  c:SetFrameLevel(f:GetFrameLevel() + 2)
  self.c = c
  local top = CreateFrame("Frame", nil, f)
  top:SetAllPoints(f)
  top:SetFrameLevel(f:GetFrameLevel() + 8)
  self.plaque = U.Tex(top, "Interface\\DialogFrame\\UI-DialogBox-Header", "ARTWORK")
  self.title = U.Text(top, 11)
  self.title:SetTextColor(1, 0.82, 0)
  self.title:SetText("Flag Carriers")
  for i = 1, 2 do
    local r = CreateFrame("Button", "OctoBGFlagRow" .. i, c)
    r:SetWidth(w - 2 * PAD_SIDE)
    r:SetHeight(ROW_H)
    r:SetPoint("TOPLEFT", f, "TOPLEFT", PAD_SIDE, -PAD_TOP - (i - 1) * (ROW_H + 2))
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r.which = (i == 1) and "enemy" or "friend"

    r.tint = U.Tex(r, U.WHITE, "BACKGROUND")      -- the carrier's team
    r.tint:SetAllPoints(r)
    r.track = U.Tex(r, U.WHITE, "BORDER")         -- health, along the bottom, under no text
    r.track:SetVertexColor(0, 0, 0, 0.6)
    r.track:SetHeight(2)
    r.track:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 0)
    r.track:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", 0, 0)
    r.bar = U.Tex(r, "Interface\\TargetingFrame\\UI-StatusBar", "ARTWORK")
    r.bar:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 0)
    r.bar:SetHeight(2)
    r.bar:SetWidth(1)

    r.icon = U.Tex(r, U.FLAG.Alliance, "ARTWORK")
    r.icon:SetWidth(22)
    r.icon:SetHeight(22)
    r.icon:SetPoint("LEFT", r, "LEFT", 3, 0)

    r.tag = U.Text(r, 12)                         -- EFC / FC
    r.tag:SetPoint("TOPLEFT", r, "TOPLEFT", TEXT_X, -2)
    r.name = U.Text(r, 13)
    r.name:SetJustifyH("LEFT")

    r.sub = U.Text(r, 10, U.NARROW)
    r.sub:SetPoint("TOPLEFT", r, "TOPLEFT", TEXT_X, -16)
    r.sub:SetJustifyH("LEFT")

    r.arrow = U.Tex(r, U.MEDIA .. "arrow", "OVERLAY")
    r.arrow:SetWidth(20)
    r.arrow:SetHeight(20)
    r.arrow:SetPoint("RIGHT", r, "RIGHT", -2, 0)

    r.time = U.Text(r, 12)
    r.time:SetPoint("TOPRIGHT", r, "TOPRIGHT", -RIGHT_X, -2)
    r.hpText = U.Text(r, 11)
    r.hpText:SetPoint("TOPRIGHT", r, "TOPRIGHT", -RIGHT_X, -16)
    r.stack = U.Text(r, 11)                       -- Focused Assault, left of the health
    r.stack:SetPoint("TOPRIGHT", r, "TOPRIGHT", -RIGHT_X - 32, -16)

    -- the carrier's notable cooldowns (built-in tracker), left of the time
    r.cds = {}
    for j = 1, 3 do
      local ic = U.Tex(r, nil, "OVERLAY")
      ic:SetWidth(13)
      ic:SetHeight(13)
      ic:SetPoint("TOPRIGHT", r, "TOPRIGHT", -RIGHT_X - TIME_W - (j - 1) * 14, -2)
      ic:SetTexCoord(0.07, 0.93, 0.07, 0.93)
      ic:Hide()
      r.cds[j] = ic
    end

    r:SetScript("OnClick", function() F:Click(this.which, arg1) end)
    r:SetScript("OnEnter", function()
      GameTooltip:SetOwner(this, "ANCHOR_BOTTOM")
      GameTooltip:AddLine(this.which == "enemy" and "Enemy flag carrier" or "Our flag carrier")
      local cr = (this.which == "enemy") and F:Enemy() or F:Friend()
      if cr and not cr.dropped then
        local n, nextIn = F:Stacks(cr, GetTime())
        if n > 0 then
          GameTooltip:AddLine("Focused Assault x" .. n .. ": takes " .. (n * STACK_PCT) .. "% more damage", 1, 0.6, 0.2, 1)
        else
          GameTooltip:AddLine("Focused Assault: no stacks yet", 0.7, 0.7, 0.7)
        end
        if nextIn and n < STACK_MAX then
          GameTooltip:AddLine("Next stack in " .. math.ceil(nextIn) .. " sec (one a minute)", 0.7, 0.7, 0.7)
        end
      end
      GameTooltip:AddLine("Left-click: target", 1, 1, 1)
      local spell = F:Spell()
      if spell ~= "" then GameTooltip:AddLine("Right-click: target + " .. spell, 1, 1, 1) end
      GameTooltip:AddLine("Ctrl-click: post to /bg", 1, 1, 1)
      GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.rows[i] = r
  end
end

function F:Paint(r, c, isEnemy, now, px, py, facing)
  local w = self.rowW or 290
  local flag = isEnemy and B.faction or B.enemy
  r.icon:SetTexture(U.FLAG[flag or "Alliance"])
  r.name:ClearAllPoints()
  if not c then
    r.tag:SetText("")
    r.stack:SetText("")
    r.name:SetPoint("LEFT", r, "LEFT", TEXT_X, 0)
    Fit(r.name, isEnemy and "Our flag: at base" or "Their flag: at base", w - TEXT_X - 8)
    r.name:SetTextColor(0.6, 0.6, 0.6)
    Fit(r.sub, "", 100)
    r.time:SetText("")
    r.hpText:SetText("")
    r.tint:SetVertexColor(0, 0, 0, 0.3)
    r.bar:Hide()
    r.track:Hide()
    r.arrow:Hide()
    r.icon:SetAlpha(0.4)
    for j = 1, 3 do r.cds[j]:Hide() end
    return
  end
  -- cooldowns the carrier has used, and an immunity still running
  local guid = c.fake and ((isEnemy and "sample1") or nil) or c.guid
  local ncd = (B.db.flags.cds and guid and not c.dropped) and B.CD:Important(guid, 3, self.cdScratch) or 0
  for j = 1, 3 do
    if j <= ncd and self.cdScratch[j].tex then
      r.cds[j]:SetTexture(self.cdScratch[j].tex)
      r.cds[j]:Show()
    else
      r.cds[j]:Hide()
    end
  end
  local immLeft, immName = B.CD:ImmuneLeft(guid)
  r.icon:SetAlpha(1)
  local team = U.FACTION[c.faction or ""]
  if team then r.tint:SetVertexColor(team[1], team[2], team[3], 0.2) else r.tint:SetVertexColor(0, 0, 0, 0.3) end
  r.tag:SetText(isEnemy and "EFC" or "FC")
  if isEnemy then r.tag:SetTextColor(1, 0.35, 0.3) else r.tag:SetTextColor(0.4, 1, 0.45) end
  local tagW = (r.tag:GetStringWidth() or 24) + 5
  r.name:SetPoint("TOPLEFT", r, "TOPLEFT", TEXT_X + tagW, -2)
  local nameW = w - TEXT_X - tagW - RIGHT_X - TIME_W - ncd * 14 - 4
  -- Focused Assault: gold, then orange, then red as it gets dangerous
  local stacks = c.dropped and 0 or self:Stacks(c, now)
  local stackW = 0
  if stacks > 0 then
    r.stack:SetText("x" .. stacks .. " +" .. (stacks * STACK_PCT) .. "%")
    if stacks >= 5 then r.stack:SetTextColor(1, 0.25, 0.2)
    elseif stacks >= 3 then r.stack:SetTextColor(1, 0.55, 0.15)
    else r.stack:SetTextColor(1, 0.82, 0.2) end
    stackW = (r.stack:GetStringWidth() or 50) + 6
  else
    r.stack:SetText("")
  end
  local cr, cg, cb = U.ClassColor(c.class)
  if c.dropped then
    Fit(r.name, "Dropped by " .. c.name, nameW)
    r.name:SetTextColor(1, 0.65, 0.2)
    r.time:SetText(U.Time(now - (c.droppedAt or now)))
    r.hpText:SetText("")
    r.bar:Hide()
    r.track:Hide()
  else
    Fit(r.name, c.name, nameW)
    r.name:SetTextColor(cr, cg, cb)
    r.time:SetText(U.Time(now - c.since))
    r.time:SetTextColor(1, 1, 1)
    if c.hp and c.hpmax and c.hpmax > 0 then
      local pct = c.hp / c.hpmax
      r.hpText:SetText(math.floor(pct * 100) .. "%")
      if pct <= B.db.flags.lowHp / 100 then
        r.hpText:SetTextColor(1, 0.25, 0.2)
        r.bar:SetVertexColor(1, 0.25, 0.2, 1)
      else
        r.hpText:SetTextColor(1, 1, 1)
        r.bar:SetVertexColor(cr, cg, cb, 1)
      end
      r.bar:SetWidth(math.max(1, w * math.min(1, pct)))
      r.bar:Show()
      r.track:Show()
    else
      r.hpText:SetText("")
      r.bar:Hide()
      r.track:Hide()
    end
  end
  local sub = c.where or ""
  local d = c.dist or c.mapDist
  if d then sub = sub .. (sub ~= "" and " - " or "") .. math.floor(d) .. " yd" end
  if c.x and not c.dropped then
    local n = self:Escort(c)
    if n > 0 then sub = sub .. (isEnemy and (" - with " .. n) or (" - " .. n .. " chasing")) end
  end
  if immLeft and not c.dropped then
    sub = immName .. " " .. math.ceil(immLeft) .. "s - " .. sub
    r.sub:SetTextColor(1, 0.82, 0)
  else
    r.sub:SetTextColor(0.88, 0.88, 0.88)
  end
  Fit(r.sub, sub, w - TEXT_X - RIGHT_X - 34 - stackW)
  if c.x and px and facing and not c.dropped then
    local rx, fy = M.Relative(px, py, facing, c.x, c.y, true)
    U.Rotate(r.arrow, math.atan2(-rx, fy))
    if d and d < 30 then r.arrow:SetVertexColor(0.3, 1, 0.3) else r.arrow:SetVertexColor(1, 0.82, 0) end
    r.arrow:Show()
  else
    r.arrow:Hide()
  end
end

function F:Refresh()
  local f = self.frame
  if not f then return end
  local show = B.db.flags.enabled and (B.zone == "WSG" or self.any or B.test)
  local merged = show and self:Merged()
  if self.docked and not merged then self:Undock() end
  -- inside the score panel there is no window of its own, and no move box for it
  if f.handle then
    if merged then f.handle:Hide() elseif not B.db.locked then f.handle:Show() end
  end
  if not show then
    if f:IsShown() then f:Hide() end
    return
  end
  self:Restyle()
  if merged then
    if f:IsShown() then f:Hide() end
    self.rowW = (B.db.bgscore.width or 300) - 2 * PAD_SIDE
  elseif not f:IsShown() then
    f:Show()
  end
  local now = GetTime()
  local px, py = M:PlayerWorld()
  local facing = M:Facing()
  self:Paint(self.rows[1], self:Enemy(), true, now, px, py, facing)
  self:Paint(self.rows[2], self:Friend(), false, now, px, py, facing)
end

B:On("OBG_INIT", function() F:Build() F:Refresh() end)

B:On("OBG_LAYOUT", function(ev, on)
  if on then
    local now = GetTime()
    F.samples = {
      enemy = { fake = true, name = "Testrogue", class = "ROGUE", enemy = true, since = now - 192, faction = B.enemy,
                hp = 61, hpmax = 100, where = "Horde base - lower level", mapDist = 212 },
      friend = { fake = true, name = UnitName("player") or "You", class = "WARRIOR", since = now - 75, faction = B.faction,
                 hp = 88, hpmax = 100, where = "midfield (west)", mapDist = 34 },
    }
  else
    F.samples = nil
  end
  F:Refresh()
end)

B:On("OBG_ZONE", function() F:Refresh() end)
