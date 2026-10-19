-- OctoBG :: incoming calls
-- A bar of buttons that post "3 INC STABLES" style calls to /bg.
--   top row     the bases of this map (AB: the five nodes; WSG: flag room,
--               midfield, their base; elsewhere: the nearest landmark).
--               The nearest base is picked automatically (AUTO, green);
--               click one to pin it (PICKED, gold), click it again to go
--               back to automatic. Ctrl-click a base: post its count.
--   bottom row  1 2 3 4 5+  Safe  Help  Auto (enemies at the base + running
--               to it: Tracker:CountIncoming)
--   top right   auto-post on / off
-- Calls: I:AtText "3 AT STABLES" (map clicks, Auto button), I:IncText "2 INC
-- STABLES" (the automatic caller, enemies running in). The enemy map posts
-- I:Post("at") for a base clicked on it.
-- Guard alert: while you stand at a base, enemies arriving there raise an
-- on-screen alert (only you see it). Posting those automatically is off by
-- default and asks first (house rule for anything posting to a shared channel).

local B = OctoBG
local U = B.U
local M = B.Map
local I = { bases = {}, baseButtons = {}, countButtons = {} }
B.Incoming = I

local BTN_H = 20
local AB_BASES = { { "Stables", "ST" }, { "Gold Mine", "GM" }, { "Blacksmith", "BS" }, { "Lumber Mill", "LM" }, { "Farm", "FM" } }
local MAX_BASES = 5

-- ---------------------------------------------------------------- bases

function I:Rebuild()
  local list = {}
  if B.zone == "AB" then
    for i = 1, table.getn(AB_BASES) do
      local m = M:FindLandmark(AB_BASES[i][1])
      table.insert(list, { name = AB_BASES[i][1], short = AB_BASES[i][2], x = m and m.wx, y = m and m.wy })
    end
  elseif B.zone == "WSG" and B.faction then
    local mine, theirs = M.WSG[B.faction].flag, M.WSG[B.enemy].flag
    table.insert(list, { name = "Flag room", short = "FR", x = mine[1], y = mine[2] })
    table.insert(list, { name = "Midfield", short = "MID", x = (mine[1] + theirs[1]) / 2, y = (mine[2] + theirs[2]) / 2 })
    table.insert(list, { name = "Their base", short = "EB", x = theirs[1], y = theirs[2] })
  else
    local px, py = M:PlayerWorld()
    local m = px and M:NearestLandmark(px, py)
    if m then table.insert(list, { name = m.name, short = m.name, x = m.wx, y = m.wy, wide = true }) end
  end
  if B.test and table.getn(list) == 0 then
    for i = 1, table.getn(AB_BASES) do
      table.insert(list, { name = AB_BASES[i][1], short = AB_BASES[i][2] })
    end
  end
  self.bases = list
end

-- The pinned base, else the nearest one.
function I:Selected()
  local list = self.bases
  if self.pinned then
    for i = 1, table.getn(list) do
      if list[i].name == self.pinned then return list[i] end
    end
    self.pinned = nil
  end
  local px, py = M:PlayerWorld()
  local best, bestD = list[1], nil
  if px then
    for i = 1, table.getn(list) do
      local b = list[i]
      if b.x then
        local d = M.Dist(px, py, b.x, b.y)
        if not bestD or d < bestD then best, bestD = b, d end
      end
    end
  end
  return best, bestD
end

-- Enemies at a base and on their way to it: by position when SuperWoW gives
-- one (Tracker:CountIncoming - teammates' sightings count too), else (when
-- the player stands there) by UnitXP distance around the player.
-- Returns at, coming.
function I:Counts(base)
  if not base then return 0, 0 end
  if B.test then return 2, 1 end
  local r = B.db.inc.radius
  local at, coming = 0, 0
  if base.x then at, coming = B.Tracker:CountIncoming(base.x, base.y, r, 3) end
  if at == 0 and not B.env.position then
    local px, py = M:PlayerWorld()
    if px and base.x and M.Dist(px, py, base.x, base.y) <= r then
      at = B.Tracker:CountAroundPlayer(r)
    end
  end
  return at, coming
end

-- Everyone at or coming to a base.
function I:Count(base)
  local at, coming = self:Counts(base)
  return at + coming
end

-- What is at a base right now (a click on the map or the bar's Auto button;
-- user: "it should say 3 AT Stables not Inc"):
--   "3 AT STABLES" / "3 AT STABLES + 2 INC" / "2 INC STABLES" / "STABLES - no enemies seen"
function I:AtText(base)
  local at, coming = self:Counts(base)
  local name = string.upper(base.name)
  local msg
  if at > 0 then
    msg = at .. " AT " .. name .. ((coming > 0) and (" + " .. coming .. " INC") or "")
  elseif coming > 0 then
    msg = coming .. " INC " .. name
  else
    msg = name .. " - no enemies seen"
  end
  return msg, at, coming
end

-- The automatic caller's INC call, for enemies running to the base:
--   "2 INC STABLES" / "2 INC STABLES (3 already there)"
function I:IncText(base)
  local at, coming = self:Counts(base)
  local msg = coming .. " INC " .. string.upper(base.name)
  if at > 0 then msg = msg .. " (" .. at .. " already there)" end
  return msg, at, coming
end

-- The base nearest a world point (within maxD yards), for clicks on the map.
function I:BaseAt(x, y, maxD)
  local best, bestD
  for i = 1, table.getn(self.bases) do
    local b = self.bases[i]
    if b.x then
      local d = M.Dist(x, y, b.x, b.y)
      if d <= maxD and (not bestD or d < bestD) then best, bestD = b, d end
    end
  end
  return best
end

-- ---------------------------------------------------------------- posting

function I:Post(kind, n, base)
  base = base or self:Selected()
  if not base then
    B:Print("no base to call here")
    return
  end
  local name = string.upper(base.name)
  local msg
  if kind == "safe" then
    msg = name .. " SAFE"
  elseif kind == "help" then
    local c = self:Count(base)
    msg = "HELP " .. name .. (c > 0 and (" - " .. c .. " enemies") or "")
  elseif kind == "auto" or kind == "at" then
    msg = self:AtText(base)
  else
    msg = tostring(n) .. " INC " .. name
  end
  U.SendBG(msg)
end

-- Key bindings (Bindings.xml)
function OctoBG_Inc(n)
  if n == "auto" then I:Post("auto") else I:Post("count", n) end
end
function OctoBG_Safe() I:Post("safe") end

-- ---------------------------------------------------------------- guard alert

local lastCount, lastAlert, lastAuto = 0, 0, 0

function I:Guard()
  if not B.db.inc.alert or not B:IsBG() then return end
  local base, d = self:Selected()
  if not base or not base.x or not d or d > 80 then
    lastCount = 0
    return
  end
  local at, coming = self:Counts(base)
  local c = at + coming
  local now = GetTime()
  if c > lastCount and c > 0 then
    if now - lastAlert > 6 or c >= lastCount + 2 then
      lastAlert = now
      local what
      if at > 0 and coming > 0 then
        what = at .. " at " .. base.name .. ", " .. coming .. " on the way!"
      elseif at > 0 then
        what = at .. (at == 1 and " enemy" or " enemies") .. " at " .. base.name .. "!"
      else
        what = coming .. (coming == 1 and " enemy" or " enemies") .. " running to " .. base.name .. "!"
      end
      U.Alert(what, 1, 0.25, 0.2, true)
      -- the automatic caller calls INC: only for enemies running in
      if B.db.inc.autoPost and coming > 0 and c >= 2 and now - lastAuto > 20 then
        lastAuto = now
        U.SendBG((self:IncText(base)))
      end
    end
  end
  lastCount = c
end

-- ---------------------------------------------------------------- UI

local function Button(parent, w, text)
  local b = CreateFrame("Button", nil, parent)
  b:SetWidth(w)
  b:SetHeight(BTN_H)
  U.Backdrop(b, 0.9)
  b:SetBackdropColor(0.12, 0.12, 0.14, 0.95)
  b.text = U.Text(b, 10)
  b.text:SetPoint("CENTER", b, "CENTER", 0, 0)
  b.text:SetText(text)
  b:SetScript("OnEnter", function() this:SetBackdropColor(0.25, 0.25, 0.3, 0.95) end)
  b:SetScript("OnLeave", function() this:SetBackdropColor(0.12, 0.12, 0.14, 0.95) end)
  return b
end

function I:Build()
  local w = 8 * 33 + 6
  local f = U.Panel("OctoBGInc", "inc", "INC calls", w, 2 * BTN_H + 22, "BOTTOM", 0, 170)
  U.Backdrop(f, 0.7)
  f:Hide()
  self.frame = f

  f.info = U.Text(f, 10, U.NARROW)
  f.info:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -3)
  f.info:SetJustifyH("LEFT")
  -- auto-post on / off, top right: click to switch (switching on asks first)
  f.post = CreateFrame("Button", nil, f)
  f.post:SetHeight(13)
  f.post:SetWidth(70)
  f.post:SetPoint("TOPRIGHT", f, "TOPRIGHT", -3, -1)
  f.post.text = U.Text(f.post, 9, U.NARROW)
  f.post.text:SetPoint("RIGHT", f.post, "RIGHT", 0, 0)
  f.post.text:SetJustifyH("RIGHT")
  f.post:SetScript("OnClick", function()
    if B.db.inc.autoPost then
      B.db.inc.autoPost = false
    else
      StaticPopup_Show("OCTOBG_AUTOPOST")
    end
    I:Paint()
  end)
  f.post:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_TOP")
    GameTooltip:AddLine("Auto-post")
    GameTooltip:AddLine("On: when enemies run at the base you are guarding, the call is posted to battleground chat "
      .. "for you (2+ enemies, at most every 20 s). Off: you only get the warning on your screen. Click to switch.", 1, 1, 1, 1)
    GameTooltip:Show()
  end)
  f.post:SetScript("OnLeave", function() GameTooltip:Hide() end)

  local bw = (w - 6) / MAX_BASES
  for i = 1, MAX_BASES do
    local b = Button(f, bw - 2, "")
    b:SetPoint("TOPLEFT", f, "TOPLEFT", 3 + (i - 1) * bw, -16)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", function()
      local base = I.bases[this.index]
      if not base then return end
      if IsControlKeyDown() then
        I:Post("auto", nil, base)
      elseif I.pinned == base.name then
        I.pinned = nil
      else
        I.pinned = base.name
      end
      I:Paint()
    end)
    b.index = i
    b:SetScript("OnEnter", function()
      this:SetBackdropColor(0.25, 0.25, 0.3, 0.95)
      local base = I.bases[this.index]
      if not base then return end
      local at, coming = I:Counts(base)
      GameTooltip:SetOwner(this, "ANCHOR_TOP")
      GameTooltip:AddLine(base.name)
      GameTooltip:AddLine(at .. " enemies there, " .. coming .. " running to it", 1, 1, 1)
      GameTooltip:AddLine("Click: pick this base (it stays picked until you click it again).", 0.8, 0.8, 0.8, 1)
      GameTooltip:AddLine("Ctrl-click: post its count to battleground chat.", 0.8, 0.8, 0.8, 1)
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function()
      this:SetBackdropColor(0.12, 0.12, 0.14, 0.95)
      GameTooltip:Hide()
    end)
    self.baseButtons[i] = b
  end

  local labels = { "1", "2", "3", "4", "5+", "Safe", "Help", "Auto" }
  for i = 1, 8 do
    local b = Button(f, 31, labels[i])
    b:SetPoint("TOPLEFT", f, "TOPLEFT", 3 + (i - 1) * 33, -16 - BTN_H - 2)
    b.label = labels[i]
    b:SetScript("OnClick", function()
      local l = this.label
      if l == "Safe" then I:Post("safe")
      elseif l == "Help" then I:Post("help")
      elseif l == "Auto" then I:Post("auto")
      else I:Post("count", l) end
    end)
    self.countButtons[i] = b
  end
  local auto = self.countButtons[8]
  auto:SetScript("OnEnter", function()
    this:SetBackdropColor(0.25, 0.25, 0.3, 0.95)
    GameTooltip:SetOwner(this, "ANCHOR_TOP")
    GameTooltip:AddLine("Post the enemies counted at the base")
    GameTooltip:AddLine("Counts enemies within " .. B.db.inc.radius .. " yd of the base, plus those running towards it "
      .. "from further out - from what you and teammates with OctoBG can see. Posts e.g. \"3 AT STABLES + 2 INC\".", 1, 1, 1, 1)
    GameTooltip:Show()
  end)
  auto:SetScript("OnLeave", function()
    this:SetBackdropColor(0.12, 0.12, 0.14, 0.95)
    GameTooltip:Hide()
  end)
end

function I:Paint()
  local f = self.frame
  if not f then return end
  local show = B.db.inc.enabled and (B:IsBG() or B.test)
  if not show then
    if f:IsShown() then f:Hide() end
    return
  end
  if not f:IsShown() then f:Show() end
  self:Rebuild()
  local sel = self:Selected()
  local list = self.bases
  local n = table.getn(list)
  local w = f:GetWidth() - 6
  for i = 1, MAX_BASES do
    local b = self.baseButtons[i]
    local base = list[i]
    if base then
      if n == 1 then
        b:SetWidth(w - 2)
      else
        b:SetWidth(w / MAX_BASES - 2)
      end
      b.text:SetText(base.short)
      if sel and base.name == sel.name and self.pinned then
        -- picked by you: gold
        b:SetBackdropBorderColor(1, 0.82, 0, 1)
        b.text:SetTextColor(1, 0.82, 0)
      elseif sel and base.name == sel.name then
        -- picked automatically (nearest): green
        b:SetBackdropBorderColor(0.3, 0.9, 0.4, 1)
        b.text:SetTextColor(0.45, 1, 0.55)
      else
        b:SetBackdropBorderColor(0.22, 0.22, 0.25, 1)
        b.text:SetTextColor(0.85, 0.85, 0.85)
      end
      b:Show()
    else
      b:Hide()
    end
  end
  local at, coming = self:Counts(sel)
  local c = at + coming
  self.countButtons[8].text:SetText(c > 0 and ("Auto " .. c) or "Auto")
  if sel then
    local mode = self.pinned and "|cffffd100PICKED|r " or "|cff55ff55AUTO|r "
    local counts = at .. " there" .. ((coming > 0) and (", " .. coming .. " coming") or "")
    f.info:SetText(mode .. sel.name .. "  |cffaaaaaa" .. counts .. "|r")
  else
    f.info:SetText("|cffaaaaaano base nearby|r")
  end
  f.post.text:SetText(B.db.inc.autoPost and "auto-post |cff55ff55ON|r" or "|cff888888auto-post off|r")
end

B:Every(0.5, function()
  I:Paint()
  I:Guard()
end, true)

B:On("OBG_INIT", function() I:Build() end)
B:On("OBG_ZONE", function()
  I.pinned = nil
  lastCount = 0
  I:Paint()
end)
B:On("OBG_LAYOUT", function() I:Paint() end)
