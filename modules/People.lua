-- OctoBG :: people (Spy's player database)
-- Everything Spy remembered about enemy players, now part of OctoBG:
--   * a record per enemy name: class, level, race, guild, GUID, where you saw
--     them (zone, sub-zone, your map position), when, wins and losses
--   * Kill On Sight with reasons, the ignore list, Spy's friends list
--   * wins and losses: "You have slain X!" counts a win, your death counts a
--     loss to whoever hit you last (nampower events aimed at you, UNIT_COMBAT)
--   * announcing a player to chat, and sharing sightings with other Spy users
--     on Spy's own addon channel ("[Spy]", same text format, so friends still
--     running Spy keep seeing yours and you theirs)
--   * a one-time import of the old Spy addon's saved data
--
-- Storage (account-wide, OctoBGDB): people[realm][faction] = { players, kos,
-- ignore }; kos / ignore entries are { t = time added, by = character }. With
-- "Share Kill On Sight between characters" off, a character only sees its own
-- entries (Spy kept them per character). Eviction: Spy's purge on login (after
-- the chosen number of days; Kill On Sight and win/loss players kept unless
-- their purge boxes are ticked), and at most MAX_PLAYERS per realm and
-- faction (oldest sighting goes first, Kill On Sight and win/loss players last).

local B = OctoBG
local U = B.U
local P = { guildCache = nil, queue = {} }
B.People = P

local MAX_PLAYERS = 5000
local SPY_PREFIX = "[Spy]"
local SPY_VERSION = "4.2.0"     -- what Spy 4.x sends (newer would nag Spy users to upgrade)

B.DEFAULTS.people = {}          -- [realm][faction] = { players = {}, kos = {}, ignore = {} }
B.DEFAULTS.spyFriends = {}      -- names Spy treated as friends (never enemies)
B.DEFAULTS.spyImportedChars = {}
-- Spy's settings, under Spy's own names (the import is a key copy). Window
-- look lives in db.list (the enemy list is Spy's Nearby window now).
B.DEFAULTS.spy = {
  Enabled = true,                    -- world PvP detection
  EnabledInBattlegrounds = true,     -- detection alerts and the Nearby / Last hour lists in battlegrounds
  DisableWhenPVPUnflagged = false,
  FilteredZones = {},                -- sanctuary sub-zones switched off: [name] = true
  unflagged = false,                 -- also list enemies who are not PvP flagged (Spy never did)
  ShowOnDetection = true,
  ShowNearbyList = true,
  PrioritiseKoS = true,
  EnableSound = true,
  OnlySoundKoS = false,
  MuteSoundInBattlegrounds = true,
  StopAlertsOnTaxi = true,
  Announce = "None",                 -- None | Self | Party | Guild | Raid | LocalDefense
  OnlyAnnounceKoS = false,
  DisplayWarnings = "Default",       -- Default (alert box) | ErrorFrame | Moveable
  WarnOnStealthEvenIfDisabled = false,
  WarnOnKOS = true,
  WarnOnKOSGuild = false,
  WarnOnRace = false,
  SelectWarnRace = "None",
  MinimapDetection = false,
  MinimapDetails = true,
  RemoveUndetectedTime = 5,          -- minutes an undetected enemy stays (greyed); 0 = at once
  PurgeData = "NinetyDays",
  PurgeKoS = false,
  PurgeWinLossData = false,
  ShareData = false,
  UseData = false,
  ShareKOSBetweenCharacters = true,
  DisplayWinLossStatistics = true,
  DisplayKOSReason = true,
  DisplayLastSeen = true,
  CommDebug = false,
}

local PURGE_DAYS = { OneDay = 1, FiveDays = 5, TenDays = 10, ThirtyDays = 30, SixtyDays = 60, NinetyDays = 90 }
P.PURGE = { { key = "OneDay", label = "1 day" }, { key = "FiveDays", label = "5 days" },
            { key = "TenDays", label = "10 days" }, { key = "ThirtyDays", label = "30 days" },
            { key = "SixtyDays", label = "60 days" }, { key = "NinetyDays", label = "90 days" } }

-- ---------------------------------------------------------------- identity / storage

function P:Me()
  if not self.me then self.me = UnitName("player") end
  return self.me
end

function P:Realm()
  local ok, r = pcall(GetCVar, "realmName")
  return (ok and r) or "?"
end

local function StoreOf(realm, faction)
  local db = B.db.people
  if type(db[realm]) ~= "table" then db[realm] = {} end
  local s = db[realm][faction]
  if type(s) ~= "table" then
    s = { players = {}, kos = {}, ignore = {} }
    db[realm][faction] = s
  end
  s.players = s.players or {}
  s.kos = s.kos or {}
  s.ignore = s.ignore or {}
  return s
end

-- This character's realm + faction store (faction known once in the world).
function P:Store()
  if self.store then return self.store end
  local fac = UnitFactionGroup("player")
  if not fac then return StoreOf(self:Realm(), "?") end
  self.store = StoreOf(self:Realm(), fac)
  return self.store
end

function P:Get(name)
  if not name then return nil end
  return self:Store().players[name]
end

-- The record for a name, created when missing.
function P:Ensure(name)
  local players = self:Store().players
  local r = players[name]
  if not r then
    r = { name = name, time = time(), isEnemy = true }
    players[name] = r
    self.count = (self.count or 0) + 1
    if self.count > MAX_PLAYERS then self:Trim() end
  end
  return r
end

local function Keep(self, name, r)
  return self:IsKOS(name) or (r.wins and r.wins > 0) or (r.loses and r.loses > 0)
end

-- Over the limit: drop the oldest plain sightings (KoS / win-loss players last).
function P:Trim()
  local players = self:Store().players
  local list, n = {}, 0
  for name, r in pairs(players) do
    n = n + 1
    list[n] = { name = name, t = r.time or 0, keep = Keep(self, name, r) and 1 or 0 }
  end
  self.count = n
  if n <= MAX_PLAYERS then return end
  table.sort(list, function(a, b)
    if a.keep ~= b.keep then return a.keep < b.keep end
    return a.t < b.t
  end)
  for i = 1, n - MAX_PLAYERS + 100 do
    players[list[i].name] = nil
  end
  self.count = MAX_PLAYERS - 100
end

-- ---------------------------------------------------------------- kill on sight / ignore / friends

local function Mine(self, e)
  return e and (B.db.spy.ShareKOSBetweenCharacters or e.by == self:Me() or not e.by)
end

function P:IsKOS(name)
  return name and Mine(self, self:Store().kos[name]) and true or false
end

function P:IsIgnored(name)
  return name and Mine(self, self:Store().ignore[name]) and true or false
end

function P:IsFriend(name)
  return name and B.db.spyFriends[name] and true or false
end

local function Sound(file)
  if B.Nearby and B.Nearby:SoundOn() then PlaySoundFile(U.MEDIA .. "sounds\\" .. file .. ".wav") end
end

function P:SetKOS(name, on, quiet)
  if not name or name == "" then return end
  local s = self:Store()
  if on then
    s.kos[name] = { t = time(), by = self:Me() }
    s.ignore[name] = nil
    local r = self:Ensure(name)
    r.kos = 1
    if not quiet then
      Sound("list-add")
      B:Print("|cffff5555" .. name .. "|r added to Kill On Sight")
    end
  else
    s.kos[name] = nil
    local r = s.players[name]
    if r then
      r.kos = nil
      r.reason = nil
    end
    if not quiet then
      Sound("list-remove")
      B:Print(name .. " removed from Kill On Sight")
    end
  end
  self.guildCache = nil
  B:Fire("OBG_PEOPLE", name)
end

function P:SetIgnored(name, on, quiet)
  if not name or name == "" then return end
  local s = self:Store()
  if on then
    s.ignore[name] = { t = time(), by = self:Me() }
    if s.kos[name] then self:SetKOS(name, false, true) end
    if not quiet then
      Sound("list-add")
      B:Print(name .. " added to the ignore list")
    end
  else
    s.ignore[name] = nil
    if not quiet then
      Sound("list-remove")
      B:Print(name .. " removed from the ignore list")
    end
  end
  B:Fire("OBG_PEOPLE", name)
end

function P:ToggleKOS(name) self:SetKOS(name, not self:IsKOS(name)) end
function P:ToggleIgnore(name) self:SetIgnored(name, not self:IsIgnored(name)) end

-- Guild of a Kill On Sight player (Spy's "KoS guild" warning).
function P:IsKOSGuild(guild)
  if not guild or guild == "" then return false end
  if not self.guildCache then
    local c = {}
    local s = self:Store()
    for name in pairs(s.kos) do
      local r = s.players[name]
      if r and r.guild and self:IsKOS(name) then c[r.guild] = true end
    end
    self.guildCache = c
  end
  return self.guildCache[guild] and true or false
end

-- Lists for the enemy list's Kill On Sight / Ignore modes: { name = time }.
function P:KOSList()
  local out, s = {}, self:Store()
  for name, e in pairs(s.kos) do
    if Mine(self, e) then out[name] = e.t or 0 end
  end
  return out
end

function P:IgnoreList()
  local out, s = {}, self:Store()
  for name, e in pairs(s.ignore) do
    if Mine(self, e) then out[name] = e.t or 0 end
  end
  return out
end

-- ---------------------------------------------------------------- reasons

-- Spy's reasons: reason[text] = true, the typed one under SpyData.OTHER.
function P:SetReason(name, reason, text)
  local r = self:Ensure(name)
  if not reason then
    r.reason = nil
  elseif reason == B.SpyData.OTHER then
    r.reason = r.reason or {}
    if text and text ~= "" then r.reason[reason] = text else r.reason[reason] = nil end
  else
    r.reason = r.reason or {}
    if r.reason[reason] then r.reason[reason] = nil else r.reason[reason] = true end
  end
  if r.reason and not next(r.reason) then r.reason = nil end
  B:Fire("OBG_PEOPLE", name)
end

function P:ReasonText(name)
  local r = self:Get(name)
  if not r or type(r.reason) ~= "table" then return nil end
  local t = {}
  for reason, v in pairs(r.reason) do
    if reason == B.SpyData.OTHER then
      if type(v) == "string" then table.insert(t, v) end
    else
      table.insert(t, reason)
    end
  end
  if not t[1] then return nil end
  table.sort(t)
  return table.concat(t, ", ")
end

StaticPopupDialogs["OCTOBG_KOS_REASON"] = {
  text = "Kill On Sight reason for %s:",
  button1 = ACCEPT,
  button2 = CANCEL,
  hasEditBox = 1,
  maxLetters = 80,
  OnShow = function()
    getglobal(this:GetName() .. "EditBox"):SetText("")
  end,
  OnAccept = function()
    local d = this:GetParent()
    P:SetReason(d.who, B.SpyData.OTHER, getglobal(d:GetName() .. "EditBox"):GetText())
  end,
  EditBoxOnEnterPressed = function()
    local d = this:GetParent()
    P:SetReason(d.who, B.SpyData.OTHER, this:GetText())
    d:Hide()
  end,
  EditBoxOnEscapePressed = function() this:GetParent():Hide() end,
  timeout = 0,
  whileDead = 1,
  hideOnEscape = 1,
}

function P:AskReason(name)
  local d = StaticPopup_Show("OCTOBG_KOS_REASON", name)
  if d then d.who = name end
end

-- ---------------------------------------------------------------- records from sightings

-- A sighting of an enemy unit (tracker record): fill the record like Spy did,
-- with the place where you were when you saw them.
function P:Saw(u)
  if not u or not u.name or u.fake then return nil end
  local r = self:Ensure(u.name)
  if u.class then r.class = u.class end
  if u.level and (u.level > 0 or not r.level) then r.level = u.level end
  if u.race then r.race = u.race end
  if u.guild then
    if r.guild ~= u.guild then self.guildCache = nil end
    r.guild = u.guild
  end
  if U.IsGuid(u.guid) then r.guid = u.guid end
  r.isEnemy, r.isGuess = true, false
  r.time = time()
  local mx, my = GetPlayerMapPosition("player")
  if mx and my and (mx ~= 0 or my ~= 0) then
    r.mapX, r.mapY = math.floor(mx * 100) / 100, math.floor(my * 100) / 100
  end
  r.zone, r.subZone = GetZoneText(), GetSubZoneText()
  return r
end

-- "Twilight Grove, Duskwood (46,36)"
function P:Location(r)
  if not r then return nil end
  local loc = r.zone
  if loc and r.subZone and r.subZone ~= "" and r.subZone ~= loc then loc = r.subZone .. ", " .. loc end
  if loc and r.mapX and r.mapY and r.mapX ~= 0 and r.mapY ~= 0 then
    loc = loc .. " (" .. math.floor(r.mapX * 100) .. "," .. math.floor(r.mapY * 100) .. ")"
  end
  return loc
end

-- "12s", "5m", "3h", "2d" since a time() stamp.
function P.Ago(t)
  if not t or t <= 0 then return "?" end
  local age = time() - t
  if age < 0 then age = 0 end
  if age >= 86400 then return math.floor(age / 86400) .. "d" end
  if age >= 3600 then return math.floor(age / 3600) .. "h" end
  if age >= 60 then return math.floor(age / 60) .. "m" end
  return age .. "s"
end

-- "less than a minute ago", "5 minutes ago"...
function P.LastSeen(t)
  if not t then return nil end
  local minutes = math.floor((time() - t) / 60)
  local hours = math.floor(minutes / 60)
  if minutes <= 0 then return "less than a minute ago" end
  if minutes < 60 then return minutes .. " minutes ago" end
  if hours < 24 then return hours .. " hours ago" end
  return math.floor(hours / 24) .. " days ago"
end

-- ---------------------------------------------------------------- purge (Spy's, on login)

function P:Purge()
  local spy = B.db.spy
  local timeout = (PURGE_DAYS[spy.PurgeData] or 90) * 86400
  local now = time()
  local s = self:Store()
  local n = 0
  for name, r in pairs(s.players) do
    local expired = type(r) ~= "table" or not r.time or now - r.time > timeout or r.isEnemy == false
    if expired then
      local wl = type(r) == "table" and ((r.wins or 0) > 0 or (r.loses or 0) > 0)
      local kos = s.kos[name] ~= nil
      if (wl and not spy.PurgeWinLossData) or (kos and not spy.PurgeKoS and not spy.PurgeWinLossData) then
        expired = false
      end
    end
    if expired then
      s.players[name] = nil
      s.ignore[name] = nil
      if spy.PurgeKoS or spy.PurgeWinLossData then s.kos[name] = nil end
    else
      n = n + 1
    end
  end
  self.count = n
  if n > MAX_PLAYERS then self:Trim() end
  self.guildCache = nil
end

-- ---------------------------------------------------------------- wins and losses

-- Who hit you last (enemy players only), for the loss when you die.
P.lastAttack, P.lastAttackGuid = nil, nil

local function MyGuid()
  return U.GuidOf("player")
end

local function Attacked(guid)
  if not guid or not U.GuidExists(guid) or not UnitIsPlayer(guid) then return end
  local mine, theirs = UnitFactionGroup("player"), UnitFactionGroup(guid)
  if mine and theirs and mine == theirs and B.zone ~= "ARENA" then return end
  local name = UnitName(guid)
  if name and name ~= P:Me() then
    P.lastAttack, P.lastAttackGuid = name, guid
  end
end

local function On()
  return B.Nearby and B.Nearby:LayerOn()
end

B:On("SPELL_GO_OTHER", function(ev, item, spell, caster, target, flags, hit, missed)
  if not On() or not target or target ~= MyGuid() then return end
  if missed and missed > 0 and (not hit or hit == 0) then return end
  Attacked(caster)
end, true)
B:On("SPELL_DAMAGE_EVENT_OTHER", function(ev, target, caster)
  if On() and target and target == MyGuid() then Attacked(caster) end
end, true)
B:On("AUTO_ATTACK_OTHER", function(ev, attacker, target)
  if On() and target and target == MyGuid() then Attacked(attacker) end
end, true)
B:On("SPELL_MISS_OTHER", function(ev, caster, target)
  if On() and target and target == MyGuid() then Attacked(caster) end
end, true)
-- Damage taken while an enemy player is your target (Spy's UNIT_COMBAT rule).
B:On("UNIT_COMBAT", function(ev, unit, action, crit, amount)
  if unit ~= "player" or action ~= "WOUND" or not amount or amount <= 0 or not On() then return end
  if UnitExists("target") and UnitIsPlayer("target") and UnitIsEnemy("player", "target") then
    local name = UnitName("target")
    if name then P.lastAttack, P.lastAttackGuid = name, U.GuidOf("target") end
  end
end, true)

B:On("PLAYER_REGEN_ENABLED", function()
  if not P.dying then P.lastAttack, P.lastAttackGuid = nil, nil end
end, true)

local function Known(name)
  return P:Get(name) ~= nil or B.Tracker:FindByName(name) ~= nil
end

B:On("CHAT_MSG_COMBAT_HOSTILE_DEATH", function(ev, msg)
  if not On() or not msg then return end
  local _, _, victim = string.find(msg, "^You have slain (.+)!$")
  if not victim then return end
  local dash = string.find(victim, "-", 1, true)
  if dash then victim = string.sub(victim, 1, dash - 1) end
  if not Known(victim) then return end
  local r = P:Ensure(victim)
  r.wins = (r.wins or 0) + 1
  local u = B.Tracker:FindByName(victim)
  if u and U.IsGuid(u.guid) then r.guid = u.guid end
  B:Fire("OBG_PEOPLE", victim)
end, true)

-- Your death is counted a second later: late hits arrive after the message.
B:On("CHAT_MSG_COMBAT_FRIENDLY_DEATH", function(ev, msg)
  if not On() or not msg then return end
  if string.find(msg, "^You die") or string.find(msg, "^You have died") then
    P.dying = GetTime() + 1
  end
end, true)

function P:CountLoss()
  self.dying = nil
  local killer, guid = self.lastAttack, self.lastAttackGuid
  if not killer then
    -- Spy's fallback: the enemy seen most recently
    local best
    for _, u in pairs(B.Tracker.units) do
      if u.visible and not u.fake and u.name and (not best or u.seen > best.seen) then best = u end
    end
    if best then killer, guid = best.name, best.guid end
  end
  self.lastAttack, self.lastAttackGuid = nil, nil
  if not killer then return end
  local r = self:Ensure(killer)
  r.loses = (r.loses or 0) + 1
  if U.IsGuid(guid) then r.guid = guid end
  B:Fire("OBG_PEOPLE", killer)
end

B:Every(0.25, function()
  if P.dying and GetTime() >= P.dying then P:CountLoss() end
end)

-- ---------------------------------------------------------------- announcing

local CLASS_NAME = { WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue", PRIEST = "Priest",
                     SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid" }
P.CLASS_NAME = CLASS_NAME

function P:LocalDefense()
  local id = GetChannelName("LocalDefense - " .. (GetZoneText() or ""))
  if id and id > 0 then return id end
  return nil
end

-- "[Spy] Player detected: Name <Guild> - Level 60 Night Elf Rogue - Duskwood (46,36)"
function P:AnnounceText(name, colored)
  local r = self:Get(name)
  if not r or not r.class or r.level == nil then return nil end
  local kos = self:IsKOS(name)
  local msg
  if colored then
    msg = "|cff9933ff[Spy]|r " .. (kos and "|cffff0000Kill On Sight player detected:|r " or "|cff40ff00Player detected:|r ") .. name
  else
    msg = (kos and "[Spy] Kill On Sight player detected: " or "[Spy] Player detected: ") .. name
  end
  if r.guild and r.guild ~= "" then msg = msg .. " <" .. r.guild .. ">" end
  msg = msg .. " - Level " .. ((r.level == 0) and "??" or r.level)
  if r.race and r.race ~= "" then msg = msg .. " " .. r.race end
  msg = msg .. " " .. (CLASS_NAME[r.class] or r.class)
  local loc = self:Location(r)
  if loc then msg = msg .. " - " .. loc end
  return msg
end

-- To a chosen channel from a menu (PARTY, RAID, GUILD, BATTLEGROUND, LOCAL).
function P:AnnounceTo(name, channel)
  local msg = self:AnnounceText(name, false)
  if not msg then
    B:Print("not enough known about " .. tostring(name) .. " yet (class and level)")
    return
  end
  if channel == "LOCAL" then
    local id = self:LocalDefense()
    if id then SendChatMessage(msg, "CHANNEL", nil, id) else B:Print("you are not in the LocalDefense channel here") end
  elseif channel == "BATTLEGROUND" then
    U.SendBG(msg)
  elseif (channel == "PARTY" and GetNumPartyMembers() > 0) or (channel == "RAID" and GetNumRaidMembers() > 0)
      or (channel == "GUILD" and GetGuildInfo("player")) then
    SendChatMessage(msg, channel)
  else
    B:Print("nobody to tell in " .. string.lower(channel))
  end
  self:Share(name, channel)
end

-- The automatic announcement of a new sighting (Spy's "Announce to").
function P:Announce(name)
  local spy = B.db.spy
  local how = spy.Announce
  if how == "None" or not how then return end
  if spy.OnlyAnnounceKoS and not self:IsKOS(name) then return end
  local inInstance = B.Nearby and B.Nearby.inInstance
  if how == "Self" then
    local msg = self:AnnounceText(name, true)
    if msg then DEFAULT_CHAT_FRAME:AddMessage(msg) end
    return
  end
  local msg = self:AnnounceText(name, false)
  if not msg then return end
  if how == "LocalDefense" then
    local id = self:LocalDefense()
    if id then SendChatMessage(msg, "CHANNEL", nil, id) end
  elseif how == "Party" and GetNumPartyMembers() > 0 then
    SendChatMessage(msg, "PARTY")
  elseif how == "Raid" and GetNumRaidMembers() > 0 then
    SendChatMessage(msg, "RAID")
  elseif how == "Guild" and GetGuildInfo("player") and not inInstance then
    SendChatMessage(msg, "GUILD")
  end
end

-- ---------------------------------------------------------------- Spy's addon channel

-- version,player,class,level,race,zone,subZone,mapX,mapY,guild,guid
function P:Share(name, channel)
  if not B.db.spy.ShareData or (B.Nearby and B.Nearby.standDown) then return end
  local r = self:Get(name)
  if not r then return end
  local function S(v) if v == nil then return "" end return tostring(v) end
  local level = (r.level and r.isGuess == false) and r.level or ""
  local msg = SPY_VERSION .. "," .. name .. "," .. S(r.class) .. "," .. S(level) .. "," .. S(r.race) .. ","
    .. S(r.zone) .. "," .. S(r.subZone) .. "," .. S(r.mapX) .. "," .. S(r.mapY) .. "," .. S(r.guild) .. "," .. S(r.guid)
  if string.len(msg) >= 240 then return end
  local inInstance = B.Nearby and B.Nearby.inInstance
  if channel then
    if (channel == "PARTY" and GetNumPartyMembers() > 0) or (channel == "RAID" and GetNumRaidMembers() > 0)
       or (channel == "GUILD" and GetGuildInfo("player")) then
      self:Queue(msg, channel)
    end
    return
  end
  if GetNumRaidMembers() > 0 then
    self:Queue(msg, "RAID")
  elseif GetNumPartyMembers() > 0 then
    self:Queue(msg, "PARTY")
  end
  if not inInstance and GetGuildInfo("player") then self:Queue(msg, "GUILD") end
end

-- At most one message every 0.3 s; the queue keeps the newest 20.
function P:Queue(msg, channel)
  local q = self.queue
  if table.getn(q) >= 20 then table.remove(q, 1) end
  table.insert(q, { msg, channel })
end

B:Every(0.3, function()
  local e = P.queue[1]
  if e then
    table.remove(P.queue, 1)
    SendAddonMessage(SPY_PREFIX, e[1], e[2])
  end
end)

local F = {}
local function Split(s)
  local n = 0
  for f in string.gfind(s .. ",", "([^,]*),") do
    n = n + 1
    F[n] = f
    if n >= 11 then break end
  end
  for i = n + 1, 11 do F[i] = nil end
  return n
end

local function Debug(msg)
  if B.db.spy.CommDebug then B:Print("|cff888888[Spy channel]|r " .. msg) end
end

P.heard = {}    -- name -> time() of the last accepted report (5 s per player; wiped at 300)
local nheard = 0

-- A sighting from another Spy / OctoBG user.
function P:Heard(msg, source)
  local spy = B.db.spy
  if not spy.UseData or not On() then return end
  if not source or source == self:Me() or type(msg) ~= "string" or string.len(msg) > 255 then return end
  Split(msg)
  local player, class, level, race, zone, sub, mx, my, guild, guid = F[2], F[3], F[4], F[5], F[6], F[7], F[8], F[9], F[10], F[11]
  if not player or player == "" or string.len(player) > 24 then return end
  local NB = B.Nearby
  if NB and NB.inInstance and zone ~= GetZoneText() then Debug(player .. ": another instance") return end
  if self:IsFriend(player) or self:IsIgnored(player) then return end
  local now = time()
  if self.heard[player] and now - self.heard[player] < 5 then return end
  local D = B.SpyData
  if class and class ~= "" and not D.CLASSES[class] then Debug(player .. ": bad class") return end
  if race and race ~= "" and not D.RACE_OK[race] then Debug(player .. ": bad race") return end
  local lvl
  if level and level ~= "" then
    lvl = tonumber(level)
    if not lvl or lvl < -1 or lvl > 60 or (lvl > 0 and math.floor(lvl) ~= lvl) then Debug(player .. ": bad level") return end
    if lvl < 0 then lvl = 0 end
  end
  mx, my = tonumber(mx), tonumber(my)
  if mx and (mx < 0 or mx > 1) then return end
  if my and (my < 0 or my > 1) then return end
  if guild and string.len(guild) > 24 then return end
  -- a GUID that proves the same faction (duels) is not an enemy
  local u = B.Tracker:FindByName(player)
  if not u and U.IsGuid(guid) and U.GuidExists(guid) then
    local mine, theirs = UnitFactionGroup("player"), UnitFactionGroup(guid)
    if mine and theirs and mine == theirs then return end
  end
  if nheard >= 300 then self.heard, nheard = {}, 0 end
  if not self.heard[player] then nheard = nheard + 1 end
  self.heard[player] = now
  local r = self:Ensure(player)
  if class and class ~= "" and not r.class then r.class = class end
  if lvl and not r.level then r.level = lvl end
  if race and race ~= "" and not r.race then r.race = race end
  if guild and guild ~= "" and not r.guild then r.guild = guild end
  if U.IsGuid(guid) and not r.guid then r.guid = guid end
  if zone and zone ~= "" then r.zone = zone end
  if sub and sub ~= "" then r.subZone = sub end
  if mx then r.mapX = math.floor(mx * 100) / 100 end
  if my then r.mapY = math.floor(my * 100) / 100 end
  r.time, r.isEnemy = now, true
  Debug("accepted " .. player .. " from " .. source)
  if NB then NB:Heard(player, source) end
end

B:On("CHAT_MSG_ADDON", function(ev, prefix, msg, channel, sender)
  if prefix == SPY_PREFIX then P:Heard(msg, sender) end
end, true)

-- ---------------------------------------------------------------- the old Spy addon

function P:SpyLoaded()
  return IsAddOnLoaded and IsAddOnLoaded("Spy") and true or false
end

-- Spy's defaults for the settings OctoBG copies: AceDB saves only what
-- differs from them, so a missing key means this value.
local SPY_DEF = {
  Enabled = true, EnabledInBattlegrounds = true, DisableWhenPVPUnflagged = false, ShowOnDetection = true,
  ShowNearbyList = true, PrioritiseKoS = true, EnableSound = true, OnlySoundKoS = false,
  MuteSoundInBattlegrounds = false, StopAlertsOnTaxi = true, Announce = "None", OnlyAnnounceKoS = false,
  DisplayWarnings = "Default", WarnOnStealthEvenIfDisabled = false, WarnOnKOS = true, WarnOnKOSGuild = false,
  WarnOnRace = false, SelectWarnRace = "None", MinimapDetection = false, MinimapDetails = true,
  RemoveUndetectedTime = 5, PurgeData = "NinetyDays", PurgeKoS = false, PurgeWinLossData = false,
  ShareData = false, UseData = false, ShareKOSBetweenCharacters = true, DisplayWinLossStatistics = true,
  DisplayKOSReason = true, DisplayLastSeen = true,
}

local function Pick(prof, key)
  local v = prof[key]
  if v == nil then v = SPY_DEF[key] end
  return v
end

-- Spy's settings for this character (its profile) -> OctoBG, once.
function P:ImportSettings()
  if B.db.spyImported or type(SpyDB) ~= "table" then return false end
  local keys, profiles = SpyDB.profileKeys, SpyDB.profiles
  local key = (type(keys) == "table" and keys[self:Me() .. " - " .. self:Realm()]) or "Default"
  local prof = type(profiles) == "table" and profiles[key]
  if type(prof) ~= "table" then prof = {} end
  local spy = B.db.spy
  for k, def in pairs(SPY_DEF) do
    local v = Pick(prof, k)
    if type(v) == type(def) then spy[k] = v end
  end
  if type(prof.FilteredZones) == "table" then
    for z, on in pairs(prof.FilteredZones) do spy.FilteredZones[z] = on and true or nil end
  end
  if prof.WarnOnStealth ~= nil then B.db.stealth.alert = prof.WarnOnStealth and true or false end
  local list = B.db.list
  if type(prof.NearbySortOrder) == "string" then list.sortWorld = prof.NearbySortOrder end
  if prof.HideSpy ~= nil then list.hideEmpty = prof.HideSpy and true or false end
  if prof.InvertSpy ~= nil then list.growUp = prof.InvertSpy and true or false end
  if type(prof.ResizeSpyLimit) == "number" then list.rows = math.max(1, math.min(40, prof.ResizeSpyLimit)) end
  if prof.Locked ~= nil then list.locked = prof.Locked and true or false end
  if prof.EnableDistanceDisplay ~= nil then list.distance = prof.EnableDistanceDisplay and true or false end
  if type(prof.DistanceUpdateRate) == "number" then list.rate = math.max(1, math.min(5, prof.DistanceUpdateRate)) end
  if prof.DisplayTooltipNearSpyWindow ~= nil then list.tipNear = prof.DisplayTooltipNearSpyWindow and true or false end
  if type(prof.TooltipAnchor) == "string" then list.tipAnchor = prof.TooltipAnchor end
  if type(prof.Font) == "string" and B.SpyData.FONT_BY_NAME[prof.Font] then list.font = B.SpyData.FONT_BY_NAME[prof.Font] end
  if prof.BarTexture == "blend" or prof.BarTexture == "Minimalist" then list.bar = prof.BarTexture end
  local mw = prof.MainWindow
  if type(mw) == "table" then
    if type(mw.RowHeight) == "number" then list.rowHeight = math.max(10, math.min(24, mw.RowHeight + 1)) end
    if type(mw.Alpha) == "number" then list.alpha = math.max(0.2, mw.Alpha) end
    if type(mw.AlphaBG) == "number" then list.alphaBG = math.max(0.2, mw.AlphaBG) end
    if type(mw.Position) == "table" and type(mw.Position.w) == "number" then
      list.width = math.max(190, math.min(400, math.floor(mw.Position.w)))
    end
  end
  local aw = prof.AlertWindow
  if type(aw) == "table" and type(aw.Position) == "table" and aw.Position.x and aw.Position.y then
    spy.alertX, spy.alertY = aw.Position.x, aw.Position.y
  end
  if type(prof.ldbIcon) == "table" and prof.ldbIcon.hide then spy.spyIconHidden = true end
  B.db.spyImported = true
  return true
end

local function Merge(dst, src, byChar)
  -- one record into another: newer sighting wins, counts add up
  if type(src) ~= "table" then return end
  if (src.time or 0) >= (dst.time or 0) then
    for _, k in ipairs({ "class", "race", "guild", "zone", "subZone", "mapX", "mapY", "time" }) do
      if src[k] ~= nil then dst[k] = src[k] end
    end
    if type(src.level) == "number" then dst.level = src.level end
    if src.isGuess ~= nil then dst.isGuess = src.isGuess end
  else
    for _, k in ipairs({ "class", "race", "guild" }) do
      if dst[k] == nil and src[k] ~= nil then dst[k] = src[k] end
    end
    if dst.level == nil and type(src.level) == "number" then dst.level = src.level end
  end
  if src.guid and not dst.guid then dst.guid = src.guid end
  if byChar then
    if type(src.wins) == "number" then dst.wins = (dst.wins or 0) + src.wins end
    if type(src.loses) == "number" then dst.loses = (dst.loses or 0) + src.loses end
  else
    if type(src.wins) == "number" and src.wins > (dst.wins or 0) then dst.wins = src.wins end
    if type(src.loses) == "number" and src.loses > (dst.loses or 0) then dst.loses = src.loses end
  end
  if type(src.reason) == "table" then
    dst.reason = dst.reason or {}
    for k, v in pairs(src.reason) do dst.reason[k] = v end
  end
  if src.isEnemy ~= nil then dst.isEnemy = src.isEnemy end
end

-- This character's Spy data (players, Kill On Sight, ignore) once per
-- character; every character's shared Kill On Sight list and the friends
-- list every login while Spy is enabled. Spy's saved files are only read.
function P:ImportData()
  local imported = false
  local me, realm = self:Me(), self:Realm()
  local fac = UnitFactionGroup("player")
  local tag = realm .. "|" .. tostring(me)
  if type(SpyPerCharDB) == "table" and fac and not B.db.spyImportedChars[tag] then
    local s = self:Store()
    if type(SpyPerCharDB.PlayerData) == "table" then
      for name, d in pairs(SpyPerCharDB.PlayerData) do
        if type(name) == "string" and name ~= "" and name ~= "Unknown" and type(d) == "table" then
          local r = s.players[name]
          if not r then
            r = { name = name }
            s.players[name] = r
          end
          Merge(r, d, true)
        end
      end
    end
    if type(SpyPerCharDB.KOSData) == "table" then
      for name, t in pairs(SpyPerCharDB.KOSData) do
        if type(name) == "string" and not s.kos[name] then
          s.kos[name] = { t = (type(t) == "number") and t or time(), by = me }
          local r = s.players[name] or { name = name, time = time(), isEnemy = true }
          s.players[name] = r
          r.kos = 1
        end
      end
    end
    if type(SpyPerCharDB.IgnoreData) == "table" then
      for name in pairs(SpyPerCharDB.IgnoreData) do
        if type(name) == "string" and not s.ignore[name] then s.ignore[name] = { t = time(), by = me } end
      end
    end
    B.db.spyImportedChars[tag] = true
    imported = true
  end
  if type(SpyDB) == "table" then
    -- the central Kill On Sight list: every character on every realm
    if type(SpyDB.kosData) == "table" then
      for rlm, facs in pairs(SpyDB.kosData) do
        if type(facs) == "table" then
          for f, chars in pairs(facs) do
            local removed = SpyDB.removeKOSData and SpyDB.removeKOSData[rlm] and SpyDB.removeKOSData[rlm][f]
            local s = (type(chars) == "table") and StoreOf(rlm, f)
            if s then
              for char, list in pairs(chars) do
                if type(list) == "table" then
                  for name, d in pairs(list) do
                    if type(name) == "string" and not (type(removed) == "table" and removed[name]) then
                      if not s.kos[name] then
                        s.kos[name] = { t = (type(d) == "table" and type(d.added) == "number") and d.added or time(), by = char }
                        imported = true
                      end
                      local r = s.players[name]
                      if not r then
                        r = { name = name }
                        s.players[name] = r
                      end
                      Merge(r, d, false)
                      r.kos = 1
                    end
                  end
                end
              end
            end
          end
        end
      end
    end
    if type(SpyDB.FriendsData) == "table" then
      for name, on in pairs(SpyDB.FriendsData) do
        if type(name) == "string" and on and not B.db.spyFriends[name] then
          B.db.spyFriends[name] = true
          imported = true
        end
      end
    end
  end
  if imported then self.guildCache = nil end
  return imported
end

StaticPopupDialogs["OCTOBG_OLD_SPY"] = {
  text = "Spy is now built into OctoBG.\n\nYour Kill On Sight list, reasons, ignore list, this character's player statistics (wins and losses) and Spy settings have been copied over. Switch the old Spy addon off for this character now? (The interface reloads.)\n\nSpy kept statistics per character: log your other characters in once with Spy still on and each gets the same offer.\n\nUntil then OctoBG keeps its own world PvP alerts quiet so nothing shows twice.",
  button1 = "Switch it off",
  button2 = "Not now",
  OnAccept = function()
    DisableAddOn("Spy")
    ReloadUI()
  end,
  timeout = 0,
  whileDead = 1,
  hideOnEscape = 1,
}

local loginDone = false
B:On("PLAYER_ENTERING_WORLD", function()
  P.store = nil
  P:Store()
  if loginDone then return end
  loginDone = true
  local any = P:ImportSettings()
  if P:ImportData() then any = true end
  if any then B:Print("Spy's data has been copied into OctoBG (Kill On Sight, ignore, statistics, settings)") end
  P:Purge()
  if P:SpyLoaded() then StaticPopup_Show("OCTOBG_OLD_SPY") end
end)
