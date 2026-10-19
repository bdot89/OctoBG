-- OctoBG :: cooldown icons on nameplates
-- From EnemyCooldowns: a row of the enemy's cooldown icons with countdowns on
-- every enemy nameplate, so you can watch everyone at once, not just your
-- target. A plate's GUID comes from nampower's frame:GetName(1); with pfUI
-- the icons attach to pfUI's plate so they get its scale and position.
--
-- For setting it up: a live preview on the options page (a sample enemy plate
-- redrawn every 0.1 s with the current settings), and a test that puts ticking
-- sample cooldowns on every nameplate you can see (also on in layout mode).

local B = OctoBG
local U = B.U
local CD = B.CD
local D = B.CDData
local NP = { candidates = {}, n = 0, known = 0, containers = {}, anchors = {}, testUntil = 0 }
B.CDPlates = NP

local pending = {}

-- sample cooldowns for the preview and the test: name, icon, cooldown
local SAMPLE = {
  { "Ice Block", "Interface\\Icons\\Spell_Frost_Frost", 300 },
  { "Insignia of the Horde", "Interface\\Icons\\INV_Jewelry_Trinketpvp_02", 120 },
  { "Vanish", "Interface\\Icons\\Ability_Vanish", 300 },
  { "Blink", "Interface\\Icons\\Spell_Arcane_Blink", 15 },
  { "Psychic Scream", "Interface\\Icons\\Spell_Shadow_PsychicScream", 30 },
  { "Kick", "Interface\\Icons\\Ability_Kick", 10 },
}

local function IsGUID(v)
  return type(v) == "string" and string.sub(v, 1, 2) == "0x"
end

function NP:Testing()
  return B.test or GetTime() < self.testUntil
end

function NP:Test(seconds)
  self.testUntil = (seconds and seconds > 0) and (GetTime() + seconds) or 0
  if seconds and seconds > 0 then
    B:Print("sample cooldowns on every visible nameplate for " .. seconds .. " s - V shows enemy plates, Shift-V friendly ones")
  end
end

-- pfUI keeps the original plate as the anchor and draws its own child; use it.
local function Anchor(plate)
  local cached = NP.anchors[plate]
  if cached and cached ~= plate then return cached end
  local kids = { plate:GetChildren() }
  for i = 1, table.getn(kids) do
    local k = kids[i]
    local name = k and k.GetName and k:GetName()
    if name and string.find(name, "^pfNamePlate") then
      NP.anchors[plate] = k
      return k
    end
  end
  NP.anchors[plate] = plate
  return plate
end

-- Nameplates are pooled and never destroyed in 1.12: only new children need indexing.
local function IndexNew()
  local total = WorldFrame:GetNumChildren()
  if total <= NP.known then return end
  local kids = { WorldFrame:GetChildren() }
  for i = NP.known + 1, total do
    if kids[i] then
      NP.n = NP.n + 1
      NP.candidates[NP.n] = kids[i]
    end
  end
  NP.known = total
end

local function Container(anchor)
  local c = CreateFrame("Frame", nil, anchor)
  c:SetFrameStrata("HIGH")
  c:SetWidth(1)
  c:SetHeight(1)
  c:EnableMouse(false)
  c.icons = {}
  c.bg = U.Tex(c, U.WHITE, "BACKGROUND")
  c.bg:Hide()
  c:Hide()
  NP.containers[anchor] = c
  return c
end

local function Icon(c, i)
  if c.icons[i] then return c.icons[i] end
  local icon = CreateFrame("Frame", nil, c)
  icon:EnableMouse(false)
  icon.border = U.Tex(icon, U.WHITE, "BACKGROUND")
  icon.tex = icon:CreateTexture(nil, "ARTWORK")
  icon.tex:SetAllPoints(icon)
  icon.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  icon.timer = U.Text(icon, 10)
  c.icons[i] = icon
  return icon
end

-- The point of the container that touches the plate: the side fixes one
-- component, the growth direction the other ("Centered row" leaves it blank).
local function Points()
  local db = B.db.cd
  local anchor, grow = db.nameplateAnchor, db.nameplateGrow
  local v, h = "", ""
  if anchor == "TOP" then v = "BOTTOM"
  elseif anchor == "BOTTOM" then v = "TOP"
  elseif anchor == "LEFT" then h = "RIGHT"
  else h = "LEFT" end
  if anchor == "TOP" or anchor == "BOTTOM" then
    if grow == "RIGHT" then h = "LEFT" elseif grow == "LEFT" then h = "RIGHT" end
  else
    if grow == "DOWN" then v = "TOP" elseif grow == "UP" then v = "BOTTOM" end
  end
  local p = v .. h
  if p == "" then p = "CENTER" end
  return p, anchor
end

local function Layout(c, count)
  local db = B.db.cd
  local size, gap, grow = db.nameplateIconSize, db.nameplateSpacing, db.nameplateGrow
  local vertical = (grow == "UP" or grow == "DOWN")
  local extent = count * size + (count - 1) * gap
  c:SetWidth(math.max(vertical and size or extent, 1))
  c:SetHeight(math.max(vertical and extent or size, 1))
  c:SetAlpha(db.nameplateAlpha)
  local selfPoint, platePoint = Points()
  c:ClearAllPoints()
  c:SetPoint(selfPoint, c:GetParent(), platePoint, db.nameplateXOffset, db.nameplateYOffset)
  if db.nameplateBackdrop then
    c.bg:SetVertexColor(CD.GetColor("nameplateBg"))
    c.bg:ClearAllPoints()
    c.bg:SetPoint("TOPLEFT", c, "TOPLEFT", -3, 3)
    c.bg:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", 3, -3)
    c.bg:Show()
  else
    c.bg:Hide()
  end
  local bs = db.nameplateBorder and db.nameplateBorderSize or 0
  local off = 0
  for i = 1, count do
    local icon = c.icons[i]
    icon:SetWidth(size)
    icon:SetHeight(size)
    icon:ClearAllPoints()
    if vertical then
      if grow == "UP" then icon:SetPoint("BOTTOM", c, "BOTTOM", 0, off)
      else icon:SetPoint("TOP", c, "TOP", 0, -off) end
    elseif grow == "LEFT" then
      icon:SetPoint("RIGHT", c, "RIGHT", -off, 0)
    else
      icon:SetPoint("LEFT", c, "LEFT", off, 0)
    end
    icon.border:ClearAllPoints()
    if bs > 0 then
      icon.border:SetPoint("TOPLEFT", icon, "TOPLEFT", -bs, bs)
      icon.border:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", bs, -bs)
      icon.border:Show()
    else
      icon.border:Hide()
    end
    icon.timer:ClearAllPoints()
    if db.nameplateShowTimer then
      local pos = db.nameplateTimerPos
      if pos == "CENTER" then icon.timer:SetPoint("CENTER", icon, "CENTER", 0, 0)
      elseif pos == "TOP" then icon.timer:SetPoint("BOTTOM", icon, "TOP", 0, 1)
      else icon.timer:SetPoint("TOP", icon, "BOTTOM", 0, -1) end
      icon.timer:Show()
    else
      icon.timer:Hide()
    end
    off = off + size + gap
  end
end

-- pending[1..n] = { tex, rem, name } from a real enemy's cooldowns
local function FillReal(guid)
  local db = B.db.cd
  local list = CD:GetActiveCooldowns(guid)
  local n = 0
  for i = 1, table.getn(list) do
    if n >= db.nameplateMaxIcons then break end
    local e = list[i]
    if not db.nameplateImportantOnly or D.ALERT_SPELLS[e.spellName] then
      n = n + 1
      if not pending[n] then pending[n] = {} end
      pending[n].tex, pending[n].rem, pending[n].name = e.texture, e.remaining, e.spellName
    end
  end
  return n
end

-- the same from the samples, ticking down and starting over
local function FillSamples()
  local db = B.db.cd
  local now = GetTime()
  local n = 0
  for i = 1, table.getn(SAMPLE) do
    if n >= db.nameplateMaxIcons then break end
    local s = SAMPLE[i]
    if not db.nameplateImportantOnly or D.ALERT_SPELLS[s[1]] then
      n = n + 1
      if not pending[n] then pending[n] = {} end
      pending[n].tex, pending[n].name = s[2], s[1]
      pending[n].rem = s[3] - math.mod(now + i * 7, s[3])
    end
  end
  return n
end

-- Draw pending[1..n] into container c.
local function Paint(c, n)
  local db = B.db.cd
  local br, bg, bb, ba = CD.GetColor("nameplateBorder")
  for i = 1, n do
    local p = pending[i]
    local icon = Icon(c, i)
    icon.tex:SetTexture(p.tex or "Interface\\Icons\\INV_Misc_QuestionMark")
    if db.nameplateBorderClass then
      local r, g, b = CD.SpellColor(p.name)
      icon.border:SetVertexColor(r, g, b, ba)
    else
      icon.border:SetVertexColor(br, bg, bb, ba)
    end
    if db.nameplateShowTimer then
      icon.timer:SetFont(U.FONT, db.nameplateTimerSize, "OUTLINE")
      icon.timer:SetText(CD.Time(p.rem))
      if p.rem < 5 then icon.timer:SetTextColor(1, 0.3, 0.3)
      elseif p.rem < 10 then icon.timer:SetTextColor(1, 0.8, 0.3)
      else icon.timer:SetTextColor(1, 1, 1) end
    end
    icon:Show()
  end
  local i = n + 1
  while c.icons[i] do
    c.icons[i]:Hide()
    i = i + 1
  end
  Layout(c, n)
  c:Show()
end

local function HideFor(plate)
  local a = NP.anchors[plate]
  local c = a and NP.containers[a]
  if c then c:Hide() end
end

local function UpdatePlate(plate, testing)
  if not plate:IsVisible() then
    HideFor(plate)
    return
  end
  local ok, guid = pcall(plate.GetName, plate, 1)
  if not ok or not IsGUID(guid) then   -- not a nameplate
    HideFor(plate)
    return
  end
  local n
  if testing then n = FillSamples() else n = FillReal(guid) end
  if n == 0 then
    HideFor(plate)
    return
  end
  local a = Anchor(plate)
  Paint(NP.containers[a] or Container(a), n)
end

function NP:HideAll()
  for _, c in pairs(self.containers) do
    if not c.preview then c:Hide() end
  end
end

local wasOn = false
B:Every(0.1, function()
  local testing = NP:Testing()
  local on = (B.db.cd.nameplates or testing) and not CD.standDown and B.env.nampower and B.env.safe
  if not on then
    if wasOn then NP:HideAll() end
    wasOn = false
    return
  end
  wasOn = true
  IndexNew()
  for i = 1, NP.n do UpdatePlate(NP.candidates[i], testing) end
end)

-- ---------------------------------------------------------------- options preview

-- A sample enemy nameplate inside an options box, redrawn while it is shown.
function NP:AttachPreview(box)
  local plate = CreateFrame("Frame", nil, box)
  plate:SetWidth(120)
  plate:SetHeight(24)
  plate:SetPoint("CENTER", box, "CENTER", 0, -6)
  local name = U.Text(plate, 10)
  name:SetPoint("TOP", plate, "TOP", 0, 0)
  name:SetText("Testmage")
  name:SetTextColor(1, 0.25, 0.2)
  local hb = U.Tex(plate, U.WHITE, "ARTWORK")
  hb:SetPoint("BOTTOMLEFT", plate, "BOTTOMLEFT", 2, 2)
  hb:SetWidth(84)
  hb:SetHeight(8)
  hb:SetVertexColor(0.85, 0.15, 0.1, 1)
  local hbg = U.Tex(plate, U.WHITE, "BORDER")
  hbg:SetPoint("BOTTOMLEFT", plate, "BOTTOMLEFT", 0, 0)
  hbg:SetWidth(120)
  hbg:SetHeight(12)
  hbg:SetVertexColor(0, 0, 0, 0.8)
  local c = Container(plate)
  c.preview = true
  c:SetFrameStrata(box:GetFrameStrata())
  c:SetFrameLevel(box:GetFrameLevel() + 5)
  box:SetScript("OnUpdate", function()
    this.t = (this.t or 0) + (arg1 or 0)
    if this.t < 0.1 then return end
    this.t = 0
    Paint(c, FillSamples())
  end)
  Paint(c, FillSamples())
end
