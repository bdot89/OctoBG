-- OctoBG :: nearby (Spy's detection lists and alerts)
-- World PvP the way Spy did it, on OctoBG's tracker:
--   * Nearby: every enemy player detected, by name. Active while your client
--     sees them (or a teammate's OctoBG / another Spy user reports them),
--     then greyed out for "Remove undetected after" minutes (dead: at least
--     30 s), then gone. Last hour: everyone seen in the last 60 minutes.
--   * on a new detection: sound (Kill On Sight, KoS guild, race, nearby),
--     the alert box (Kill On Sight / guild / stealth / reported by someone
--     else) or the error-message line, an announcement and Spy's channel
--   * where it runs: off in sanctuaries, the chosen neutral towns, dungeons
--     and raids; battlegrounds and PvP-unflagged zones by choice; while on a
--     taxi nothing new is added (optional)
--   * stealth alerts for battlegrounds and the open world (Tracker calls
--     StealthAlert), also when detection is off ("warn even if disabled")
--   * minimap tooltips: class and level of tracked enemy players, and those
--     names count as detected (optional, Track Humanoids)
-- The enemy list (Roster.lua) draws these lists.
--
-- Eviction: Nearby by the timeout above, Last hour after 60 minutes, at most
-- 300 names each (oldest go), everything when detection is switched off and
-- when entering or leaving a battleground.

local B = OctoBG
local U = B.U
local NB = { nearby = {}, active = {}, inactive = {}, lastHour = {}, first = {}, order = 0, dead = {},
             comm = {}, n = 0, nLast = 0, enabledInZone = false, inInstance = false }
B.Nearby = NB

local MAX_NAMES = 300
local ACTIVE_FOR = 2      -- seconds a name stays active after its last sighting

-- ---------------------------------------------------------------- where it runs

-- The old Spy addon is still enabled: its windows and sounds are on screen.
function NB:Standing()
  return self.standDown
end

-- Detection alerts, the Nearby list and win/loss counting run here and now.
function NB:LayerOn()
  return B.db.spy.Enabled and self.enabledInZone and not self.standDown
end

-- Only stealth alerts: detection is off, "warn even if disabled" is on.
function NB:StealthOnly()
  local spy = B.db.spy
  return not spy.Enabled and spy.WarnOnStealthEvenIfDisabled and not self.standDown
end

-- Spy's zone rules (ZoneChangedEvent).
function NB:ZoneCheck()
  local spy = B.db.spy
  local pvpType = GetZonePVPInfo()
  local zone, sub = GetZoneText(), GetSubZoneText()
  local on = true
  self.inInstance = false
  if pvpType == "sanctuary" or zone == "" or (sub and spy.FilteredZones[sub]) then
    on = false
  else
    local inInstance, kind = false, nil
    if IsInInstance then inInstance, kind = IsInInstance() end
    if inInstance then
      self.inInstance = true
      if zone ~= "Winter Veil Vale" and (kind == "party" or kind == "raid"
         or (kind == "pvp" and not spy.EnabledInBattlegrounds)) then
        on = false
      end
    elseif B:IsBG() then
      self.inInstance = true
      if not spy.EnabledInBattlegrounds then on = false end
    elseif (pvpType == "friendly" or pvpType == nil) and spy.DisableWhenPVPUnflagged and not UnitIsPVP("player") then
      on = false
    end
  end
  if on ~= self.enabledInZone then
    self.enabledInZone = on
    if not on then self:Clear() end
  end
  B:RefreshActive()
end

-- Open world: detection (or stealth-only alerts) and the panels' world options.
function B:WorldWanted()
  local db = self.db
  if NB:LayerOn() or NB:StealthOnly() then return true end
  if db.hud.enabled and db.hud.world then return true end
  if db.map.enabled and db.map.world then return true end
  if B.TacMap and B.TacMap.big then return true end   -- the map opened as the world map
  return false
end

local function Zone() NB:ZoneCheck() end
B:On("ZONE_CHANGED", Zone)
B:On("ZONE_CHANGED_INDOORS", Zone)
B:On("ZONE_CHANGED_NEW_AREA", Zone)
B:On("PLAYER_ENTERING_WORLD", Zone)
B:On("OBG_ZONE", function()
  NB:Clear()
  NB:ZoneCheck()
end)
B:On("UNIT_FACTION", function(ev, unit)
  if unit == "player" then NB:ZoneCheck() end
end)

-- ---------------------------------------------------------------- lists

function NB:Clear()
  self.nearby, self.active, self.inactive, self.dead, self.comm = {}, {}, {}, {}, {}
  self.first = {}
  self.n = 0
  B:Fire("OBG_NEARBY")
end

-- Spy's clear button: Shift = sound on/off, Ctrl = detection on/off.
function NB:ClearButton()
  if IsShiftKeyDown() then
    B.db.spy.EnableSound = not B.db.spy.EnableSound
    B:Print("detection sounds " .. (B.db.spy.EnableSound and "on" or "off"))
    return
  end
  self:Clear()
  if IsControlKeyDown() then self:SetEnabled(not B.db.spy.Enabled) end
end

function NB:SetEnabled(on)
  B.db.spy.Enabled = on and true or false
  if not on then self:Clear() end
  B:Print("world PvP detection " .. (on and "on" or "off"))
  self:ZoneCheck()
  if B.Options then B.Options:Refresh() end
end

local function Oldest(t)
  local oldN, oldT
  for name, v in pairs(t) do
    if not oldT or v < oldT then oldN, oldT = name, v end
  end
  return oldN
end

function NB:Remove(name, quiet)
  if self.nearby[name] then self.n = self.n - 1 end
  self.nearby[name], self.active[name], self.inactive[name], self.dead[name], self.comm[name] = nil, nil, nil, nil, nil
  self.first[name] = nil
  if not quiet then B:Fire("OBG_NEARBY") end
end

local function AddLastHour(self, name, now)
  if not self.lastHour[name] then
    if self.nLast >= MAX_NAMES then
      local o = Oldest(self.lastHour)
      if o then
        self.lastHour[o] = nil
        self.nLast = self.nLast - 1
      end
    end
    self.nLast = self.nLast + 1
  end
  self.lastHour[name] = now
end

-- Passes Spy's filters (flagged enemy player, not ignored, not a friend).
function NB:Wanted(u)
  if not u or not u.name or u.fake then return false end
  local P = B.People
  if P:IsIgnored(u.name) or P:IsFriend(u.name) then return false end
  if not u.pvp and not B.db.spy.unflagged and B.zone == nil then return false end
  return true
end

-- A sighting: new names alert, known ones turn active again.
function NB:Seen(name, u, source)
  local now = time()
  local spy = B.db.spy
  if spy.StopAlertsOnTaxi and UnitOnTaxi("player") and not self.nearby[name] then return end
  local fresh = not self.nearby[name]
  local changed = fresh
  if fresh then
    if self.n >= MAX_NAMES then
      local o = Oldest(self.nearby)
      if o then self:Remove(o, true) end
    end
    self.n = self.n + 1
    self.order = self.order + 1
    self.first[name] = self.order
    self.nearby[name] = now
  end
  AddLastHour(self, name, now)
  local dead = u and u.dead
  if source then
    -- reported by someone else: listed greyed until this client sees them
    if not self.active[name] then self.inactive[name] = self.inactive[name] or now end
    self.comm[name] = { t = now, source = source }
  elseif dead then
    if not self.dead[name] then changed = true end
    self.dead[name] = true
    if self.active[name] or not self.inactive[name] then self.inactive[name] = now end
    self.active[name] = nil
  else
    if self.dead[name] or not self.active[name] then changed = true end
    self.dead[name] = nil
    self.active[name] = now
    self.inactive[name] = nil
    self.nearby[name] = now
  end
  if not changed then return end
  if fresh then
    local Roster = B.Roster
    if Roster then
      -- undoes the list's close button (not the options' "Show the enemy list")
      if spy.ShowOnDetection and Roster.closed then
        Roster.closed = false
        Roster:Refresh()
      end
      if spy.ShowNearbyList and B.db.list.mode ~= 1 then Roster:SetMode(1) end
    end
    self:Alert(name, source)
    if not source then
      B.People:Announce(name)
      B.People:Share(name)
    end
  end
  B:Fire("OBG_NEARBY", name)
end

-- Another Spy / OctoBG user reported this name on Spy's channel.
function NB:Heard(name, source)
  if not self:LayerOn() then return end
  self:Seen(name, nil, source)
end

-- New enemies from the tracker are handled straight away.
B:On("OBG_ENEMY", function(ev, guid)
  if not NB:LayerOn() then return end
  local u = B.Tracker.units[guid]
  if NB:Wanted(u) and not u.dead then
    B.People:Saw(u)
    NB:Seen(u.name, u)
  end
end, true)

-- Every half second: tracker sightings -> active, timeouts -> greyed -> gone.
function NB:Tick()
  if not self:LayerOn() then return end
  local now, gnow = time(), GetTime()
  local T = B.Tracker
  for _, u in pairs(T.units) do
    if u.name and not u.fake and (u.visible or (u.teamAt and gnow - u.teamAt < T.TEAM_FRESH)) and self:Wanted(u) then
      if not self.nearby[u.name] or not self.active[u.name] or u.dead ~= (self.dead[u.name] or nil) then
        B.People:Saw(u)
      end
      self:Seen(u.name, u)
    end
  end
  local removeAfter = (B.db.spy.RemoveUndetectedTime or 5) * 60
  local changed = false
  for name, t in pairs(self.active) do
    if now - t > ACTIVE_FOR then
      self.active[name] = nil
      self.inactive[name] = now
      changed = true
    end
  end
  for name, t in pairs(self.inactive) do
    local limit = removeAfter
    if self.dead[name] and limit < 30 then limit = 30 end
    if now - t >= limit then
      self:Remove(name, true)
      changed = true
    end
  end
  for name, t in pairs(self.lastHour) do
    if now - t > 3600 then
      self.lastHour[name] = nil
      self.nLast = self.nLast - 1
    end
  end
  if changed then B:Fire("OBG_NEARBY") end
end

B:Every(0.5, function() NB:Tick() end, true)

function NB:ActiveCount()
  local n = 0
  for _ in pairs(self.active) do n = n + 1 end
  return n
end

-- ---------------------------------------------------------------- alerts

function NB:SoundOn()
  local spy = B.db.spy
  if not spy.EnableSound then return false end
  if spy.MuteSoundInBattlegrounds and (self.inInstance or B.zone ~= nil) then return false end
  return true
end

local function Play(file)
  PlaySoundFile(U.MEDIA .. "sounds\\" .. file .. ".wav")
end

-- The alert box: icon, title, name, a line under it; Spy's colours.
local STYLE = {
  kos = { icon = "Interface\\Icons\\Ability_Creature_Cursed_02", title = "Kill On Sight player detected!", r = 1, g = 0.15, b = 0.15 },
  kosguild = { icon = "Interface\\Icons\\Spell_Holy_PrayerofSpirit", title = "Kill On Sight player guild detected!", r = 1, g = 0.82, b = 0 },
  stealth = { icon = "Interface\\Icons\\Ability_Stealth", title = "Stealthed player detected!", r = 0.7, g = 0.35, b = 1 },
  race = { icon = "Interface\\Icons\\INV_Misc_Head_Human_01", title = "Race detected!", r = 1, g = 0.55, b = 0.1 },
  kosaway = { icon = "Interface\\Icons\\Ability_Hunter_SniperShot", title = "Kill On Sight player located by ", r = 0.2, g = 1, b = 0.2 },
  kosguildaway = { icon = "Interface\\Icons\\Ability_Hunter_SniperShot", title = "Kill On Sight player guild located by ", r = 0.2, g = 1, b = 0.2 },
}
local RANK = { kos = 4, kosguild = 3, stealth = 2, race = 1, kosaway = 1, kosguildaway = 1 }

function NB:AlertBox()
  if self.box then return self.box end
  local f = CreateFrame("Frame", "OctoBGAlertBox", UIParent)
  f:SetWidth(240)
  f:SetHeight(46)
  f:SetFrameStrata("HIGH")
  f:SetClampedToScreen(true)
  B.W.Skin(f, "panel", 0.9)
  f.icon = U.Tex(f, nil, "ARTWORK")
  f.icon:SetWidth(34)
  f.icon:SetHeight(34)
  f.icon:SetPoint("LEFT", f, "LEFT", 6, 0)
  f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  f.title = U.Text(f, 11)
  f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 46, -5)
  f.title:SetJustifyH("LEFT")
  f.name = U.Text(f, 14)
  f.name:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -2)
  f.name:SetJustifyH("LEFT")
  f.line = U.Text(f, 10, U.NARROW)
  f.line:SetPoint("TOPLEFT", f.name, "BOTTOMLEFT", 0, -1)
  f.line:SetJustifyH("LEFT")
  f:SetMovable(true)
  f:SetScript("OnMouseDown", function()
    if this.moving then this:StartMoving() end
  end)
  f:SetScript("OnMouseUp", function()
    if this.moving then
      this:StopMovingOrSizing()
      B.db.spy.alertX, B.db.spy.alertY = this:GetLeft(), this:GetBottom()
    end
  end)
  f:SetScript("OnUpdate", function()
    if this.moving then return end
    this.t = this.t - arg1
    if this.t <= 0 then
      this:Hide()
      NB.boxKind = nil
    elseif this.t < 1 then
      this:SetAlpha(this.t)
    else
      -- pulses for the first two seconds
      local e = 5 - this.t
      if e < 2 then this:SetAlpha(0.65 + 0.35 * math.abs(math.cos(e * 3.14159))) else this:SetAlpha(1) end
    end
  end)
  f:Hide()
  self.box = f
  self:PlaceBox()
  return f
end

function NB:PlaceBox()
  local f = self.box
  if not f then return end
  f:ClearAllPoints()
  local spy = B.db.spy
  if spy.DisplayWarnings == "Moveable" and spy.alertX and spy.alertY then
    f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", spy.alertX, spy.alertY)
  else
    f:SetPoint("TOP", UIParent, "TOP", 0, -140)
  end
end

-- Moveable alerts: show the box with a frame to drag until Done.
function NB:MoveBox(on)
  local f = self:AlertBox()
  if on then
    self:PlaceBox()
    f.moving = true
    f:EnableMouse(true)
    f.icon:SetTexture(STYLE.stealth.icon)
    f:SetBackdropBorderColor(0.3, 0.7, 1, 1)
    f.title:SetText("Drag the alert box")
    f.title:SetTextColor(0.3, 0.7, 1)
    f.name:SetText("Name")
    f.line:SetText("then click Done")
    f:SetAlpha(1)
    f:Show()
  else
    f.moving = nil
    f:EnableMouse(false)
    f:Hide()
  end
end

-- kind: kos | kosguild | stealth | race | kosaway | kosguildaway
function NB:ShowAlert(kind, name, line, source)
  local spy = B.db.spy
  local st = STYLE[kind]
  if not st then return end
  -- also as combat text (pfUI Octo's, through SCTLink.lua) when that message type is on there
  if B.SCT and B.SCT.Notify then
    local what = (kind == "stealth" and "Stealth: ") or (kind == "race" and "Race: ")
      or ((kind == "kosaway" or kind == "kosguildaway") and ("Kill On Sight (" .. (source or "?") .. "): ")) or "Kill On Sight: "
    B.SCT:Notify(kind == "stealth" and "obgStealth" or "obgDetect",
      what .. name .. ((line and line ~= "") and (" - " .. line) or ""), st.r, st.g, st.b)
  end
  if spy.DisplayWarnings == "ErrorFrame" then
    local title = (kind == "kosaway" or kind == "kosguildaway") and (st.title .. (source or "?") .. ": ") or (st.title .. " ")
    UIErrorsFrame:AddMessage(title .. name .. (line and line ~= "" and (" - " .. line) or ""), st.r, st.g, st.b, 1, UIERRORS_HOLD_TIME)
    return
  end
  local f = self:AlertBox()
  if f.moving then return end
  -- a lower kind never replaces a higher one that is still up
  if f:IsShown() and self.boxKind and RANK[self.boxKind] > RANK[kind] then return end
  self:PlaceBox()
  self.boxKind = kind
  f.icon:SetTexture(st.icon)
  f:SetBackdropBorderColor(st.r, st.g, st.b, 1)
  local title = st.title
  if kind == "kosaway" or kind == "kosguildaway" then title = title .. (source or "?") .. "!" end
  f.title:SetText(title)
  f.title:SetTextColor(st.r, st.g, st.b)
  f.name:SetText(name)
  f.name:SetTextColor(1, 1, 1)
  f.line:SetText(line or "")
  f.line:SetTextColor(1, 0.82, 0)
  local w = math.max(f.title:GetStringWidth(), f.name:GetStringWidth(), f.line:GetStringWidth())
  f:SetWidth(math.max(180, w + 58))
  f:SetHeight((line and line ~= "") and 52 or 42)
  f.t = 5
  f:SetAlpha(1)
  f:Show()
end

-- A new name in the Nearby list (Spy's AlertPlayer).
function NB:Alert(name, source)
  local P = B.People
  local spy = B.db.spy
  if P:IsFriend(name) then return end
  local r = P:Get(name)
  local sound = self:SoundOn()
  local away = source and source ~= P:Me()
  if P:IsKOS(name) and spy.WarnOnKOS then
    if away then
      self:ShowAlert("kosaway", name, P:Location(r), source)
      if sound then Play("detected-kosaway") end
    else
      self:ShowAlert("kos", name, P:ReasonText(name))
      if sound then Play("detected-kos") end
    end
    return
  end
  if spy.WarnOnKOSGuild and r and r.guild and P:IsKOSGuild(r.guild) then
    if away then
      self:ShowAlert("kosguildaway", "<" .. r.guild .. ">", P:Location(r), source)
      if sound then Play("detected-kosaway") end
    else
      self:ShowAlert("kosguild", "<" .. r.guild .. ">", name)
      if sound then Play("detected-kosguild") end
    end
    return
  end
  if away then return end
  if spy.WarnOnRace and r and r.race and r.race == spy.SelectWarnRace then
    self:ShowAlert("race", name, r.race)
    if sound and not spy.OnlySoundKoS then Play("detected-kosguild") end
    return
  end
  if sound and not spy.OnlySoundKoS then Play("detected-nearby") end
end

-- One stealth alert for battlegrounds and the open world. Returns true when shown.
function NB:StealthAlert(u, kind, dist)
  if not u or not u.name or u.fake then return false end
  local db = B.db
  if not db.stealth.alert then return false end
  if self.standDown then return false end
  local P = B.People
  if P:IsIgnored(u.name) or P:IsFriend(u.name) then return false end
  -- battlegrounds always; the open world while detection or stealth-only runs here
  if B.zone == nil and not ((db.spy.Enabled and self.enabledInZone) or self:StealthOnly()) then return false end
  local range = db.stealth.range or 0
  if range > 0 and (not dist or dist > range) then return false end
  local line = (kind or "Stealth") .. (dist and ("  " .. math.floor(dist) .. " yd") or "")
  self:ShowAlert("stealth", u.name, line)
  if self:SoundOn() then Play("detected-stealth") end
  return true
end

-- ---------------------------------------------------------------- minimap tooltips (Track Humanoids)

-- Names in the minimap's tooltip: known enemies get class and level, and
-- with "Detect from the minimap" they count as detected (Spy's feature).
local lastTip
function NB:MinimapTip()
  local spy = B.db.spy
  if not (spy.MinimapDetails or spy.MinimapDetection) or not GameTooltip:IsVisible() then return end
  if not GameTooltip.IsOwned or not GameTooltip:IsOwned(Minimap) then return end
  local line = GameTooltipTextLeft1
  local text = line and line:GetText()
  if not text or text == lastTip then return end
  local P = B.People
  local out = {}
  local changed = false
  for row in string.gfind(text, "[^\n]+") do
    local name = string.gsub(row, "|c%x%x%x%x%x%x%x%x", "")
    name = string.gsub(name, "|r", "")
    name = string.gsub(name, "^%s+", "")
    local r = P:Get(name)
    if r and r.isEnemy then
      local desc = ""
      if spy.MinimapDetails and (r.class or r.level) then
        local cr, cg, cb = U.ClassColor(r.class)
        desc = " " .. U.Hex(cr, cg, cb) .. "[" .. (r.level and ((r.level == 0) and "??" or r.level) or "")
          .. (r.class and ((r.level and " " or "") .. (P.CLASS_NAME[r.class] or r.class)) or "") .. "]|r"
        changed = true
      end
      table.insert(out, row .. desc)
      if spy.MinimapDetection and self:LayerOn() and not P:IsIgnored(name) and not B.zone then
        r.time = time()
        self:Seen(name, nil)
      end
    else
      table.insert(out, row)
    end
  end
  local newText = table.concat(out, "\n")
  lastTip = newText
  if changed and newText ~= text then
    line:SetText(newText)
    GameTooltip:Show()
  end
end

B:Every(0.2, function() NB:MinimapTip() end)

-- ---------------------------------------------------------------- setup

B:On("OBG_LOADED", function()
  NB.standDown = B.People:SpyLoaded()
end)

-- Leaving the world or switching detection off empties the lists (Spy cleared on login).
B:On("PLAYER_LEAVING_WORLD", function()
  NB.active = {}
end)

-- Spy's "test" (a stealth alert) and the old slash command.
function NB:Test()
  self:ShowAlert("stealth", "Bazzalan", "Stealth  25 yd")
  if self:SoundOn() then Play("detected-stealth") end
end

-- ---------------------------------------------------------------- key bindings

local function TargetName()
  if UnitExists("target") and UnitIsPlayer("target") and UnitIsEnemy("player", "target") then return UnitName("target") end
  UIErrorsFrame:AddMessage("Target an enemy player first", 1, 0.3, 0.2)
  return nil
end

function OctoBG_ToggleWorld() NB:SetEnabled(not B.db.spy.Enabled) end
function OctoBG_KOSTarget()
  local name = TargetName()
  if name then B.People:ToggleKOS(name) end
end
function OctoBG_IgnoreTarget()
  local name = TargetName()
  if name then B.People:ToggleIgnore(name) end
end
function OctoBG_PostNearby() if B.Roster then B.Roster:PostCount() end end
