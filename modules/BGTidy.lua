-- OctoBG :: a tidier battleground screen
--   * the game's score frame at the top (WorldStateAlwaysUpFrame: "0/3",
--     bases, resources) hidden in battlegrounds when OctoBG's panels show it
--   * BigWigs' Arathi Basin / Alterac Valley bars kept quiet while OctoBG's
--     timers panel runs (BigWigs' modules draw them through module:Bar - that
--     one call is wrapped; BigWigs itself is never changed)
--   * AV mode: nameplates for enemy PLAYERS only - no NPCs (guards, the
--     hundreds of Alterac Valley mobs), no friendly plates. A toggle in the
--     options, a button you can place, a key binding, /obg avmode.
--     With pfUI's nameplates: its own "hide" settings (enemy / neutral /
--     friendly NPCs, friendly players) are set while on and put back after.
--     Game nameplates: plates that are not enemy players are made invisible
--     and unclickable (alpha 0; GUID from nampower's frame:GetName(1)).

local B = OctoBG
local U = B.U
local BT = { faded = {} }
B.BGTidy = BT

B.DEFAULTS.tidy = { scoreFrame = false, bigwigs = true }
B.DEFAULTS.avmode = { on = false, button = false, saved = nil, enemyWas = nil, friendWas = nil }

-- ---------------------------------------------------------------- score frame

-- The frame's own Show is replaced while hidden and given back after, so the
-- game can't show it again behind our back; no chat needed to undo it.
function BT:ScoreFrame()
  local f = WorldStateAlwaysUpFrame
  if not f then return end
  local hide = B.db.tidy.scoreFrame and B:IsBG()
  if hide then
    if not self.scoreHidden then
      f.Show = function() end
      self.scoreHidden = true
    end
    f:Hide()
  elseif self.scoreHidden then
    f.Show = nil          -- the frame's own Show again
    self.scoreHidden = nil
    f:Show()
  end
end

-- ---------------------------------------------------------------- BigWigs

-- Our timers run where they have something to show: AB and AV with the panel on.
function BT:OursRunning()
  return B.db.timers.enabled and (B.zone == "AB" or B.zone == "AV")
end

function BT:QuietBigWigs()
  if self.bwDone or not BigWigs or not BigWigs.GetModule then return end
  for _, name in ipairs({ "Arathi Basin", "Alterac Valley" }) do
    local ok, mod = pcall(BigWigs.GetModule, BigWigs, name)
    if ok and mod and mod.Bar and not mod.obgBar then
      mod.obgBar = mod.Bar
      mod.Bar = function(self, a1, a2, a3, a4, a5, a6, a7, a8)
        if B.db and B.db.tidy.bigwigs and BT:OursRunning() then return end
        return self.obgBar(self, a1, a2, a3, a4, a5, a6, a7, a8)
      end
      self.bwDone = true
    end
  end
end

-- ---------------------------------------------------------------- AV mode

local PF_KEYS = { "enemynpc", "neutralnpc", "friendlynpc", "friendlyplayer" }

local function PfuiPlates()
  return pfUI and pfUI.nameplates and pfUI_config and pfUI_config.nameplates
end

local function IsPlate(f)
  if not f or not f.GetRegions then return false end
  local r = f:GetRegions()
  return r and r.GetTexture and r:GetTexture() == "Interface\\Tooltips\\Nameplate-Border"
end

-- Plates of anything but enemy players go invisible (game nameplates only).
function BT:Fade(on)
  local kids = { WorldFrame:GetChildren() }
  for i = 1, table.getn(kids) do
    local f = kids[i]
    if f:IsVisible() and IsPlate(f) then
      local guid = f.GetName and f:GetName(1)
      local keep = not on or (U.IsGuid(guid) and UnitIsPlayer(guid) and UnitCanAttack("player", guid))
      if keep then
        if self.faded[f] then
          f:SetAlpha(1)
          f:EnableMouse(true)
          self.faded[f] = nil
        end
      elseif U.IsGuid(guid) then
        f:SetAlpha(0)
        f:EnableMouse(false)
        self.faded[f] = true
      end
    end
  end
  if not on then
    for f in pairs(self.faded) do
      f:SetAlpha(1)
      f:EnableMouse(true)
    end
    self.faded = {}
  end
end

function BT:SetAV(on)
  local A = B.db.avmode
  on = on and true or false
  if on == (A.on and true or false) and not self.avForce then return end
  self.avForce = nil
  A.on = on
  local pc = PfuiPlates()
  if on then
    A.enemyWas = (NAMEPLATES_ON ~= nil) and (NAMEPLATES_ON and true or false) or nil
    A.friendWas = (FRIENDNAMEPLATES_ON ~= nil) and (FRIENDNAMEPLATES_ON and true or false) or nil
    if ShowNameplates then ShowNameplates() NAMEPLATES_ON = 1 end
    if HideFriendNameplates then HideFriendNameplates() FRIENDNAMEPLATES_ON = nil end
    if pc then
      if not A.saved then
        A.saved = {}
        for _, k in ipairs(PF_KEYS) do A.saved[k] = pc[k] end
      end
      for _, k in ipairs(PF_KEYS) do pc[k] = "1" end
      pc.enemyplayer = "0"
    end
    B:Print("|cffff7a3aAV mode on|r - nameplates for enemy players only")
  else
    if pc and A.saved then
      for _, k in ipairs(PF_KEYS) do pc[k] = A.saved[k] end
    end
    A.saved = nil
    if A.friendWas and ShowFriendNameplates then ShowFriendNameplates() FRIENDNAMEPLATES_ON = 1 end
    if A.enemyWas == false and HideNameplates then HideNameplates() NAMEPLATES_ON = nil end
    self:Fade(false)
    B:Print("AV mode off - your nameplates as before")
  end
  self:PaintButton()
  if B.Options then B.Options:Refresh() end
end

function BT:ToggleAV() self:SetAV(not B.db.avmode.on) end
function OctoBG_ToggleAVMode() BT:ToggleAV() end

-- the button: a small movable panel (Move frames places it)
function BT:BuildButton()
  local f = U.Panel("OctoBGAVButton", "avbutton", "AV mode button", 92, 24, "TOP", 160, -120)
  local b = CreateFrame("Button", "OctoBGAVButtonClick", f, "UIPanelButtonTemplate")
  b:SetAllPoints(f)
  b:SetScript("OnClick", function() BT:ToggleAV() end)
  b:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("AV mode")
    GameTooltip:AddLine("On: nameplates for enemy players only - no NPCs, no friendly plates.", 1, 1, 1, 1)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  self.button, self.buttonClick = f, b
  self:PaintButton()
end

function BT:PaintButton()
  local f, b = self.button, self.buttonClick
  if not f then return end
  local on = B.db.avmode.on
  b:SetText(on and "AV mode: ON" or "AV mode: off")
  local t = getglobal(b:GetName() .. "Text")
  if t then
    if on then t:SetTextColor(0.35, 1, 0.35) else t:SetTextColor(1, 0.82, 0) end
  end
  if B.db.avmode.button or B.test then f:Show() else f:Hide() end
end

-- ---------------------------------------------------------------- wiring

B:On("OBG_INIT", function()
  BT:BuildButton()
  BT:QuietBigWigs()
  if B.db.avmode.on then
    BT.avForce = true
    BT:SetAV(true)
  end
end)
B:On("PLAYER_ENTERING_WORLD", function()
  BT:QuietBigWigs()
  BT:ScoreFrame()
end)
B:On("OBG_ZONE", function() BT:ScoreFrame() end)
B:On("UPDATE_WORLD_STATES", function() if BT.scoreHidden then WorldStateAlwaysUpFrame:Hide() end end)
B:On("OBG_LAYOUT", function() BT:PaintButton() end)
B:Every(0.1, function()
  if B.db.avmode.on and not PfuiPlates() then BT:Fade(true) end
end)

B:Command("avmode", "AV mode: nameplates for enemy players only (on / off / nothing to swap)", function(rest)
  rest = string.lower(rest or "")
  if rest == "on" then BT:SetAV(true) elseif rest == "off" then BT:SetAV(false) else BT:ToggleAV() end
end)
