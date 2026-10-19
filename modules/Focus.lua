-- OctoBG :: focus
-- pfUI already has the focus frame (/focus, GUID based with SuperWoW) and its
-- castbar, so OctoBG uses that same focus and adds only what it lacks:
--   * cast on the focus WITHOUT switching target: /fcast Polymorph, or three
--     key bindings with spells per class. SuperWoW's CastSpellByName(spell,
--     unit) does it (pfUI's /pfcast uses the same call); pfUI's /castfocus
--     swaps your target back and forth instead.
--   * a strip under pfUI's focus frame: cooldowns they have used, diminishing
--     returns, distance, line of sight, immunity.
--   * right-click an enemy in the enemy list to focus them.
-- Without pfUI's focus frame OctoBG keeps its own focus, and the strip also
-- shows the name, health and the cast.

local B = OctoBG
local U = B.U
local FO = { cds = {}, drs = {} }
B.Focus = FO

B.DEFAULTS.focus = { strip = true, attach = true, spells = {} }   -- spells[CLASS] = { s1, s2, s3 }

FO.CLASS_SPELLS = {
  MAGE = { "Polymorph", "Counterspell", "Fire Blast" },
  PRIEST = { "Dispel Magic", "Silence", "Mana Burn" },
  WARLOCK = { "Fear", "Death Coil", "Curse of Tongues" },
  ROGUE = { "Blind", "Sap", "Kick" },
  HUNTER = { "Scatter Shot", "Viper Sting", "Tranquilizing Shot" },
  DRUID = { "Entangling Roots", "Hibernate", "Faerie Fire" },
  SHAMAN = { "Purge", "Earth Shock", "Frost Shock" },
  PALADIN = { "Hammer of Justice", "Repentance", "Judgement" },
  WARRIOR = { "Pummel", "Shield Bash", "Intercept" },
}

local function PF()
  return pfUI and pfUI.uf and pfUI.uf.focus
end

function FO:Spells()
  local _, class = UnitClass("player")
  class = class or "WARRIOR"
  local s = B.db.focus.spells[class]
  if not s then
    local d = self.CLASS_SPELLS[class] or { "", "", "" }
    s = { d[1], d[2], d[3] }
    B.db.focus.spells[class] = s
  end
  return s
end

-- The focus GUID and name: pfUI's focus when pfUI has one, else OctoBG's own.
function FO:Get()
  local f = PF()
  if f then
    if U.IsGuid(f.label) then
      -- remember the name while they are in range (pfUI's /focus sets only the GUID)
      local n = U.GuidExists(f.label) and UnitName(f.label)
      if n then self.guid, self.name = f.label, n end
      return f.label, (f.label == self.guid) and self.name or nil
    end
    if f.unitname then   -- pfUI without SuperWoW keeps a lowercased name
      for _, u in pairs(B.Tracker.units) do
        if u.name and string.lower(u.name) == f.unitname then return u.guid, u.name end
      end
      return nil, f.unitname
    end
    return nil
  end
  return self.guid, self.name
end

function FO:Set(guid, name)
  if not U.IsGuid(guid) then return end
  local f = PF()
  if f then
    if SUPERWOW_VERSION then
      -- the same fields pfUI's own GUID focus sets (pfUI\modules\superwow.lua)
      f.unitname, f.label, f.id = nil, guid, ""
      local ft = pfUI.uf.focustarget
      if ft then ft.unitname, ft.label, ft.id = nil, guid .. "target", "" end
    else
      f.unitname = name and string.lower(name)
    end
  end
  self.guid, self.name = guid, name
  UIErrorsFrame:AddMessage("Focus: " .. (name or "?"), 0.4, 0.8, 1)
end

-- Focus whoever a unit token ("target", "mouseover") points at. Works in
-- combat: 1.12 has no protected targeting, and this only writes pfUI's fields.
function FO:SetFromUnit(unit)
  if not UnitExists(unit) then return false end
  local g = U.GuidOf(unit)
  if not g then return false end
  self:Set(g, UnitName(unit))
  return true
end

function FO:SetFromTarget()
  if not self:SetFromUnit("target") then self:Clear() end
end

function FO:Clear()
  local f = PF()
  if f then
    f.unitname, f.label, f.id = nil, nil, nil
    local ft = pfUI.uf.focustarget
    if ft then ft.unitname, ft.label, ft.id = nil, nil, nil end
  end
  self.guid, self.name = nil, nil
end

-- Cast on the focus without touching your target (SuperWoW). Without
-- SuperWoW: target them, cast, and go back (pfUI's way).
function FO:Cast(spell)
  if not spell or spell == "" then return end
  local guid, name = self:Get()
  if not guid and not name then
    UIErrorsFrame:AddMessage("No focus - right-click an enemy in the enemy list, or use the Set focus key", 1, 0.3, 0.2)
    return
  end
  if B.env.superwow and guid then
    if not U.GuidExists(guid) then
      UIErrorsFrame:AddMessage((name or "Your focus") .. " is out of range", 1, 0.3, 0.2)
      return
    end
    CastSpellByName(spell, guid)
    return
  end
  local had = UnitExists("target")
  TargetByName(name, true)
  if UnitName("target") ~= name then
    if had then TargetLastTarget() end
    UIErrorsFrame:AddMessage((name or "Your focus") .. " is out of range", 1, 0.3, 0.2)
    return
  end
  CastSpellByName(spell)
  if had then TargetLastTarget() else ClearTarget() end
end

-- Key bindings (Bindings.xml) and /fcast
function OctoBG_FocusSet() FO:SetFromTarget() end
function OctoBG_FocusTarget()
  local g, n = FO:Get()
  if not U.TargetGuidOrName(g, n) then UIErrorsFrame:AddMessage("Focus is out of range", 1, 0.3, 0.2) end
end
function OctoBG_FocusSpell(i) FO:Cast(FO:Spells()[i]) end
-- Focus what is under the mouse (a character in the world or a unit frame)
-- without touching your target.
function OctoBG_FocusMouseover()
  if not FO:SetFromUnit("mouseover") then
    UIErrorsFrame:AddMessage("Nothing under the mouse to focus", 1, 0.3, 0.2)
  end
end
-- Your focus becomes your target and your target your focus (no focus yet:
-- your target becomes it).
function OctoBG_FocusSwap()
  local g, n = FO:Get()
  if not g and not n then
    FO:SetFromTarget()
    return
  end
  local tg, tn = U.GuidOf("target"), UnitExists("target") and UnitName("target")
  if not U.TargetGuidOrName(g, n) then
    UIErrorsFrame:AddMessage("Focus is out of range", 1, 0.3, 0.2)
    return
  end
  if tg and tn then FO:Set(tg, tn) end
end

SLASH_OCTOBGFCAST1 = "/fcast"
SlashCmdList["OCTOBGFCAST"] = function(msg)
  FO:Cast(string.gsub(msg or "", "^%s*(.-)%s*$", "%1"))
end

-- ---------------------------------------------------------------- strip

function FO:Build()
  local f = U.Panel("OctoBGFocus", "focus", "Focus extras", 180, 34, "CENTER", 220, -170)
  U.Backdrop(f, 0.75)
  f:Hide()
  f.name = U.Text(f, 10)
  f.name:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -3)
  f.name:SetJustifyH("LEFT")
  f.info = U.Text(f, 9, U.NARROW)
  f.info:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
  f.info:SetJustifyH("RIGHT")
  f.icons = {}
  for i = 1, 6 do
    local t = U.Tex(f, nil, "ARTWORK")
    t:SetWidth(14)
    t:SetHeight(14)
    t:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    t:Hide()
    f.icons[i] = t
  end
  f.dr = U.Text(f, 9, U.NARROW)
  f.dr:SetJustifyH("RIGHT")
  f.castbg = U.Tex(f, U.WHITE, "BORDER")
  f.castbg:SetVertexColor(0.1, 0.1, 0.1, 0.9)
  f.castbar = U.Tex(f, U.WHITE, "ARTWORK")
  f.cast = U.Text(f, 9, U.NARROW)
  self.frame = f
end

function FO:Update()
  local f = self.frame
  local db = B.db.focus
  local guid, name, class
  if B.test then
    guid, name, class = "sample1", "Testrogue", "ROGUE"
  else
    guid, name = self:Get()
    if U.IsGuid(guid) and UnitClass(guid) then
      local _, c = UnitClass(guid)
      class = c
    end
  end
  if not db.strip or not guid then
    if f:IsShown() then f:Hide() end
    return
  end
  local pf = PF()
  local own = not (pf and pf:IsShown())         -- no pfUI focus frame on screen: show it all
  local pfCast = pfUI and pfUI.castbar and pfUI.castbar.focus

  -- where: under pfUI's focus frame (and its castbar), else where you put it
  if db.attach and pf and not own and B.db.locked then
    local anchor = pfCast or pf
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -3)
    f:SetWidth(math.max(150, pf:GetWidth()))
    f.attached = true
  elseif f.attached then
    f.attached = nil
    U.RestorePos(f)
    f:SetWidth(180)
  end

  -- distance, sight or immunity
  local visible = U.GuidExists(guid) or B.test
  local info
  local left, imm = B.CD:ImmuneLeft(guid)
  if left then
    info = "|cffffd100" .. imm .. " " .. math.ceil(left) .. "s|r"
  elseif B.test then
    info = "28 yd  |cff55ff55in sight|r"
  elseif visible then
    local d, los = U.Distance(guid), U.InSight(guid)
    info = (d and (math.floor(d) .. " yd") or "")
      .. (los == true and "  |cff55ff55in sight|r" or (los == false and "  |cffff5555no sight|r" or ""))
  else
    -- a teammate running OctoBG sees them (Sync.lua)
    local u = B.Tracker.units[guid]
    if u and u.teamAt and GetTime() - u.teamAt < B.Tracker.TEAM_FRESH and u.dist then
      info = "|cff73bfff" .. math.floor(u.dist) .. " yd (team)|r"
    else
      info = "|cff888888out of range|r"
    end
  end
  f.info:SetText(info)

  -- diminishing returns as one line of text
  local nd = B.db.cd.showDR and B.CD:CollectDR(B.test and B.CD.SAMPLE or guid, self.drs) or 0
  local drText = ""
  for i = 1, nd do
    local e = self.drs[i]
    drText = drText .. U.Hex(e.r, e.g, e.b) .. e.label .. " " .. B.CD.FormatDR(e.multiplier) .. "|r  "
  end
  f.dr:SetText(drText)

  -- rows, top to bottom
  local y = -3
  f.info:ClearAllPoints()
  f.dr:ClearAllPoints()
  if own then
    -- no pfUI focus frame: name and health first
    local r, g, b = U.ClassColor(class)
    local hp = ""
    if visible and not B.test then
      local h, m = UnitHealth(guid), UnitHealthMax(guid)
      if h and m and m > 0 then hp = "  |cffffffff" .. math.floor(h / m * 100) .. "%|r" end
    end
    f.name:SetText(U.Hex(r, g, b) .. (name or "?") .. "|r" .. hp)
    f.name:Show()
    f.info:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, y - 1)
    y = y - 15
  else
    f.name:Hide()
    f.info:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, y - 1)
  end
  -- cooldowns they have used
  local n = B.CD:Important(guid, 6, self.cds)
  for i = 1, 6 do
    local t = f.icons[i]
    if i <= n and self.cds[i].tex then
      t:SetTexture(self.cds[i].tex)
      t:ClearAllPoints()
      t:SetPoint("TOPLEFT", f, "TOPLEFT", 4 + (i - 1) * 15, y)
      t:Show()
    else
      t:Hide()
    end
  end
  y = y - 16
  if drText ~= "" then
    f.dr:SetPoint("TOPLEFT", f, "TOPLEFT", 4, y)
    y = y - 13
  end
  -- the cast, unless pfUI's focus castbar already shows it
  local spell, _, prog, rem, chan = B.Casts:Get(B.test and "sample2" or guid)
  if spell and (own or not pfCast) then
    local w = f:GetWidth() - 8
    f.castbg:ClearAllPoints()
    f.castbg:SetPoint("TOPLEFT", f, "TOPLEFT", 4, y)
    f.castbg:SetWidth(w)
    f.castbg:SetHeight(11)
    f.castbar:ClearAllPoints()
    f.castbar:SetPoint("TOPLEFT", f, "TOPLEFT", 4, y)
    f.castbar:SetHeight(11)
    f.castbar:SetWidth(math.max(1, w * (chan and (1 - prog) or prog)))
    if chan then f.castbar:SetVertexColor(0.3, 0.6, 1, 0.9) else f.castbar:SetVertexColor(1, 0.75, 0.15, 0.9) end
    f.cast:ClearAllPoints()
    f.cast:SetPoint("LEFT", f.castbg, "LEFT", 3, 0)
    f.cast:SetText(spell .. "  " .. string.format("%.1f", rem))
    f.castbg:Show()
    f.castbar:Show()
    f.cast:Show()
    y = y - 14
  else
    f.castbg:Hide()
    f.castbar:Hide()
    f.cast:Hide()
  end
  f:SetHeight(-y + 2)
  if not f:IsShown() then f:Show() end
end

B:Every(0.1, function()
  if FO.frame then FO:Update() end
end)

B:On("OBG_INIT", function() FO:Build() end)
