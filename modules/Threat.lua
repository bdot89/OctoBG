-- OctoBG :: threat on your target's nameplate
-- A label by your target's nameplate (above, below, left, right - or a box you
-- place anywhere): words ("Threat 72%"), just the number, or a bar; "Aggro"
-- with how close the next player is once the mob is on you. Your own cap:
-- stay under N % of the top (or the 2nd, or the 3rd) player's threat - the
-- label goes yellow near it and red past it, and a popup with a sound can
-- shout once when you cross it or pull aggro. /obg threat 70 2 sets it fast.
--
-- The numbers come from the server, asked the way TWThreat 1.3.0 (installed
-- here) asks: SendAddonMessage("TWT_UDTSv4", "limit=N", "RAID" | "PARTY")
-- every 0.5 s while you are in a group and your target is a mob in combat.
-- The answer is CHAT_MSG_ADDON with arg2 "TWTv4=Name:tank:threat:perc:melee;..."
-- (a tank-mode tail after "#" is skipped). The server pulls a mob at 110 % of
-- the holder's threat in melee, 130 % at range (TWThreat's calcAGROPerc).
-- While TWThreat (or anyone) fed us an answer in the last 0.45 s, OctoBG
-- does not ask again.
--
-- Not verified on this server: with no answer after GIVE_UP requests OctoBG
-- stops asking until the next zone change, and the options page says so.
-- Plate colours by aggro are pfUI's (its nameplate combat state colours, on by
-- default), so they are not drawn here again.

local B = OctoBG
local U = B.U
local TH = { silent = 0, gaveUp = false, lastPacket = 0, answers = 0 }
B.Threat = TH

B.DEFAULTS.threat = {
  enabled = true,
  look = "words",          -- words | number | bar | none (popups only)
  where = "above",         -- above | below | left | right | screen (the "Threat" box, Move frames)
  x = 0, y = 2, size = 13, outline = "THICKOUTLINE",
  limit = 90,              -- your cap: % of the reference player's threat
  ref = 1,                 -- stay under the 1st (tank), 2nd or 3rd highest other player
  next = true,             -- with aggro: how close the next player is
  popup = true, popupText = "THREAT - back off!", popupSound = "RaidWarning",
  popupAggro = true,       -- also when you pull aggro (tanks may untick)
}

local GIVE_UP = 20
local FRESH = 2   -- seconds an answer is shown
local BAR_W, BAR_H = 70, 7

local floor = math.floor

TH.LOOKS = { { key = "words", label = "Words: Threat 72%" }, { key = "number", label = "Just the number: 72%" },
             { key = "bar", label = "A bar and the number" }, { key = "none", label = "Nothing on the plate (popups only)" } }
TH.PLACES = { { key = "above", label = "Above the nameplate" }, { key = "below", label = "Below the nameplate" },
              { key = "left", label = "Left of the nameplate" }, { key = "right", label = "Right of the nameplate" },
              { key = "screen", label = "A box I place (Move frames)" } }
TH.REFS = { { key = 1, label = "the top (the tank)" }, { key = 2, label = "the top two" },
            { key = 3, label = "the top three" } }

local function InGroup() return GetNumRaidMembers() > 0 or GetNumPartyMembers() > 0 end

-- In a group, the target a mob you can attack, in combat.
function TH:Wanted()
  if not B.db.threat.enabled or not InGroup() then return false end
  if not UnitExists("target") or UnitIsPlayer("target") or not UnitCanAttack("player", "target") then return false end
  return UnitAffectingCombat("target") and true or false
end

-- "TWTv4=Name:tank:threat:perc:melee;..." -> { { name, tank, threat, perc, melee }, ... } or nil
function TH.Parse(msg)
  if type(msg) ~= "string" then return nil end
  local _, e = string.find(msg, "TWTv4=", 1, true)
  if not e then return nil end
  local body = string.sub(msg, e + 1)
  local cut = string.find(body, "#", 1, true)
  if cut then body = string.sub(body, 1, cut - 1) end
  local out = {}
  for name, tank, threat, perc, melee in string.gfind(body, "([^:;]+):(%d+):(%-?%d+):([%-%d%.]+):(%d+)") do
    table.insert(out, { name = name, tank = (tank == "1"), threat = tonumber(threat) or 0,
                        perc = tonumber(perc) or 0, melee = (melee == "1") })
  end
  return out
end

local function ByThreat(a, b) return a.threat > b.threat end

-- What the label shows, from one answer and the current settings:
-- { aggro, share (% of the reference), nextP (with aggro), state 1 green / 2 yellow / 3 red }
function TH:Judge(list)
  local db = B.db.threat
  local me = UnitName("player")
  local mine
  local others = {}
  for i = 1, table.getn(list) do
    local p = list[i]
    if p.name == me then mine = p else table.insert(others, p) end
  end
  table.sort(others, ByThreat)
  local j = { aggro = mine and mine.tank }
  if j.aggro then
    local n = others[1]
    j.nextP = n and n.perc
    j.state = (j.nextP and j.nextP >= 90) and 2 or 1
    return j
  end
  local ref = others[math.min(db.ref or 1, table.getn(others))]
  local mineT = mine and mine.threat or 0
  if ref and ref.threat > 0 then j.share = mineT / ref.threat * 100 else j.share = 0 end
  local f = j.share / math.max(1, db.limit)
  j.state = (f >= 1) and 3 or ((f >= 0.8) and 2 or 1)
  return j
end

local COLOURS = { "|cff5aff5a", "|cffffd23a", "|cffff4a3a" }
local RGB = { { 0.35, 1, 0.35 }, { 1, 0.82, 0.23 }, { 1, 0.29, 0.23 } }

function TH:Text(j)
  local db = B.db.threat
  local c = COLOURS[j.state or 1]
  if j.aggro then
    local s = (db.look == "number") and "|cffff7a3aAGGRO|r" or "|cffff7a3aAggro|r"
    if db.next and j.nextP and db.look ~= "number" then s = s .. "  " .. c .. "next " .. floor(j.nextP + 0.5) .. "%|r" end
    return s
  end
  local pct = floor((j.share or 0) + 0.5) .. "%"
  if db.look == "words" then return c .. "Threat " .. pct .. "|r" end
  return c .. pct .. "|r"
end

-- ---------------------------------------------------------------- the label

local label = CreateFrame("Frame", "OctoBGThreat", UIParent)
label:SetWidth(160)
label:SetHeight(18)
label:SetFrameStrata("HIGH")
label:Hide()
label.text = label:CreateFontString(nil, "OVERLAY")
label.barBg = label:CreateTexture(nil, "BACKGROUND")
label.barBg:SetTexture(U.WHITE)
label.barBg:SetVertexColor(0, 0, 0, 0.6)
label.bar = label:CreateTexture(nil, "ARTWORK")
label.bar:SetTexture(U.WHITE)
TH.label = label

local POINTS = {   -- label point, plate point, x / y direction
  above = { "BOTTOM", "TOP" }, below = { "TOP", "BOTTOM" }, left = { "RIGHT", "LEFT" }, right = { "LEFT", "RIGHT" },
}

function TH:Place(plate)
  local db = B.db.threat
  label:ClearAllPoints()
  if db.where == "screen" then
    if not self.box then return false end
    label:SetPoint("CENTER", self.box, "CENTER", 0, 0)
    return true
  end
  if not plate then return false end
  local p = POINTS[db.where] or POINTS.above
  label:SetPoint(p[1], plate, p[2], db.x or 0, db.y or 0)
  return true
end

function TH:Paint(j)
  local db = B.db.threat
  label.text:SetFont(U.FONT, db.size, db.outline or "")
  label.text:ClearAllPoints()
  if db.look == "bar" and not j.aggro then
    local f = math.min(1, (j.share or 0) / math.max(1, db.limit))
    local c = RGB[j.state or 1]
    label.barBg:ClearAllPoints()
    label.barBg:SetPoint("LEFT", label, "LEFT", 4, 0)
    label.barBg:SetWidth(BAR_W)
    label.barBg:SetHeight(BAR_H)
    label.bar:ClearAllPoints()
    label.bar:SetPoint("LEFT", label.barBg, "LEFT", 0, 0)
    label.bar:SetWidth(math.max(1, BAR_W * f))
    label.bar:SetHeight(BAR_H)
    label.bar:SetVertexColor(c[1], c[2], c[3], 1)
    label.barBg:Show()
    label.bar:Show()
    label.text:SetPoint("LEFT", label.barBg, "RIGHT", 4, 0)
  else
    label.barBg:Hide()
    label.bar:Hide()
    label.text:SetPoint("CENTER", label, "CENTER", 0, 0)
  end
  label.text:SetText(self:Text(j))
end

-- Once per crossing: past your cap (again after dropping under 85 % of it),
-- or the mob turning to you.
function TH:Popups(j)
  local db = B.db.threat
  if not db.popup then return end
  if j.aggro then
    if db.popupAggro and not self.hadAggro then
      U.Alert("AGGRO!", 1, 0.45, 0.2)
      if B.SCT then B.SCT.PlaySound(db.popupSound) end
    end
    self.hadAggro = true
    return
  end
  self.hadAggro = nil
  if j.state == 3 and not self.warned then
    self.warned = true
    U.Alert(db.popupText or "THREAT", 1, 0.25, 0.2)
    if B.SCT then B.SCT.PlaySound(db.popupSound) end
  elseif self.warned and (j.share or 0) < db.limit * 0.85 then
    self.warned = nil
  end
end

function TH:Draw()
  local db = B.db.threat
  local j
  if self.sampleUntil and GetTime() < self.sampleUntil then
    j = { share = 72, state = 1 }
    if db.limit <= 72 then j.state = 3 elseif 72 >= db.limit * 0.8 then j.state = 2 end
  elseif self.data and GetTime() - self.data.at < FRESH and self:Wanted() then
    j = self:Judge(self.data.list)
  elseif B.test and db.where == "screen" then
    j = { share = 72, state = 1 }   -- Move frames: something to place
  else
    label:Hide()
    return
  end
  if db.look == "none" then
    label:Hide()
    return
  end
  local guid = U.GuidOf("target")
  local plate = guid and B.SCT and B.SCT:Plate(guid)
  if not self:Place(plate) then
    label:Hide()
    return
  end
  self:Paint(j)
  label:Show()
end

-- A sample on your target's plate (or the box) for a few seconds.
function TH:Sample(seconds)
  self.sampleUntil = GetTime() + (seconds or 8)
  self:Draw()
end

-- ---------------------------------------------------------------- asking and listening

function TH:Ask()
  if not self:Wanted() or self.gaveUp then return end
  if GetTime() - self.lastPacket < 0.45 then return end   -- TWThreat (or our last ask) just answered
  if pcall(SendAddonMessage, "TWT_UDTSv4", "limit=10", (GetNumRaidMembers() > 0) and "RAID" or "PARTY") then
    self.silent = self.silent + 1
    if self.silent >= GIVE_UP and self.answers == 0 then self.gaveUp = true end
  end
end

B:On("CHAT_MSG_ADDON", function(ev, prefix, msg)
  if not B.db.threat.enabled or type(msg) ~= "string" or not string.find(msg, "TWTv4=", 1, true) then return end
  local list = TH.Parse(msg)
  if not list then return end
  TH.lastPacket, TH.silent, TH.answers = GetTime(), 0, TH.answers + 1
  TH.data = { list = list, at = GetTime(), guid = U.GuidOf("target") }
  if TH:Wanted() then TH:Popups(TH:Judge(list)) end
  TH:Draw()
end)

B:On("PLAYER_TARGET_CHANGED", function()
  TH.data, TH.warned, TH.hadAggro = nil, nil, nil
  TH:Draw()
end)

B:On("OBG_ZONE", function()
  TH.data, TH.silent, TH.gaveUp = nil, 0, false
  label:Hide()
end)

-- the box for "A box I place": a panel like the others (Move frames, hover toolbar)
B:On("OBG_INIT", function()
  TH.box = U.Panel("OctoBGThreatBox", "threat", "Threat", 160, 22, "CENTER", 0, -120)
end)

B:Every(0.5, function() TH:Ask() end)
B:Every(0.1, function()
  if TH.data or label:IsShown() or TH.sampleUntil or B.test then TH:Draw() end
  if TH.sampleUntil and GetTime() >= TH.sampleUntil then TH.sampleUntil = nil end
end)

-- One line for the options page and /obg threat.
function TH:Status()
  if not B.db.threat.enabled then return "Off." end
  if self.data and GetTime() - self.data.at < FRESH then
    return "|cff5aff5aServer threat data coming in|r (" .. self.answers .. " answers)."
  end
  if self.gaveUp then
    return "|cffff7a3aThis server sent no threat data|r (asked " .. GIVE_UP .. " times) - OctoBG asks again after the next zone change."
  end
  if self.answers > 0 then
    return "The server answered " .. self.answers .. " times; waiting for the next fight."
  end
  if not InGroup() then return "Waiting: threat data needs a party or raid." end
  return "Waiting for a fight with a mob (asked " .. self.silent .. " times so far)."
end

-- The cap in words, for the options page and chat.
function TH:CapText()
  local db = B.db.threat
  local who = (db.ref == 2) and "the 2nd highest" or ((db.ref == 3) and "the 3rd highest" or "the top (tank)")
  return "stay under " .. db.limit .. "% of " .. who .. "'s threat"
end

-- /obg threat              status
-- /obg threat 70           cap 70 % of the top player
-- /obg threat 70 2         cap 70 % of the 2nd highest
B:Command("threat", "threat on your target's nameplate: status, or your cap: 70 [1-3]", function(rest)
  local _, _, n, r = string.find(rest or "", "^%s*(%d+)%s*(%d*)")
  if n then
    local db = B.db.threat
    db.limit = math.max(10, math.min(150, tonumber(n)))
    if r and r ~= "" then db.ref = math.max(1, math.min(3, tonumber(r))) end
    B:Print("threat cap: " .. TH:CapText())
    if B.Options then B.Options:Refresh() end
    return
  end
  B:Print("threat: " .. TH:Status() .. "  Cap: " .. TH:CapText() .. " (/obg threat 70 2 to change).")
end)
