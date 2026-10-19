-- OctoBG :: cooldown bars
-- Your target's cooldowns as bars (from EnemyCooldowns' main frame): spell,
-- time left, colour by time left (or by class), a shaded zone where the
-- enemy's talents may already have the spell back, a green sub-bar while an
-- immunity (Ice Block, Divine Shield...) is still running, and a row of
-- diminishing returns. A header says whose cooldowns these are: your target,
-- your last target (sticky, dimmed) or, in Warsong Gulch with no target, the
-- enemy flag carrier. Right-click a bar to hide that spell.

local B = OctoBG
local U = B.U
local CD = B.CD
local D = B.CDData
local CB = { bars = {}, drw = {}, drs = {} }
B.CDBars = CB

local SPACE, IMM_SPACE, PAD, HEAD = 2, 1, 4, 14

local function Font(fs, size)
  fs:SetFont(U.NARROW, size, "OUTLINE")
end

-- ---------------------------------------------------------------- bars

local function OnEnter()
  if not this.spellName then return end
  GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
  GameTooltip:SetText(this.spellName, 1, 1, 1)
  GameTooltip:AddLine("Cooldown: " .. CD.Time(this.duration or 0), 0.8, 0.8, 0.8)
  GameTooltip:AddLine("Ready in: " .. CD.Time(math.max(0, (this.endTime or 0) - GetTime())), 0.8, 0.8, 0.8)
  local learned = CB.guid and CD:GetLearned(CB.guid, this.spellName)
  if learned then
    GameTooltip:AddLine("Learned from this enemy: " .. CD.Time(learned), 0.4, 0.9, 0.4)
  elseif this.unsure then
    GameTooltip:AddLine("Talents can cut this to " .. CD.Time(D.TALENT_MIN_CD[this.spellName]), 1, 0.75, 0.2)
    GameTooltip:AddLine("Shaded part: it may already be ready", 1, 0.75, 0.2)
  end
  if this.spellID then GameTooltip:AddLine("Spell ID " .. this.spellID, 0.5, 0.5, 0.5) end
  GameTooltip:AddLine("Right-click: hide this spell", 0.4, 0.8, 0.4)
  GameTooltip:Show()
end

local menuSpell
local function MenuInit()
  local name = menuSpell
  if not name then return end
  local info = { text = name, isTitle = 1, notCheckable = 1 }
  UIDropDownMenu_AddButton(info)
  info = { text = "Hide this spell", notCheckable = 1, func = function()
    CD:SetBlocked(name, true)
    B:Print("hiding |cffffff00" .. name .. "|r - bring it back under Spell filter in /obg")
    CloseDropDownMenus()
  end }
  UIDropDownMenu_AddButton(info)
  local class = CD.SPELL_CLASS[name]
  if class and class ~= "OTHERS" then
    local pretty = string.upper(string.sub(class, 1, 1)) .. string.lower(string.sub(class, 2))
    info = { text = "Hide all " .. pretty .. " spells", notCheckable = 1, func = function()
      CD:SetClassBlocked(class, true)
      B:Print("hiding all " .. pretty .. " spells")
      CloseDropDownMenus()
    end }
    UIDropDownMenu_AddButton(info)
  end
  info = { text = "Cooldown settings", notCheckable = 1, func = function()
    if B.Options then B.Options:Open("cdbars") end
    CloseDropDownMenus()
  end }
  UIDropDownMenu_AddButton(info)
  info = { text = "Cancel", notCheckable = 1, func = function() CloseDropDownMenus() end }
  UIDropDownMenu_AddButton(info)
end

local function OnClick()
  if arg1 ~= "RightButton" or not this.spellName then return end
  menuSpell = this.spellName
  if not CB.menu then CB.menu = CreateFrame("Frame", "OctoBGCDBarMenu", UIParent, "UIDropDownMenuTemplate") end
  UIDropDownMenu_Initialize(CB.menu, MenuInit, "MENU")
  ToggleDropDownMenu(1, nil, CB.menu, this, 0, 0)
end

function CB:Bar(i)
  local b = self.bars[i]
  if b then return b end
  b = CreateFrame("Button", nil, self.frame)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:SetScript("OnEnter", OnEnter)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  b:SetScript("OnClick", OnClick)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  b.bg = U.Tex(b, U.WHITE, "BACKGROUND")
  b.bg:SetVertexColor(0.15, 0.15, 0.15, 0.8)
  b.fill = U.Tex(b, U.WHITE, "BORDER")
  b.zone = U.Tex(b, U.WHITE, "ARTWORK")
  b.zone:SetVertexColor(1, 0.75, 0.2, 0.22)
  b.imm = U.Tex(b, U.WHITE, "ARTWORK")
  b.imm:SetVertexColor(0.12, 0.63, 0, 0.8)
  b.immText = U.Text(b, 9, U.NARROW)
  b.text = U.Text(b, 10, U.NARROW)
  b.text:SetJustifyH("LEFT")
  b.timer = U.Text(b, 10, U.NARROW)
  b:Hide()
  self.bars[i] = b
  return b
end

function CB:DRWidget(i)
  local w = self.drw[i]
  if w then return w end
  w = CreateFrame("Frame", nil, self.frame)
  w.bg = U.Tex(w, U.WHITE, "BACKGROUND")
  w.bg:SetAllPoints(w)
  w.bg:SetVertexColor(0.1, 0.1, 0.1, 0.85)
  w.fill = U.Tex(w, U.WHITE, "BORDER")
  w.fill:SetPoint("TOPLEFT", w, "TOPLEFT", 0, 0)
  w.fill:SetPoint("BOTTOMLEFT", w, "BOTTOMLEFT", 0, 0)
  w.label = U.Text(w, 9, U.NARROW)
  w.label:SetPoint("CENTER", w, "CENTER", 0, 0)
  self.drw[i] = w
  return w
end

-- ---------------------------------------------------------------- update

-- Fill colour: past the talented minimum orange, else class or time-left colours.
local function FillColor(b, rem, unsure)
  if unsure then return 0.95, 0.65, 0.15, 0.7 end
  if B.db.cd.classColors then
    local r, g, bl = CD.SpellColor(b.spellName)
    return r, g, bl, 0.6
  end
  if rem < 5 then return 0.9, 0.2, 0.2, 0.7 end
  if rem < 10 then return 0.9, 0.7, 0.2, 0.7 end
  return 0.3, 0.6, 1.0, 0.6
end

function CB:PaintBar(b, now, W, H, iconOff)
  local db = B.db.cd
  local rem = math.max(0, b.endTime - now)
  local unsure = b.unsure and rem <= b.unsure
  local fs = db.fontSize
  Font(b.text, fs)
  Font(b.timer, fs)
  b.icon:SetTexture(b.texture or "Interface\\Icons\\INV_Misc_QuestionMark")
  b.icon:ClearAllPoints()
  b.timer:ClearAllPoints()
  if db.iconOnly then
    b:SetWidth(H)
    b:SetHeight(H)
    b.icon:SetAllPoints(b)
    b.icon:Show()
    b.bg:Hide()
    b.fill:Hide()
    b.zone:Hide()
    b.text:Hide()
    b.timer:SetPoint("BOTTOM", b, "BOTTOM", 0, 1)
    if unsure then b.timer:SetTextColor(1, 0.75, 0.2)
    elseif rem < 5 then b.timer:SetTextColor(1, 0.3, 0.3)
    elseif rem < 10 then b.timer:SetTextColor(1, 0.8, 0.3)
    else b.timer:SetTextColor(1, 1, 1) end
  else
    b:SetWidth(W)
    b:SetHeight(H)
    if db.showIcon then
      b.icon:SetWidth(H)
      b.icon:SetHeight(H)
      b.icon:SetPoint("LEFT", b, "LEFT", 0, 0)
      b.icon:Show()
    else
      b.icon:Hide()
    end
    local pw = W - iconOff
    b.bg:ClearAllPoints()
    b.bg:SetPoint("TOPLEFT", b, "TOPLEFT", iconOff, 0)
    b.bg:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
    b.bg:Show()
    local frac = rem / b.duration
    if not db.invertFill then frac = 1 - frac end
    b.fill:ClearAllPoints()
    b.fill:SetPoint("LEFT", b, "LEFT", iconOff, 0)
    b.fill:SetHeight(H)
    b.fill:SetWidth(math.max(1, pw * frac))
    b.fill:SetVertexColor(FillColor(b, rem, unsure))
    b.fill:Show()
    if b.unsure then
      b.zone:ClearAllPoints()
      b.zone:SetPoint("RIGHT", b, "RIGHT", 0, 0)
      b.zone:SetHeight(H)
      b.zone:SetWidth(math.max(1, pw * (b.unsure / b.duration)))
      b.zone:Show()
    else
      b.zone:Hide()
    end
    b.text:ClearAllPoints()
    b.text:SetPoint("LEFT", b, "LEFT", iconOff + 4, 0)
    b.text:SetWidth(pw - 40)
    b.text:SetText(b.spellName)
    b.text:Show()
    b.timer:SetPoint("RIGHT", b, "RIGHT", -4, 0)
    b.timer:SetTextColor(1, 1, 1)
  end
  b.timer:SetText((unsure and "~" or "") .. CD.Time(rem))

  -- immunity effect still running: thin green bar under the bar
  local eff = b.showImm and D.IMMUNITY_SPELLS[b.spellID]
  local left = eff and (eff - (now - b.startTime))
  if left and left > 0 then
    local w = db.iconOnly and H or (W - iconOff)
    local frac = db.invertFill and (left / eff) or (1 - left / eff)
    b.imm:ClearAllPoints()
    b.imm:SetPoint("TOPLEFT", b, "BOTTOMLEFT", db.iconOnly and 0 or iconOff, -IMM_SPACE)
    b.imm:SetHeight(db.immuneBarHeight)
    b.imm:SetWidth(math.max(1, w * frac))
    b.imm:Show()
    if db.immuneAlwaysShowTimer or left <= eff / 2 then
      b.immText:ClearAllPoints()
      b.immText:SetPoint("LEFT", b.imm, "RIGHT", 2, 0)
      b.immText:SetText(CD.Time(left))
      b.immText:Show()
    else
      b.immText:Hide()
    end
  else
    b.imm:Hide()
    b.immText:Hide()
  end
  b:EnableMouse(db.interactiveBars and true or false)
  b:Show()
end

local function ImmExtra(b, now)
  local eff = b.showImm and D.IMMUNITY_SPELLS[b.spellID]
  if eff and eff - (now - b.startTime) > 0 then return B.db.cd.immuneBarHeight + IMM_SPACE end
  return 0
end

function CB:Update()
  local f = self.frame
  local db = B.db.cd
  local guid, how, name
  if B.test then
    if not CD.cache[CD.SAMPLE] then CD:LoadSamples() end
    guid, how, name = CD.SAMPLE, "target", "Testmage"
  else
    guid, how, name = CD:Subject()
  end
  self.guid = guid
  if not db.bars or CD.standDown or not guid then
    if f:IsShown() then f:Hide() end
    return
  end
  local now = GetTime()
  local list = CD:GetActiveCooldowns(guid)
  local n = math.min(table.getn(list), db.maxBars)
  -- copy out of the shared table first
  for i = 1, n do
    local e = list[i]
    local b = self:Bar(i)
    b.spellName, b.spellID, b.duration, b.endTime = e.spellName, e.spellID, e.duration, e.endTime
    b.startTime, b.texture = e.startTime, e.texture
    b.showImm = db.showImmuneBars and e.spellID and D.IMMUNITY_SPELLS[e.spellID] and true or false
    local tmin = db.showUncertainty and D.TALENT_MIN_CD[e.spellName]
    b.unsure = (tmin and tmin < e.duration) and (e.duration - tmin) or nil
  end
  for i = n + 1, table.getn(self.bars) do
    local b = self.bars[i]
    b:Hide()
    b.imm:Hide()
    b.immText:Hide()
    b.spellName = nil
  end
  local ndr = db.showDR and CD:CollectDR(guid, self.drs) or 0
  if n == 0 and ndr == 0 then
    if f:IsShown() then f:Hide() end
    return
  end

  -- size
  local W, H = db.barWidth, db.barHeight
  local iconOff = (db.showIcon and not db.iconOnly) and (H + SPACE) or 0
  local head = db.showWho and HEAD or 0
  local drH = (ndr > 0) and (db.drHeight + SPACE) or 0
  local total, width = PAD * 2 + head + drH, W + PAD * 2
  if db.iconOnly then
    local extra = 0
    for i = 1, n do extra = math.max(extra, ImmExtra(self.bars[i], now)) end
    if n > 0 then total = total + H + extra end
    width = math.max(n * H + (n - 1) * SPACE, ndr * (db.drWidth + SPACE), 80) + PAD * 2
  else
    for i = 1, n do total = total + H + ImmExtra(self.bars[i], now) + ((i > 1) and SPACE or 0) end
  end
  f:SetWidth(width)
  f:SetHeight(total)
  f:SetAlpha(db.alpha * ((how == "last") and 0.45 or 1))

  -- whose cooldowns
  if db.showWho then
    local r, g, bl = 0.85, 0.85, 0.85
    if U.IsGuid(guid) and UnitClass(guid) then
      local _, class = UnitClass(guid)
      r, g, bl = U.ClassColor(class)
    elseif guid == CD.SAMPLE then
      r, g, bl = U.ClassColor("MAGE")
    end
    local note = (how == "last" and " |cff888888(last target)|r") or (how == "efc" and " |cffff5555(enemy flag carrier)|r") or ""
    f.head:SetText(U.Hex(r, g, bl) .. (name or "?") .. "|r" .. note)
    f.head:Show()
  else
    f.head:Hide()
  end

  -- place the bars: down from the header, or up from the DR row
  local y = db.growUp and (PAD + drH) or -(PAD + head)
  for i = 1, n do
    local b = self.bars[i]
    local ext = ImmExtra(b, now)
    b:ClearAllPoints()
    if db.iconOnly then
      local x = PAD + (i - 1) * (H + SPACE)
      if db.growUp then
        b:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", x, y + (ext > 0 and ext or 0))
      else
        b:SetPoint("TOPLEFT", f, "TOPLEFT", x, y)
      end
    elseif db.growUp then
      b:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, y + ext)
      y = y + H + ext + SPACE
    else
      b:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)
      y = y - H - ext - SPACE
    end
    self:PaintBar(b, now, W, H, iconOff)
  end

  -- diminishing returns along the bottom
  local x = PAD
  for i = 1, ndr do
    local e = self.drs[i]
    local w = self:DRWidget(i)
    w:SetWidth(db.drWidth)
    w:SetHeight(db.drHeight)
    w:ClearAllPoints()
    w:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", x, PAD)
    Font(w.label, math.max(7, db.fontSize - 1))
    w.label:SetText(e.label .. " " .. CD.FormatDR(e.multiplier))
    if e.multiplier <= 0 then w.label:SetTextColor(1, 0.35, 0.35) else w.label:SetTextColor(e.r, e.g, e.b) end
    w.fill:SetVertexColor(e.r, e.g, e.b, 0.25)
    w.fill:SetWidth(math.max(1, db.drWidth * math.min(1, e.remaining / (D.DR_WINDOW * 2))))
    w:Show()
    x = x + db.drWidth + SPACE
  end
  for i = ndr + 1, table.getn(self.drw) do self.drw[i]:Hide() end

  if not f:IsShown() then f:Show() end
end

-- ---------------------------------------------------------------- setup

function CB:Build()
  local db = B.db.cd
  local f = U.Panel("OctoBGCDBars", "cdbars", "Enemy cooldowns", db.barWidth + PAD * 2, 60, "CENTER", 300, 160)
  f:Hide()
  f.head = U.Text(f, 10, U.NARROW)
  f.head:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -PAD + 1)
  f.head:SetJustifyH("LEFT")
  self.frame = f
  self:SetGrowUp(db.growUp)
end

function CB:SetGrowUp(up)
  local f = self.frame
  if not f then return end
  f.growUp = up and true or false
  U.SavePos(f)
end

B:Every(0.1, function()
  if CB.frame then CB:Update() end
end)

B:On("OBG_INIT", function() CB:Build() end)

-- Key bindings (Bindings.xml)
function OctoBG_ToggleCDBars()
  B.db.cd.bars = not B.db.cd.bars
  B:Print("cooldown bars " .. (B.db.cd.bars and "on" or "off"))
end

function OctoBG_Options()
  if B.Options then B.Options:Toggle() end
end
