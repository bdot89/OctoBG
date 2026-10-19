-- OctoBG :: statistics window (Spy's statistics, rebuilt)
-- Every enemy player in Spy's database: level, class, guild, wins, losses,
-- Kill On Sight reasons, where and when you last saw them. Filter by name
-- or guild, or to Kill On Sight / won-lost / with-reason players; click a
-- column to sort (again to reverse). Rows: click = target, Shift-click =
-- Kill On Sight, right-click = the enemy menu, hover = everything known.
-- Built the first time it opens; it refreshes every second while shown.

local B = OctoBG
local U = B.U
local S = { rows = {}, list = {}, sortBy = "time", desc = true, offset = 0 }
B.Stats = S

local ROWS, ROW_H, WIDTH, HEIGHT = 18, 18, 724, 486

-- key, header, width, justify
local COLS = {
  { "kos", "", 18 }, { "name", "Name", 104 }, { "level", "Lvl", 30 }, { "class", "Class", 58 },
  { "guild", "Guild", 104 }, { "wins", "Won", 34 }, { "loses", "Lost", 34 }, { "reason", "Reason", 112 },
  { "zone", "Last seen at", 128 }, { "time", "When", 44 },
}

local function Num(v) return tonumber(v) or 0 end

local function Less(a, b, key)
  if key == "name" or key == "class" or key == "guild" or key == "zone" or key == "reason" then
    local x, y = string.lower(a[key] or "~"), string.lower(b[key] or "~")
    if x ~= y then return x < y, true end
  else
    local x, y = Num(a[key]), Num(b[key])
    if x ~= y then return x < y, true end
  end
  return false, false
end

function S:Collect()
  local P = B.People
  local store = P:Store()
  local filter = string.lower(self.box and self.box:GetText() or "")
  local onlyKos, onlyWL, onlyReason = self.cbKos:GetChecked(), self.cbWL:GetChecked(), self.cbReason:GetChecked()
  local list, n = self.list, 0
  for name, r in pairs(store.players) do
    if type(r) == "table" then
      local guild = r.guild or ""
      local ok = filter == "" or string.find(string.lower(name), filter, 1, true) == 1
        or (guild ~= "" and string.find(string.lower(guild), filter, 1, true) == 1)
      local kos = P:IsKOS(name)
      if ok and onlyKos and not kos then ok = false end
      if ok and onlyWL and Num(r.wins) == 0 and Num(r.loses) == 0 then ok = false end
      local reason = P:ReasonText(name)
      if ok and onlyReason and not reason then ok = false end
      if ok then
        n = n + 1
        local e = list[n]
        if not e then
          e = {}
          list[n] = e
        end
        e.name, e.level, e.class, e.guild, e.wins, e.loses = name, r.level, r.class, r.guild, r.wins, r.loses
        e.reason, e.zone, e.time, e.kos = reason, P:Location(r), r.time or 0, kos and 1 or 0
      end
    end
  end
  for i = table.getn(list), n + 1, -1 do list[i] = nil end
  local key, desc = self.sortBy, self.desc
  table.sort(list, function(a, b)
    local r, decided = Less(a, b, key)
    if decided then
      if desc then return not r end
      return r
    end
    return a.name < b.name
  end)
  return n
end

-- Collecting walks the whole database: only when something changed (S.dirty),
-- and every 10 s for new sightings; the rows repaint every second.
function S:Paint()
  if not self.frame or not self.frame:IsShown() then return end
  if self.dirty or not self.n then
    self.n = self:Collect()
    self.dirty = nil
  end
  local n = self.n
  local max = math.max(0, n - ROWS)
  if self.offset > max then self.offset = max end
  local P = B.People
  for i = 1, ROWS do
    local row = self.rows[i]
    local e = self.list[i + self.offset]
    if e then
      row.entry = e
      local fresh = time() - e.time < 60
      local cr, cg, cb = U.ClassColor(e.class)
      local c = row.cells
      if e.kos == 1 then c.kos:SetText("|cffff3333KoS|r") else c.kos:SetText("") end
      c.name:SetText(e.name)
      c.name:SetTextColor(cr, cg, cb)
      c.level:SetText(e.level and ((e.level == 0) and "??" or tostring(e.level)) or "?")
      c.class:SetText(e.class and (P.CLASS_NAME[e.class] or e.class) or "?")
      c.class:SetTextColor(cr, cg, cb)
      c.guild:SetText(e.guild or "")
      c.wins:SetText(tostring(e.wins or 0))
      c.loses:SetText(tostring(e.loses or 0))
      c.reason:SetText(e.reason or "")
      c.zone:SetText(e.zone or "?")
      c.time:SetText(P.Ago(e.time))
      if fresh then c.time:SetTextColor(0.4, 1, 0.4) else c.time:SetTextColor(0.8, 0.8, 0.8) end
      row:Show()
    else
      row.entry = nil
      row:Hide()
    end
  end
  self.slider.loading = true
  self.slider:SetMinMaxValues(0, max)
  self.slider:SetValue(self.offset)
  self.slider.loading = nil
  if max > 0 then self.slider:Show() else self.slider:Hide() end
  local kos = 0
  for _ in pairs(P:KOSList()) do kos = kos + 1 end
  local total = 0
  for _ in pairs(P:Store().players) do total = total + 1 end
  self.info:SetText(n .. " shown of " .. total .. " players   |cffff5555" .. kos .. " Kill On Sight|r   |cff888888"
    .. (P:Realm()) .. " - " .. (UnitFactionGroup("player") or "?") .. "|r")
  for i = 1, table.getn(self.heads) do
    local h = self.heads[i]
    if h.key == self.sortBy then
      h.text:SetTextColor(1, 0.82, 0)
      h.text:SetText(h.label .. (self.desc and " v" or " ^"))
    else
      h.text:SetTextColor(0.8, 0.8, 0.8)
      h.text:SetText(h.label)
    end
  end
end

local function Check(parent, label, x)
  local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  cb:SetWidth(22)
  cb:SetHeight(22)
  cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -46)
  local t = B.W.Font(parent:CreateFontString(nil, "OVERLAY"), 11, 1, 1, 1)
  t:SetPoint("LEFT", cb, "RIGHT", 1, 0)
  t:SetText(label)
  cb:SetScript("OnClick", function()
    S.offset = 0
    S.dirty = true
    S:Paint()
  end)
  return cb
end

function S:Build()
  local f = CreateFrame("Frame", "OctoBGStats", UIParent)
  f:SetWidth(WIDTH)
  f:SetHeight(HEIGHT)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 30)
  f:SetFrameStrata("DIALOG")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:EnableMouseWheel(true)
  f:SetClampedToScreen(true)
  B.W.Skin(f, "window")
  f:Hide()
  table.insert(UISpecialFrames, "OctoBGStats")
  self.frame = f
  f:SetScript("OnMouseDown", function() if arg1 == "LeftButton" then this:StartMoving() end end)
  f:SetScript("OnMouseUp", function() this:StopMovingOrSizing() end)
  f:SetScript("OnMouseWheel", function()
    S.offset = math.max(0, S.offset - arg1 * 3)
    S:Paint()
  end)
  f:SetScript("OnUpdate", function()
    this.t = (this.t or 0) + arg1
    this.t10 = (this.t10 or 0) + arg1
    if this.t > 1 then
      this.t = 0
      if this.t10 > 10 then
        this.t10 = 0
        S.dirty = true
      end
      S:Paint()
    end
  end)

  B.W.Header(f, "Enemy statistics", 260)
  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -5, -5)

  local lab = B.W.Font(f:CreateFontString(nil, "OVERLAY"), 12, 1, 1, 1)
  lab:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -52)
  lab:SetText("Find:")
  local box = CreateFrame("EditBox", "OctoBGStatsFind", f, "InputBoxTemplate")
  box:SetWidth(150)
  box:SetHeight(18)
  box:SetPoint("LEFT", lab, "RIGHT", 10, 0)
  box:SetAutoFocus(false)
  box:SetScript("OnTextChanged", function()
    S.offset = 0
    S.dirty = true
    S:Paint()
  end)
  box:SetScript("OnEscapePressed", function()
    this:SetText("")
    this:ClearFocus()
  end)
  box:SetScript("OnEnterPressed", function() this:ClearFocus() end)
  self.box = box
  self.cbKos = Check(f, "Kill On Sight", 240)
  self.cbWL = Check(f, "Won / lost", 350)
  self.cbReason = Check(f, "With a reason", 450)

  -- column headers
  self.heads = {}
  local x = 18
  for i = 1, table.getn(COLS) do
    local c = COLS[i]
    local h = CreateFrame("Button", nil, f)
    h:SetWidth(c[3])
    h:SetHeight(16)
    h:SetPoint("TOPLEFT", f, "TOPLEFT", x, -78)
    h.key, h.label = c[1], c[2]
    h.text = B.W.Font(h:CreateFontString(nil, "OVERLAY"), 11, 1, 0.82, 0)
    h.text:SetPoint("LEFT", h, "LEFT", 2, 0)
    h.text:SetText(c[2])
    local hl = h:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(h)
    hl:SetTexture(U.WHITE)
    hl:SetVertexColor(1, 1, 1, 0.08)
    h:SetScript("OnClick", function()
      if S.sortBy == this.key then
        S.desc = not S.desc
      else
        S.sortBy = this.key
        S.desc = (this.key == "time" or this.key == "wins" or this.key == "loses" or this.key == "level" or this.key == "kos")
      end
      S.dirty = true
      S:Paint()
    end)
    table.insert(self.heads, h)
    x = x + c[3]
  end
  local line = U.Tex(f, U.WHITE, "ARTWORK")
  line:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -95)
  line:SetWidth(WIDTH - 60)
  line:SetHeight(1)
  line:SetVertexColor(1, 0.82, 0, 0.35)

  for i = 1, ROWS do
    local row = CreateFrame("Button", nil, f)
    row:SetWidth(WIDTH - 60)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -98 - (i - 1) * ROW_H)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(row)
    hl:SetTexture(U.WHITE)
    hl:SetVertexColor(0.3, 0.5, 0.8, 0.25)
    if math.mod(i, 2) == 0 then
      local zebra = U.Tex(row, U.WHITE, "BACKGROUND")
      zebra:SetAllPoints(row)
      zebra:SetVertexColor(1, 1, 1, 0.03)
    end
    row.cells = {}
    local cx = 0
    for j = 1, table.getn(COLS) do
      local c = COLS[j]
      local fs = U.Text(row, 10, U.NARROW)
      fs:SetPoint("LEFT", row, "LEFT", cx + 2, 0)
      fs:SetWidth(c[3] - 4)
      fs:SetHeight(ROW_H)
      fs:SetJustifyH("LEFT")
      row.cells[c[1]] = fs
      cx = cx + c[3]
    end
    row:SetScript("OnClick", function()
      local e = this.entry
      if not e then return end
      if arg1 == "RightButton" then
        B.Roster:Menu(e.name, B.Tracker:FindByName(e.name))
      elseif IsShiftKeyDown() then
        B.People:ToggleKOS(e.name)
        S.dirty = true
        S:Paint()
      else
        B.Roster:Target(e.name, B.Tracker:FindByName(e.name))
      end
    end)
    row:SetScript("OnEnter", function()
      local e = this.entry
      if not e then return end
      B.Roster:Tooltip(e.name, B.Tracker:FindByName(e.name), this, "ANCHOR_RIGHT")
      GameTooltip:AddLine("Click: target  Shift-click: Kill On Sight  Right-click: menu", 0.4, 0.8, 0.4)
      GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:Hide()
    self.rows[i] = row
  end

  local slider = CreateFrame("Slider", "OctoBGStatsSlider", f, "OptionsSliderTemplate")
  slider:SetOrientation("VERTICAL")
  slider:SetWidth(16)
  slider:SetHeight(ROWS * ROW_H)
  slider:SetPoint("TOPRIGHT", f, "TOPRIGHT", -18, -98)
  slider:SetValueStep(1)
  local lo, hi, tx = getglobal("OctoBGStatsSliderLow"), getglobal("OctoBGStatsSliderHigh"), getglobal("OctoBGStatsSliderText")
  if lo then lo:SetText("") end
  if hi then hi:SetText("") end
  if tx then tx:SetText("") end
  slider:SetScript("OnValueChanged", function()
    if this.loading then return end
    S.offset = math.floor(this:GetValue() + 0.5)
    S:Paint()
  end)
  self.slider = slider

  self.info = U.Text(f, 10, U.NARROW)
  self.info:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 22, 20)
  local purge = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  purge:SetWidth(120)
  purge:SetHeight(20)
  purge:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -18, 16)
  purge:SetText("Purge old now")
  purge:SetScript("OnClick", function()
    B.People:Purge()
    S.dirty = true
    S:Paint()
  end)
  purge:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_TOP")
    GameTooltip:AddLine("Purge old now")
    GameTooltip:AddLine("Removes players not seen for the time set under World PvP data (as on every login).", 1, 1, 1, 1)
    GameTooltip:Show()
  end)
  purge:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function S:Show()
  if not self.frame then self:Build() end
  self.frame:Show()
  self.dirty = true
  self:Paint()
end

function S:Toggle()
  if self.frame and self.frame:IsShown() then self.frame:Hide() else self:Show() end
end

B:On("OBG_PEOPLE", function()
  S.dirty = true
  if S.frame and S.frame:IsShown() then S:Paint() end
end)

function OctoBG_ToggleStats() S:Toggle() end
