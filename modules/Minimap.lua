-- OctoBG :: minimap button
-- Left-click: options. Shift-click: enemy statistics (as Spy's button did).
-- Ctrl-click: world PvP detection on / off. Right-click: a menu of quick
-- switches. Drag (right button) to move it around the minimap. Replaces
-- EnemyCooldowns' and Spy's buttons; EnemyCooldowns' position carries over.

local B = OctoBG
local U = B.U
local MB = {}
B.Minimap = MB

B.DEFAULTS.minimap = { pos = 200, hide = false }

local RADIUS = 78

function MB:Place()
  local a = math.rad(B.db.minimap.pos or 200)
  self.button:ClearAllPoints()
  self.button:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 54 - RADIUS * math.cos(a), RADIUS * math.sin(a) - 55)
end

function MB:Drag()
  local x, y = GetCursorPosition()
  local left, bottom = Minimap:GetLeft(), Minimap:GetBottom()
  if not left or not bottom then return end
  local s = UIParent:GetScale()
  x = left - x / s + 70
  y = y / s - bottom - 70
  local deg = math.deg(math.atan2(y, x))
  if deg < 0 then deg = deg + 360 end
  B.db.minimap.pos = deg
  self:Place()
end

function MB:Update()
  if not self.button then return end
  if B.db.minimap.hide then self.button:Hide() else self.button:Show() end
end

-- quick switches: { label, function() return on end, function() toggle end }
local function Toggle(tbl, key, after)
  return function()
    tbl()[key] = not tbl()[key]
    if after then after() end
    if B.Options then B.Options:Refresh() end
  end
end

local SWITCHES = {
  { "Move frames", function() return not B.db.locked end, function() U.SetLocked(not B.db.locked) end },
  { "Enemy map", function() return B.db.map.enabled end, Toggle(function() return B.db.map end, "enabled") },
  { "Enemy list", function() return B.db.list.enabled end, Toggle(function() return B.db.list end, "enabled",
      function() if B.Roster and B.db.list.enabled then B.Roster:Open() end end) },
  { "World PvP detection", function() return B.db.spy.Enabled end, function() B.Nearby:SetEnabled(not B.db.spy.Enabled) end },
  { "Detection sounds", function() return B.db.spy.EnableSound end, Toggle(function() return B.db.spy end, "EnableSound") },
  { "Radar HUD", function() return B.db.hud.enabled end, Toggle(function() return B.db.hud end, "enabled", function() B:RefreshActive() end) },
  { "Cooldown bars", function() return B.db.cd.bars end, Toggle(function() return B.db.cd end, "bars") },
  { "Nameplate cooldowns", function() return B.db.cd.nameplates end, Toggle(function() return B.db.cd end, "nameplates") },
  { "Diminishing returns", function() return B.db.cd.showDR end, Toggle(function() return B.db.cd end, "showDR") },
  { "Stealth marks", function() return B.db.stealth.enabled end, Toggle(function() return B.db.stealth end, "enabled") },
  { "Keep target (Feign Death)", function() return B.db.retarget.enabled end, Toggle(function() return B.db.retarget end, "enabled") },
  { "Keep target (Vanish, Stealth)", function() return B.db.retarget.rogue end, Toggle(function() return B.db.retarget end, "rogue") },
  { "Grab rogues with Hunter's Mark", function() return B.db.retarget.mark end, Toggle(function() return B.db.retarget end, "mark") },
}

local function MenuInit()
  UIDropDownMenu_AddButton({ text = "OctoBG", isTitle = 1, notCheckable = 1 })
  for i = 1, table.getn(SWITCHES) do
    local s = SWITCHES[i]
    UIDropDownMenu_AddButton({ text = s[1], checked = s[2]() and 1 or nil, func = function()
      s[3]()
      CloseDropDownMenus()
    end })
  end
  UIDropDownMenu_AddButton({ text = "Enemy statistics...", notCheckable = 1, func = function()
    if B.Stats then B.Stats:Show() end
    CloseDropDownMenus()
  end })
  UIDropDownMenu_AddButton({ text = "Max view distance", notCheckable = 1, func = function()
    if B.Options then B.Options:MaxView(false) end
    CloseDropDownMenus()
  end })
  UIDropDownMenu_AddButton({ text = "Options...", notCheckable = 1, func = function()
    if B.Options then B.Options:Open() end
    CloseDropDownMenus()
  end })
  UIDropDownMenu_AddButton({ text = "Hide this button", notCheckable = 1, func = function()
    B.db.minimap.hide = true
    MB:Update()
    B:Print("minimap button hidden - bring it back under General in /obg")
    CloseDropDownMenus()
  end })
end

function MB:Build()
  local b = CreateFrame("Button", "OctoBGMinimapButton", Minimap)
  b:SetWidth(33)
  b:SetHeight(33)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel(8)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("RightButton")
  local icon = b:CreateTexture(nil, "BORDER")
  icon:SetWidth(20)
  icon:SetHeight(20)
  icon:SetPoint("CENTER", b, "CENTER", -2, 1)
  icon:SetTexture((B.faction == "Horde") and "Interface\\Icons\\INV_BannerPVP_01" or "Interface\\Icons\\INV_BannerPVP_02")
  icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  self.icon = icon
  local border = b:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetWidth(52)
  border:SetHeight(52)
  border:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
  local hl = b:CreateTexture()
  hl:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  hl:SetBlendMode("ADD")
  b:SetHighlightTexture(hl)

  b:SetScript("OnDragStart", function() this.dragging = true end)
  b:SetScript("OnDragStop", function()
    this.dragging = nil
    this.dragEnd = GetTime()
  end)
  b:SetScript("OnUpdate", function() if this.dragging then MB:Drag() end end)
  b:SetScript("OnClick", function()
    if this.dragEnd and GetTime() - this.dragEnd < 0.3 then return end   -- the release of a drag
    if arg1 == "RightButton" then
      if not MB.menu then MB.menu = CreateFrame("Frame", "OctoBGMinimapMenu", UIParent, "UIDropDownMenuTemplate") end
      UIDropDownMenu_Initialize(MB.menu, MenuInit, "MENU")
      ToggleDropDownMenu(1, nil, MB.menu, this, 0, 0)
    elseif IsShiftKeyDown() then
      if B.Stats then B.Stats:Toggle() end
    elseif IsControlKeyDown() then
      B.Nearby:SetEnabled(not B.db.spy.Enabled)
    elseif B.Options then
      B.Options:Toggle()
    end
  end)
  b:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_LEFT")
    GameTooltip:AddLine("|cff33ccffOcto|rBG")
    local NB = B.Nearby
    if B.db.spy.Enabled and NB.enabledInZone and not NB:Standing() then
      GameTooltip:AddLine("World PvP: " .. NB:ActiveCount() .. " enemies seen now", 0.4, 1, 0.4)
    elseif not B.db.spy.Enabled then
      GameTooltip:AddLine("World PvP detection is off", 1, 0.4, 0.4)
    end
    GameTooltip:AddLine("Left-click: options", 1, 1, 1)
    GameTooltip:AddLine("Shift-click: enemy statistics", 1, 1, 1)
    GameTooltip:AddLine("Ctrl-click: world PvP detection on / off", 1, 1, 1)
    GameTooltip:AddLine("Right-click: quick switches", 1, 1, 1)
    GameTooltip:AddLine("Right-drag: move this button", 1, 1, 1)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  self.button = b
  self:Place()
  self:Update()
end

B:On("OBG_INIT", function() MB:Build() end)

-- the faction is known only once the player is in the world
B:On("PLAYER_ENTERING_WORLD", function()
  if MB.icon then
    MB.icon:SetTexture((B.faction == "Horde") and "Interface\\Icons\\INV_BannerPVP_01" or "Interface\\Icons\\INV_BannerPVP_02")
  end
end)
