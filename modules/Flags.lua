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
local F = { carriers = {}, pos = {}, rows = {}, cdScratch = {} }
B.Flags = F
local raw = {}   -- flag map positions by token faction: { mx, my, t }

local ROW_H = 34
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

local function RaidUnit(name)
  if UnitName("player") == name then return "player" end
  for i = 1, GetNumRaidMembers() do
    if UnitName("raid" .. i) == name then return "raid" .. i end
  end
  for i = 1, GetNumPartyMembers() do
    if UnitName("party" .. i) == name then return "party" .. i end
  end
  return nil
end

local function ScoreClass(name)
  for i = 1, GetNumBattlefieldScores() do
    local n, _, _, _, _, _, _, _, class = GetBattlefieldScore(i)
    if n == name then return U.ClassToken(class) end
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
  if not c.class then c.class = ScoreClass(c.name) end
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
    if not c.class then c.class = ScoreClass(c.name) end
  end

  local live = c.unit
  if not live and c.guid and U.GuidExists(c.guid) then live = c.guid end
  if live then
    c.hp, c.hpmax = UnitHealth(live), UnitHealthMax(live)
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

function F:Build()
  local w = 236
  local f = U.Panel("OctoBGFlags", "flags", "Flag carriers", w, 2 * ROW_H + 6, "TOP", 0, -96)
  U.Backdrop(f, 0.75)
  f:Hide()
  self.frame = f
  for i = 1, 2 do
    local r = CreateFrame("Button", "OctoBGFlagRow" .. i, f)
    r:SetWidth(w - 4)
    r:SetHeight(ROW_H)
    r:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -2 - (i - 1) * (ROW_H + 2))
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r.which = (i == 1) and "enemy" or "friend"

    r.bar = U.Tex(r, U.WHITE, "BACKGROUND")
    r.bar:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 0)
    r.bar:SetHeight(ROW_H)
    r.bar:SetWidth(1)

    r.icon = U.Tex(r, U.FLAG.Alliance, "ARTWORK")
    r.icon:SetWidth(26)
    r.icon:SetHeight(26)
    r.icon:SetPoint("LEFT", r, "LEFT", 2, 0)

    r.name = U.Text(r, 12)
    r.name:SetPoint("TOPLEFT", r, "TOPLEFT", 32, -3)
    r.name:SetJustifyH("LEFT")

    r.sub = U.Text(r, 10, U.NARROW)
    r.sub:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 32, 4)
    r.sub:SetWidth(w - 100)
    r.sub:SetJustifyH("LEFT")

    r.arrow = U.Tex(r, U.MEDIA .. "arrow", "OVERLAY")
    r.arrow:SetWidth(26)
    r.arrow:SetHeight(26)
    r.arrow:SetPoint("RIGHT", r, "RIGHT", -2, 0)

    r.time = U.Text(r, 11)
    r.time:SetPoint("TOPRIGHT", r, "TOPRIGHT", -32, -3)
    r.hpText = U.Text(r, 10)
    r.hpText:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", -32, 4)

    -- the carrier's notable cooldowns (built-in tracker), left of the time
    r.cds = {}
    for j = 1, 3 do
      local ic = U.Tex(r, nil, "OVERLAY")
      ic:SetWidth(14)
      ic:SetHeight(14)
      ic:SetPoint("TOPRIGHT", r, "TOPRIGHT", -62 - (j - 1) * 15, -2)
      ic:SetTexCoord(0.07, 0.93, 0.07, 0.93)
      ic:Hide()
      r.cds[j] = ic
    end

    r:SetScript("OnClick", function() F:Click(this.which, arg1) end)
    r:SetScript("OnEnter", function()
      GameTooltip:SetOwner(this, "ANCHOR_BOTTOM")
      GameTooltip:AddLine(this.which == "enemy" and "Enemy flag carrier" or "Our flag carrier")
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
  local w = r:GetWidth()
  local flag = isEnemy and B.faction or B.enemy
  r.icon:SetTexture(U.FLAG[flag or "Alliance"])
  if not c then
    r.name:SetText(isEnemy and "Our flag: at base" or "Their flag: at base")
    r.name:SetTextColor(0.55, 0.55, 0.55)
    r.sub:SetText("")
    r.time:SetText("")
    r.hpText:SetText("")
    r.bar:Hide()
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
  local cr, cg, cb = U.ClassColor(c.class)
  if c.dropped then
    r.name:SetText("Dropped by " .. c.name)
    r.name:SetTextColor(1, 0.65, 0.2)
    r.time:SetText(U.Time(now - (c.droppedAt or now)))
    r.hpText:SetText("")
    r.bar:Hide()
  else
    r.name:SetText(c.name)
    r.name:SetTextColor(cr, cg, cb)
    r.time:SetText(U.Time(now - c.since))
    if c.hp and c.hpmax and c.hpmax > 0 then
      local pct = c.hp / c.hpmax
      r.hpText:SetText(math.floor(pct * 100) .. "%")
      if pct <= B.db.flags.lowHp / 100 then
        r.hpText:SetTextColor(1, 0.25, 0.2)
      else
        r.hpText:SetTextColor(1, 1, 1)
      end
      r.bar:SetWidth(math.max(1, w * pct))
      r.bar:SetVertexColor(cr, cg, cb, 0.28)
      r.bar:Show()
    else
      r.hpText:SetText("")
      r.bar:Hide()
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
    sub = "|cffffd100" .. immName .. " " .. math.ceil(immLeft) .. "s|r - " .. sub
  end
  r.sub:SetText(sub)
  r.sub:SetTextColor(0.85, 0.85, 0.85)
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
  if not show then
    if f:IsShown() then f:Hide() end
    return
  end
  if not f:IsShown() then f:Show() end
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
      enemy = { fake = true, name = "Testrogue", class = "ROGUE", enemy = true, since = now - 42,
                hp = 61, hpmax = 100, where = "Horde base - lower level", mapDist = 212 },
      friend = { fake = true, name = UnitName("player") or "You", class = "WARRIOR", since = now - 15,
                 hp = 88, hpmax = 100, where = "midfield (west)", mapDist = 34 },
    }
  else
    F.samples = nil
  end
  F:Refresh()
end)

B:On("OBG_ZONE", function() F:Refresh() end)
