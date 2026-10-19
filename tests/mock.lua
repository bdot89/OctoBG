-- A stand-in for the 1.12 client, enough to run every OctoBG file offline
-- (tools: DmorphOcto\tools\LuaHost on OBS's lua51.dll; see run.ps1).
--
-- Widgets accept any method (unknown setters are no-ops, the getters OctoBG
-- uses return sensible values) except names this client does not have
-- (SetSize, SetShown, HookScript...), which raise an error like the client.
-- Scripts run with this / event / arg1..arg9 globals, as in the client.

Mock = { frames = {}, now = 1000, clock = 1700000000, sent = {}, chat = {}, sounds = {}, printed = {}, units = {} }

local NOT_IN_112 = {
  SetSize = 1, SetShown = 1, SetColorTexture = 1, SetAtlas = 1, HookScript = 1, GetOwner = 1,
  SetIgnoreParentAlpha = 1, CreateAnimationGroup = 1, SetClipsChildren = 1, SetObeyStepOnDrag = 1,
  SetMouseClickEnabled = 1, SetMouseMotionEnabled = 1, IsMouseOver = 1, SetFixedFrameStrata = 1,
  GetNumPoints = 1, SetResizeBounds = 1, SetGradientAlpha = 1,
}

local methods = {}
local meta = {
  __index = function(w, key)
    local m = methods[key]
    if m then return m end
    if NOT_IN_112[key] then error("1.12 has no " .. w.kind .. ":" .. key .. "()", 2) end
    local first = string.sub(key, 1, 1)
    if first == string.upper(first) and first ~= "_" then
      return function() end
    end
    return nil
  end,
}

local function New(kind, name, parent)
  local w = setmetatable({ kind = kind, name = name, parent = parent, shown = true, scripts = {}, events = {},
                           children = {}, w = 0, h = 0, level = 1, alpha = 1 }, meta)
  if name then _G[name] = w end
  if parent then table.insert(parent.children, w) end
  if kind ~= "Texture" and kind ~= "FontString" then table.insert(Mock.frames, w) end
  return w
end
Mock.New = New

function methods:SetWidth(v) self.w = v end
function methods:SetHeight(v) self.h = v end
function methods:GetWidth() return self.w end
function methods:GetHeight() return self.h end
function methods:SetPoint(p, rel, rp, x, y)
  assert(type(p) == "string", "SetPoint needs a point")
  self.point = { p, rel, rp, x, y }
end
function methods:GetLeft() return 100 end
function methods:GetTop() return 700 end
function methods:GetBottom() return 600 end
function methods:GetRight() return 300 end
function methods:GetCenter() return 200, 650 end
function methods:GetName(a) if a == 1 then return self.plateGuid end return self.name end
function methods:GetParent() return self.parent end
function methods:GetChildren() return unpack(self.children) end
function methods:GetNumChildren() return table.getn(self.children) end
function methods:IsShown() return self.shown end
function methods:IsVisible()
  local w = self
  while w do
    if not w.shown then return false end
    w = w.parent
  end
  return true
end
local function Run(w, script, a1)
  local fn = w.scripts[script]
  if fn then
    local oldThis, oldArg = this, arg1
    this, arg1 = w, a1
    fn()
    this, arg1 = oldThis, oldArg
  end
end
Mock.Run = Run
function methods:Show()
  if not self.shown then
    self.shown = true
    if self:IsVisible() then Run(self, "OnShow") end
  end
end
function methods:Hide()
  if self.shown then
    self.shown = false
    Run(self, "OnHide")
  end
end
function methods:SetScript(s, fn)
  assert(fn == nil or type(fn) == "function", s .. " must be a function")
  self.scripts[s] = fn
end
function methods:GetScript(s) return self.scripts[s] end
function methods:RegisterEvent(e) self.events[e] = true end
function methods:UnregisterEvent(e) self.events[e] = nil end
function methods:UnregisterAllEvents() self.events = {} end
function methods:GetFrameLevel() return self.level end
function methods:SetFrameLevel(l) self.level = l end
function methods:GetEffectiveScale() return 1 end
function methods:GetScale() return 1 end
function methods:SetAlpha(a) self.alpha = a end
function methods:GetAlpha() return self.alpha end
function methods:CreateTexture(name, layer) return New("Texture", name, self) end
function methods:CreateFontString(name, layer, inherits) return New("FontString", name, self) end
function methods:SetText(t)
  assert(t == nil or type(t) == "string" or type(t) == "number", "SetText needs a string, got " .. type(t))
  self.text = t and tostring(t)
  if self.kind == "EditBox" then Run(self, "OnTextChanged") end
end
function methods:GetText()
  if self.kind == "EditBox" then return self.text or "" end
  return self.text
end
function methods:GetStringWidth() return string.len(self.text or "") * 6 end
function methods:SetFont(f, s, fl)
  assert(type(f) == "string" and type(s) == "number", "SetFont needs file and size")
  self.font = { f, s, fl }
end
function methods:GetFont() local f = self.font or { "Fonts\\FRIZQT__.TTF", 12, "" } return f[1], f[2], f[3] end
function methods:SetTexture(t) self.texture = t end
function methods:GetTexture() return self.texture end
function methods:SetTexCoord(a, b, c, d, e, f, g, h)
  assert(type(a) == "number" and type(d) == "number", "SetTexCoord needs numbers")
  assert(e == nil or type(h) == "number", "SetTexCoord takes 4 or 8 numbers")
end
function methods:SetVertexColor(r, g, b, a)
  assert(type(r) == "number" and type(g) == "number" and type(b) == "number", "SetVertexColor needs numbers")
end
function methods:SetTextColor(r, g, b, a)
  assert(type(r) == "number" and type(g) == "number" and type(b) == "number", "SetTextColor needs numbers")
  self.color = { r, g, b, a }
end
function methods:SetChecked(v) self.checked = v and 1 or nil end
function methods:GetChecked() return self.checked end
function methods:SetMinMaxValues(a, b) self.min, self.max = a, b end
function methods:GetMinMaxValues() return self.min or 0, self.max or 1 end
function methods:SetValue(v)
  self.value = v
  Run(self, "OnValueChanged")
end
function methods:GetValue() return self.value or 0 end
function methods:StartMoving() end
function methods:StopMovingOrSizing() end
function methods:IsObjectType(t) return self.kind == t end
function methods:GetModel() return self.model end
function methods:GetFacing() return 0.3 end
function methods:SetOwner(o, a) self.owner = o self.lines = {} end
function methods:AddLine(t) table.insert(self.lines or {}, t) end
function methods:AddDoubleLine(a, b) table.insert(self.lines or {}, tostring(a) .. " " .. tostring(b)) end
function methods:IsOwned(f) return self.owner == f end
function methods:ClearLines() self.lines = {} end
function methods:AddMessage(t) table.insert(Mock.printed, tostring(t)) end
function methods:GetNumRegions() return 0 end
function methods:UpdateScrollChildRect() end

function CreateFrame(kind, name, parent, template)
  local f = New(kind, name, parent)
  f.template = template
  if template == "OptionsSliderTemplate" then
    New("FontString", name .. "Low", f)
    New("FontString", name .. "High", f)
    New("FontString", name .. "Text", f)
  elseif template == "UIPanelButtonTemplate" and name then
    New("FontString", name .. "Text", f)   -- <ButtonText name="$parentText"/> (patch-4 UIPanelTemplates.xml)
  end
  return f
end

UIParent = New("Frame", "UIParent")
WorldFrame = New("Frame", "WorldFrame")
Minimap = New("Frame", "Minimap")
local arrow = New("Model", nil, Minimap)
arrow.model = "Interface\\Minimap\\MinimapArrow.mdx"
GameTooltip = New("GameTooltip", "GameTooltip", UIParent)
GameTooltip.shown = false
GameTooltipTextLeft1 = New("FontString", "GameTooltipTextLeft1", GameTooltip)
UIErrorsFrame = New("Frame", "UIErrorsFrame", UIParent)
DEFAULT_CHAT_FRAME = New("Frame", "ChatFrame1", UIParent)
WorldMapFrame = New("Frame", "WorldMapFrame", UIParent)
WorldMapFrame.shown = false
ColorPickerFrame = New("Frame", "ColorPickerFrame", UIParent)
OpacitySliderFrame = New("Slider", "OpacitySliderFrame", UIParent)
UISpecialFrames = {}
SlashCmdList = {}
StaticPopupDialogs = {}
YES, NO, ACCEPT, CANCEL = "Yes", "No", "Accept", "Cancel"
UIERRORS_HOLD_TIME = 5
RAID_CLASS_COLORS = {}
for _, c in ipairs({ "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }) do
  RAID_CLASS_COLORS[c] = { r = 0.5, g = 0.6, b = 0.7 }
end

function getglobal(n) return _G[n] end
function GetTime() return Mock.now end
time = function() return math.floor(Mock.clock) end
date = function(fmt) return "14 Oct" end
function IsShiftKeyDown() return Mock.shift end
function IsControlKeyDown() return Mock.ctrl end
function IsAltKeyDown() return Mock.alt end
function GetCursorPosition() return Mock.cx or 0, Mock.cy or 0 end
function MouseIsOver(f) return Mock.over == f end
-- key bindings (Blizzard_BindingUI's calls)
Mock.bindings = {}
function SetBinding(key, action) Mock.bindings[key] = action return 1 end
function GetBindingKey(action)
  local a, b
  for k, v in pairs(Mock.bindings) do
    if v == action then
      if not a then a = k else b = k end
    end
  end
  return a, b
end
function GetBindingAction(key) return Mock.bindings[key] or "" end
function SaveBindings(which) Mock.bindingsSaved = (Mock.bindingsSaved or 0) + 1 end
function GetCurrentBindingSet() return 1 end
function GetBindingText(action) return action end
function PlaySound(s) table.insert(Mock.sounds, s) end
function PlaySoundFile(s) table.insert(Mock.sounds, s) end
function SendChatMessage(msg, ch) table.insert(Mock.chat, { msg, ch }) end
function SendAddonMessage(p, msg, ch) table.insert(Mock.sent, { p, msg, ch }) end
function GetChannelName() return 0 end
function IsAddOnLoaded(n) return Mock.loaded and Mock.loaded[n] end
function DisableAddOn() end
function ReloadUI() end
function ShowUIPanel(f) f:Show() end
function StaticPopup_Show(which, a)
  Mock.popup = which
  local d = New("Frame", "StaticPopup1", UIParent)
  New("EditBox", "StaticPopup1EditBox", d)
  d.which = which
  return d
end
function UIDropDownMenu_Initialize(frame, fn, kind) Mock.menuInit = fn end
function UIDropDownMenu_AddButton(info, level)
  assert(type(info) == "table", "AddButton needs info")
  Mock.menuItems = Mock.menuItems or {}
  table.insert(Mock.menuItems, info)
end
function ToggleDropDownMenu(level, value, frame, anchor, x, y)
  Mock.menuItems = {}
  UIDROPDOWNMENU_MENU_VALUE = value
  if Mock.menuInit then Mock.menuInit(level or 1) end
end
function CloseDropDownMenus() end
function GameTooltip_SetDefaultAnchor(tip, parent) tip:SetOwner(parent, "ANCHOR_NONE") end
function KeyBindingFrame_LoadUI() end
function WorldMap_GetPOITextureCoords(i) return 0, 0.125, 0, 0.125 end

-- ---------------------------------------------------------------- the world

Mock.zone, Mock.sub, Mock.pvp = "Duskwood", "Raven Hill", "contested"
Mock.faction = "Horde"
Mock.px, Mock.py = -10500, -500     -- Duskwood, in world yards (x north, y west)
Mock.raid, Mock.party = 0, 0
Mock.scores = {}
Mock.cvars = { realmName = "Y'Shaarj", NP_EnableSpellGoEvents = "0", NP_EnableSpellStartEvents = "1",
               NP_EnableAutoAttackEvents = "1", NP_EnableAuraCastEvents = "0", farclip = "500",
               horizonfarclip = "2112", unitDrawDist = "300" }
function GetCVar(n) return Mock.cvars[n] end
function SetCVar(n, v) Mock.cvars[n] = tostring(v) end
function GetRealZoneText() return Mock.zone end
function GetZoneText() return Mock.zone end
function GetSubZoneText() return Mock.sub end
function GetZonePVPInfo() return Mock.pvp end
function IsInInstance() return Mock.instance ~= nil, Mock.instance end
function UnitOnTaxi() return Mock.taxi end
function GetNumRaidMembers() return Mock.raid end
function GetNumPartyMembers() return Mock.party end
function GetGuildInfo(u)
  local e = Mock.units[u]
  if e then return e.guild end
  return nil
end
local MAPS = { Duskwood = "Duskwood", ["Warsong Gulch"] = "WarsongGulch" }
function SetMapToCurrentZone() end
function GetMapInfo() return MAPS[Mock.zone] end
function GetPlayerMapPosition(u)
  if u == "player" then return Mock.pmx or 0.45, Mock.pmy or 0.4 end
  return 0, 0
end
function GetNumMapLandmarks() return 0 end
function GetMapLandmarkInfo() return nil end
function GetNumBattlefieldScores() return table.getn(Mock.scores) end
function GetBattlefieldScore(i)
  local s = Mock.scores[i]
  return s[1], 0, 0, 0, 0, s[2], 0, 0, s[3]
end
function RequestBattlefieldScoreData() end
function GetNumBattlefieldFlagPositions() return 0 end
function GetBattlefieldFlagPosition() return nil end
function GetAreaSpiritHealerTime() return 0 end
function GetNumWorldStateUI() return 0 end
function GetWorldStateUIInfo() return nil end
function GetNampowerVersion() return 3, 1, 0 end
SUPERWOW_VERSION = "1.5"
function SpellInfo(id) return "Spell" .. tostring(id), "", "Interface\\Icons\\Spell" end
function GetSpellIdCooldown() return 0 end
function TargetUnit(g) Mock.target = g end
function TargetByName(n) Mock.targetName = n end
function ClearTarget() Mock.target = nil end
function TargetLastTarget() end
function CastSpellByName() end

-- Units: "player", "target" and enemy GUIDs in Mock.units.
local ME = "0x0000000000000001"
local function E(u)
  if u == "target" then return Mock.units[Mock.target or ""] end
  if u == "mouseover" then return Mock.units[Mock.mouseover or ""] end
  return Mock.units[u]
end
function UnitExists(u)
  if u == "player" then return 1, ME end
  local e = E(u)
  if e and e.near then return 1, e.guid end
  return nil
end
function GetUnitGUID(u)
  if u == "player" then return ME end
  local e = E(u)
  if e and e.near then return e.guid end
  return nil
end
function UnitName(u)
  if u == "player" then return "Tester" end
  local e = E(u)
  return e and e.name
end
function UnitClass(u)
  if u == "player" then return "Warrior", "WARRIOR" end
  local e = E(u)
  if e then return e.class, e.class end
  return nil
end
function UnitLevel(u)
  if u == "player" then return 60 end
  local e = E(u)
  return e and e.level or 0
end
function UnitRace(u)
  local e = E(u)
  if e then return e.race, e.raceToken end
  return "Orc", "Orc"
end
function UnitFactionGroup(u)
  if u == "player" then return Mock.faction end
  local e = E(u)
  return e and e.faction
end
function UnitIsPlayer(u) return u == "player" or (E(u) and not E(u).npc and true) or false end
function UnitAffectingCombat(u) local e = E(u) return e and e.combat or false end
function UnitIsEnemy(a, u) local e = E(u) return e and e.faction ~= Mock.faction end
function UnitCanAttack(a, u) return UnitIsEnemy(a, u) end
function UnitIsPVP(u) if u == "player" then return 1 end local e = E(u) return e and e.pvp end
function UnitHealth(u)
  if u == "player" then return Mock.playerHp or 100 end
  local e = E(u)
  return e and e.hp or 100
end
function UnitHealthMax(u) return 100 end
function UnitIsDeadOrGhost(u) local e = E(u) return e and e.hp == 0 end
function UnitIsGhost(u) return false end
function UnitIsUnit(a, b) return a == b end
function GetUnitField(g, key)
  local e = Mock.units[g]
  if not e then return nil end
  if key == "health" then return e.hp end
  if key == "maxHealth" then return 100 end
  if key == "aura" then return e.auras or {} end
  return nil
end
function UnitPosition(u)
  if u == "player" then return Mock.px, Mock.py, 0 end
  local e = E(u)
  if e then return Mock.px + e.x, Mock.py + e.y, 0 end
  return nil
end
function UnitXP(what, a, b)
  if what == "distanceBetween" then
    if b == "player" then return 0 end
    local e = Mock.units[b]
    if e then return math.sqrt(e.x * e.x + e.y * e.y) end
    return nil
  end
  if what == "inSight" then return true end
  return nil
end

function Mock.Enemy(guid, name, class, x, y, extra)
  local e = { guid = guid, name = name, class = class, x = x, y = y, hp = 80, level = 60, race = "Human",
              raceToken = "Human", faction = "Alliance", pvp = 1, near = true, guild = "Sample Guild" }
  for k, v in pairs(extra or {}) do e[k] = v end
  Mock.units[guid] = e
  return e
end

-- ---------------------------------------------------------------- driving

function Mock.Fire(ev, a1, a2, a3, a4, a5, a6, a7, a8, a9)
  local list = {}
  for _, f in ipairs(Mock.frames) do
    if f.events[ev] then table.insert(list, f) end
  end
  for _, f in ipairs(list) do
    local fn = f.scripts.OnEvent
    if fn then
      local o = { this, event, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9 }
      this, event, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9 = f, ev, a1, a2, a3, a4, a5, a6, a7, a8, a9
      fn()
      this, event, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9 = o[1], o[2], o[3], o[4], o[5], o[6], o[7], o[8], o[9], o[10], o[11]
    end
  end
end

-- Advances the clock in steps of dt, running every visible frame's OnUpdate.
function Mock.Tick(seconds, dt)
  dt = dt or 0.05
  local t = 0
  while t < seconds do
    Mock.now = Mock.now + dt
    Mock.clock = Mock.clock + dt
    local list = {}
    for _, f in ipairs(Mock.frames) do
      if f.scripts.OnUpdate and f:IsVisible() then table.insert(list, f) end
    end
    for _, f in ipairs(list) do Run(f, "OnUpdate", dt) end
    t = t + dt
  end
end

function Mock.Load(dir, toc)
  local files = {}
  for line in io.lines(dir .. "/" .. toc) do
    if not string.find(line, "^##") and string.find(line, "%.lua%s*$") then
      table.insert(files, (string.gsub(string.gsub(line, "%s+$", ""), "\\", "/")))
    end
  end
  for _, f in ipairs(files) do dofile(dir .. "/" .. f) end
  return files
end

-- ---------------------------------------------------------------- combat text helpers

BOOKTYPE_SPELL = "spell"
Mock.book = { { "Overpower", 0 }, { "Revenge", 0 }, { "Execute", 0 }, { "Recklessness", 1800 } }
function GetSpellName(i) local s = Mock.book[i] return s and s[1] end
function GetSpellTexture(i) return "Interface\\Icons\\Spell" .. tostring(i) end
function GetSpellCooldown(i)
  local s = Mock.book[i]
  if s and Mock.cdStart and s[2] > 0 then return Mock.cdStart, s[2], 1 end
  return 0, 0, 1
end
function GetComboPoints() return Mock.cp or 0 end
function UnitMana(u) return Mock.mana or 500 end
function UnitManaMax(u) return 1000 end
function UnitPowerType(u) return 0 end
function ShowNameplates() Mock.platesOn = true end

-- A nameplate for a GUID among WorldFrame's children (nampower's GetName(1)).
function Mock.Plate(guid)
  local p = New("Frame", nil, WorldFrame)
  p.plateGuid = guid
  return p
end
