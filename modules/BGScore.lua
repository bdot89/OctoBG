-- OctoBG :: the battleground score panel
-- One framed panel with everything about the game in progress, in the game's
-- own art: the battleground's name on a plaque over its map,
-- the time, and the score.
--   * Warsong Gulch (any game scored to a few points): big flag scores with
--     who carries each flag
--   * Arathi Basin: both sides' resources as bars, their bases, who wins and
--     exactly when (Timers.lua TM:Predict, counted down every frame), and a
--     row of the five bases with their capture timers
--   * Alterac Valley and others: the sides' numbers as bars, other lines as text
-- Scores change the moment the server says so (UPDATE_WORLD_STATES); bars glide
-- to the new value. Everything is a setting (db.bgscore): frame, colour, picture,
-- how dark it is, what shows; size and place with Move frames. Clicking the
-- prediction or a base says it in /bg, as the Timers panel's rows do.

local B = OctoBG
local U = B.U
local M = B.Map
local W = B.W
local S = { bars = {}, big = {}, nodes = {} }
B.BGScore = S

B.DEFAULTS.bgscore = { enabled = true, border = "gold", borderColor = { 0.5, 0.5, 0.55 }, art = "zone", dark = 0.55,
                       plaque = true, time = true, predict = true, nodes = true, carriers = true, graveyard = true,
                       width = 300 }

S.ARTS = { { key = "zone", label = "The battleground's map" }, { key = "stone", label = "Dark stone" },
           { key = "plain", label = "Plain dark" } }

-- The picture behind panels: the battleground's own world map (12 tiles of 256 px
-- making 1002 x 668, as TacMap draws them). Scaled to cover the area, never
-- stretched, the overhang cropped with texcoords (1.12 doesn't clip textures).
-- The loading screens were tried first: posters with a logo and characters.
local MAP_W, MAP_H = 1002, 668
function S.MapArt(parent, layer)
  local a = { tiles = {} }
  for i = 1, 12 do a.tiles[i] = U.Tex(parent, nil, layer or "BACKGROUND") end
  function a:Set(file)
    if file ~= self.file then
      self.file, self.fw = file, nil
      for i = 1, 12 do
        if file then self.tiles[i]:SetTexture("Interface\\WorldMap\\" .. file .. "\\" .. file .. i) end
      end
    end
    if not file then self:Hide() end
  end
  function a:Hide()
    self.fw = nil
    for i = 1, 12 do self.tiles[i]:Hide() end
  end
  -- Covers a w x h area from parent's top left.
  function a:Fit(w, h)
    if not self.file or (self.fw == w and self.fh == h) or w <= 0 or h <= 0 then return end
    self.fw, self.fh = w, h
    local k = math.max(w / MAP_W, h / MAP_H)
    local vw, vh = w / k, h / k
    local vx, vy = (MAP_W - vw) / 2, (MAP_H - vh) / 2
    for i = 1, 12 do
      local row, col = math.floor((i - 1) / 4), math.mod(i - 1, 4)
      local tx0, ty0 = col * 256, row * 256
      local tx1 = tx0 + ((col == 3) and (MAP_W - 768) or 256)
      local ty1 = ty0 + ((row == 2) and (MAP_H - 512) or 256)
      local ix0, iy0 = math.max(tx0, vx), math.max(ty0, vy)
      local ix1, iy1 = math.min(tx1, vx + vw), math.min(ty1, vy + vh)
      local t = self.tiles[i]
      if ix1 - ix0 > 0.01 and iy1 - iy0 > 0.01 then
        t:ClearAllPoints()
        t:SetWidth((ix1 - ix0) * k)
        t:SetHeight((iy1 - iy0) * k)
        t:SetPoint("TOPLEFT", parent, "TOPLEFT", (ix0 - vx) * k, -(iy0 - vy) * k)
        t:SetTexCoord((ix0 - tx0) / 256, (ix1 - tx0) / 256, (iy0 - ty0) / 256, (iy1 - ty0) / 256)
        t:Show()
      else
        t:Hide()
      end
    end
  end
  return a
end

local ZONE_NAME = { WSG = "Warsong Gulch", AB = "Arathi Basin", AV = "Alterac Valley", TG = "Thorn Gorge" }
local AB_NODES = { "Stables", "Gold Mine", "Blacksmith", "Lumber Mill", "Farm" }
local SIDES = { "Alliance", "Horde" }
local POI = "Interface\\Minimap\\POIIcons"
local BAR_H, NODE_W = 16, 44

-- 6:03, 0:45: always minutes and seconds, a clock that reads the same every frame
local function Clock(s)
  if not s or s < 0 then s = 0 end
  s = math.ceil(s - 0.05)
  return string.format("%d:%02d", math.floor(s / 60), math.mod(s, 60))
end
S.Clock = Clock

-- Is the panel up and showing this part (so the Timers panel can leave it out)?
function S:Shows(what)
  local db = B.db.bgscore
  return db.enabled and db[what] and B:IsBG() and true or false
end

-- ---------------------------------------------------------------- build

local function Bar(f, fac)
  local c = U.FACTION[fac]
  local b = {}
  b.icon = U.Tex(f, U.FLAG[fac], "ARTWORK")
  b.icon:SetWidth(BAR_H + 4)
  b.icon:SetHeight(BAR_H + 4)
  b.bg = U.Tex(f, U.WHITE, "BORDER")
  b.bg:SetVertexColor(0, 0, 0, 0.55)
  b.bg:SetHeight(BAR_H)
  b.fill = U.Tex(f, "Interface\\TargetingFrame\\UI-StatusBar", "ARTWORK")
  b.fill:SetVertexColor(c[1], c[2], c[3], 0.9)
  b.fill:SetHeight(BAR_H)
  b.text = U.Text(f, 11)
  b.text:SetTextColor(1, 1, 1)
  b.bases = U.Text(f, 10, U.NARROW)
  b.bases:SetTextColor(0.9, 0.9, 0.9)
  return b
end

local function Big(f, fac)
  local b = {}
  b.icon = U.Tex(f, U.FLAG[fac], "ARTWORK")
  b.icon:SetWidth(24)
  b.icon:SetHeight(24)
  b.num = U.Text(f, 22)
  b.carrier = U.Text(f, 10, U.NARROW)
  return b
end

function S:Build()
  local f = U.Panel("OctoBGScore", "score", "Score", 300, 100, "TOP", 0, -30)
  f:Hide()
  self.frame = f
  self.bg = U.Tex(f, nil, "BACKGROUND")
  self.bg:SetAllPoints(f)
  self.map = S.MapArt(f)
  self.dim = U.Tex(f, U.WHITE, "BORDER")
  self.dim:SetAllPoints(f)
  -- contents on a child, above the picture and under the frame's edge
  local c = CreateFrame("Frame", nil, f)
  c:SetAllPoints(f)
  c:SetFrameLevel(f:GetFrameLevel() + 2)
  self.c = c
  -- the plaque and the battleground's name, over the frame's edge
  local top = CreateFrame("Frame", nil, f)
  top:SetAllPoints(f)
  top:SetFrameLevel(f:GetFrameLevel() + 8)
  self.top = top
  self.plaque = U.Tex(top, "Interface\\DialogFrame\\UI-DialogBox-Header", "ARTWORK")
  self.title = U.Text(top, 12)
  self.title:SetTextColor(1, 0.82, 0)
  self.clock = U.Text(c, 12)
  self.clock:SetTextColor(1, 1, 1)
  for i = 1, 2 do
    local fac = SIDES[i]
    self.bars[fac] = Bar(c, fac)
    self.big[fac] = Big(c, fac)
  end
  self.vs = U.Text(c, 16)
  self.vs:SetText(":")
  self.vs:SetTextColor(1, 0.82, 0)
  -- the prediction: a button, a click says it in /bg
  local pb = CreateFrame("Button", nil, c)
  pb:SetHeight(16)
  pb:RegisterForClicks("LeftButtonUp")
  pb.text = U.Text(pb, 12)
  pb.text:SetPoint("CENTER", pb, "CENTER", 0, 0)
  pb:SetScript("OnClick", function() if this.say then U.SendBG(this.say) end end)
  self.pred = pb
  for i = 1, 5 do
    local n = CreateFrame("Button", nil, c)
    n:SetWidth(NODE_W)
    n:SetHeight(30)
    n:RegisterForClicks("LeftButtonUp")
    n.icon = U.Tex(n, POI, "ARTWORK")
    n.icon:SetWidth(16)
    n.icon:SetHeight(16)
    n.icon:SetPoint("TOP", n, "TOP", 0, 0)
    n.text = U.Text(n, 10)
    n.text:SetPoint("TOP", n.icon, "BOTTOM", 0, 0)
    n.name = AB_NODES[i]
    n:SetScript("OnClick", function() if this.say then U.SendBG(this.say) end end)
    n:SetScript("OnEnter", function()
      GameTooltip:SetOwner(this, "ANCHOR_BOTTOM")
      GameTooltip:AddLine(this.name, 1, 0.82, 0)
      if this.say then
        GameTooltip:AddLine(this.say, 1, 1, 1, 1)
        GameTooltip:AddLine("Click: say it in /bg", 0.6, 0.6, 0.6)
      end
      GameTooltip:Show()
    end)
    n:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.nodes[i] = n
  end
  self.extra = U.Text(c, 10, U.NARROW)
  self.extra:SetTextColor(0.85, 0.85, 0.85)
  -- the graveyard row along the bottom: your nearest graveyard's next wave, a
  -- bar sweeping down to it, and the enemy's soonest; a click says it in /bg
  local gy = CreateFrame("Button", nil, c)
  gy:SetHeight(20)
  gy:RegisterForClicks("LeftButtonUp")
  gy.icon = U.Tex(gy, "Interface\\Icons\\Spell_Holy_Resurrection", "ARTWORK")
  gy.icon:SetWidth(15)
  gy.icon:SetHeight(15)
  gy.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  gy.icon:SetPoint("LEFT", gy, "LEFT", 3, 1)
  gy.name = U.Text(gy, 11, U.NARROW)
  gy.name:SetPoint("LEFT", gy.icon, "RIGHT", 4, 0)
  gy.name:SetJustifyH("LEFT")
  gy.time = U.Text(gy, 13)
  gy.time:SetPoint("CENTER", gy, "CENTER", 6, 1)
  gy.enemy = U.Text(gy, 10, U.NARROW)
  gy.enemy:SetPoint("RIGHT", gy, "RIGHT", -3, 1)
  gy.enemy:SetTextColor(1, 0.5, 0.45)
  gy.track = U.Tex(gy, U.WHITE, "BORDER")
  gy.track:SetVertexColor(0, 0, 0, 0.5)
  gy.track:SetHeight(2)
  gy.track:SetPoint("BOTTOMLEFT", gy, "BOTTOMLEFT", 2, 0)
  gy.track:SetPoint("BOTTOMRIGHT", gy, "BOTTOMRIGHT", -2, 0)
  gy.sweep = U.Tex(gy, U.WHITE, "ARTWORK")
  gy.sweep:SetHeight(2)
  gy.sweep:SetPoint("BOTTOMLEFT", gy, "BOTTOMLEFT", 2, 0)
  gy:SetScript("OnClick", function() if this.say then U.SendBG(this.say) end end)
  gy:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("Next resurrection wave", 1, 0.82, 0)
    local SP = B.Timers.spirit
    if SP.perGuide then
      GameTooltip:AddLine("Graveyards here are healing out of step, so this is timed per graveyard: "
        .. "the nearest one to you, and on the right the enemy's soonest.", 1, 1, 1, 1)
    else
      GameTooltip:AddLine("Every 30 seconds, for the whole battleground and both sides, known from the game's clock "
        .. "with no graveyard in sight.", 1, 1, 1, 1)
      if this.confirmed then
        GameTooltip:AddLine("Gold: locked on to a real wave.", 1, 0.82, 0.2, 1)
      else
        GameTooltip:AddLine("White: from the game's clock. Turns gold once a heal or a spirit healer's timer confirms it.",
          0.8, 0.8, 0.8, 1)
      end
    end
    GameTooltip:AddLine("/obg reswave shows how it is known", 0.6, 0.6, 0.6)
    if this.say then GameTooltip:AddLine("Click: say it in /bg", 0.6, 0.6, 0.6) end
    GameTooltip:Show()
  end)
  gy:SetScript("OnLeave", function() GameTooltip:Hide() end)
  self.gy = gy
  -- every frame while shown; an error is recorded once (/obg errors), not every frame
  f:SetScript("OnUpdate", function()
    if S.broken then return end
    local ok, err = pcall(S.Frame, S, arg1 or 0)
    if not ok then
      S.broken = true
      B:Error(err)
    end
  end)
  self:Restyle()
end

-- Frame, picture, darkness, plaque, width: from the settings.
function S:Restyle()
  local f = self.frame
  if not f then return end
  local db = B.db.bgscore
  W.ArtFrame(f, db.border, db.borderColor)
  local zone = B.zone or "WSG"
  if db.art == "zone" then
    self.bg:Hide()
    self.map:Set((M.DATA[zone] or M.DATA.WSG).file)
    self.map.fw = nil     -- drawn again by Frame, which knows the size
  elseif db.art == "stone" then
    self.map:Set(nil)
    self.bg:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Background")
    self.bg:SetTexCoord(0, 1, 0, 1)
    self.bg:SetVertexColor(1, 1, 1, 1)
    self.bg:Show()
  else
    self.map:Set(nil)
    self.bg:Hide()
  end
  self.dim:SetVertexColor(0, 0, 0, (db.art == "plain") and math.max(db.dark, 0.7) or db.dark)
  local w = db.width or 300
  f:SetWidth(w)
  self.plaque:ClearAllPoints()
  local pw = math.min(w * 0.75, 240)
  self.plaque:SetWidth(pw)
  self.plaque:SetHeight(pw * 0.25)
  self.plaque:SetPoint("TOP", f, "TOP", 0, pw * 0.25 * 0.45)
  self.title:ClearAllPoints()
  self.title:SetPoint("TOP", self.plaque, "TOP", 0, -pw * 0.25 * 0.2)
  self.title:SetText(B.zone and (ZONE_NAME[B.zone] or B.zoneName) or "Warsong Gulch")
  if db.plaque then self.plaque:Show() else self.plaque:Hide() end
  self.mode = nil
end

-- ---------------------------------------------------------------- data

-- The scores, the prediction and base states; sample numbers while arranging.
function S:Data()
  local TM = B.Timers
  if B.test and not B.zone then
    -- arranging: a flag game, so the carriers show where they will be
    if not self.sample then
      self.sample = { Alliance = { cur = 2, max = 3 }, Horde = { cur = 1, max = 3 } }
    end
    return self.sample, nil, "WSG"
  end
  return TM.score, TM.pred, B.zone
end

-- Which layout the score asks for: "flags" (a few points), "bars", or none yet.
local function ModeOf(P)
  local max = P.Alliance.max or P.Horde.max
  if P.Alliance.cur == nil and P.Horde.cur == nil then return "none" end
  if max and max <= 10 then return "flags" end
  return "bars"
end

-- ---------------------------------------------------------------- layout

-- Changes when the carrier rows need placing again: -1 when they aren't here.
function S:RowsKey()
  local F = B.Flags
  if self.wantMode ~= "flags" or not B.db.bgscore.carriers or not B.db.flags.enabled or not (F and F.frame) then return -1 end
  return (F:Enemy() and 1 or 0) + (F:Friend() and 2 or 0) + (F.docked and 4 or 0)
end

local function ShowAll(t, on)
  for _, r in pairs(t) do
    if on then r:Show() else r:Hide() end
  end
end

function S:Layout(mode, zone)
  local db = B.db.bgscore
  local f, c = self.frame, self.c
  local w = db.width or 300
  local y = db.plaque and -18 or -6
  self.clock:ClearAllPoints()
  self.clock:SetPoint("TOPRIGHT", c, "TOPRIGHT", -8, -4)
  for i = 1, 2 do
    local fac = SIDES[i]
    local b, g = self.bars[fac], self.big[fac]
    ShowAll({ b.icon, b.bg, b.fill, b.text, b.bases }, mode == "bars")
    ShowAll({ g.icon, g.num, g.carrier }, mode == "flags")
    if mode == "bars" then
      b.icon:ClearAllPoints()
      b.icon:SetPoint("TOPLEFT", c, "TOPLEFT", 6, y + 2)
      b.bg:ClearAllPoints()
      b.bg:SetPoint("TOPLEFT", c, "TOPLEFT", 28, y)
      b.bg:SetWidth(w - 28 - 52)
      b.fill:ClearAllPoints()
      b.fill:SetPoint("LEFT", b.bg, "LEFT", 0, 0)
      b.text:ClearAllPoints()
      b.text:SetPoint("CENTER", b.bg, "CENTER", 0, 0)
      b.bases:ClearAllPoints()
      b.bases:SetPoint("LEFT", b.bg, "RIGHT", 5, 0)
      y = y - BAR_H - 4
    end
  end
  self.vs:Hide()
  if mode == "flags" then
    local mid, cy = w / 2, y - 13
    local A, H = self.big.Alliance, self.big.Horde
    A.num:ClearAllPoints()
    A.num:SetPoint("RIGHT", c, "TOPLEFT", mid - 12, cy)
    A.icon:ClearAllPoints()
    A.icon:SetPoint("RIGHT", A.num, "LEFT", -6, 0)
    H.num:ClearAllPoints()
    H.num:SetPoint("LEFT", c, "TOPLEFT", mid + 12, cy)
    H.icon:ClearAllPoints()
    H.icon:SetPoint("LEFT", H.num, "RIGHT", 6, 0)
    self.vs:ClearAllPoints()
    self.vs:SetPoint("CENTER", c, "TOPLEFT", mid, cy)
    self.vs:Show()
    y = y - 28
    A.carrier:ClearAllPoints()
    H.carrier:ClearAllPoints()
    A.carrier:Hide()
    H.carrier:Hide()
    if db.carriers then
      -- the flag carriers' full rows, inside this window (Flags.lua)
      if B.db.flags.enabled and B.Flags and B.Flags.frame then
        y = B.Flags:Dock(c, y, w)
      else
        A.carrier:Show()
        H.carrier:Show()
        A.carrier:SetPoint("TOPRIGHT", c, "TOPLEFT", mid - 4, y)
        H.carrier:SetPoint("TOPLEFT", c, "TOPLEFT", mid + 4, y)
        y = y - 14
      end
    end
  end
  local isAB = (zone == "AB")
  self.pred:ClearAllPoints()
  if mode == "bars" and isAB and db.predict then
    self.pred:SetPoint("TOPLEFT", c, "TOPLEFT", 4, y)
    self.pred:SetPoint("TOPRIGHT", c, "TOPRIGHT", -4, y)
    self.pred:Show()
    y = y - 18
  else
    self.pred:Hide()
  end
  local showNodes = isAB and db.nodes
  for i = 1, 5 do
    local n = self.nodes[i]
    n:ClearAllPoints()
    if showNodes then
      n:SetPoint("TOPLEFT", c, "TOPLEFT", (w - 5 * NODE_W) / 2 + (i - 1) * NODE_W, y)
      n:Show()
    else
      n:Hide()
    end
  end
  if showNodes then y = y - 30 end
  self.gy:ClearAllPoints()
  if db.graveyard then
    self.gy:SetPoint("TOPLEFT", c, "TOPLEFT", 6, y)
    self.gy:SetPoint("TOPRIGHT", c, "TOPRIGHT", -6, y)
    self.gy:Show()
    y = y - 22
  else
    self.gy:Hide()
  end
  self.extra:ClearAllPoints()
  self.extra:SetPoint("TOP", c, "TOP", 0, y)
  self.extraY = y
  f:SetHeight(math.max(36, -y + 6))
  self.mode, self.zoneMode = mode, zone
  self.rowsKey = self:RowsKey()
end

-- ---------------------------------------------------------------- every frame

local function NodeState(n, name, now)
  local TM = B.Timers
  local node = TM.obj.nodes[name]
  local m = M:FindLandmark(name)
  if m and m.tex and WorldMap_GetPOITextureCoords then
    n.icon:SetTexture(POI)
    n.icon:SetTexCoord(WorldMap_GetPOITextureCoords(m.tex))
    n.icon:Show()
  else
    n.icon:Hide()
  end
  if node and node.ends and node.ends > now then
    local c = U.FACTION[node.by] or { 1, 1, 1 }
    n.text:SetText(Clock(node.ends - now))
    n.text:SetTextColor(math.min(1, c[1] + 0.2), math.min(1, c[2] + 0.2), math.min(1, c[3] + 0.2))
    n.say = name .. ": " .. (node.by or "?") .. " takes it in " .. Clock(node.ends - now)
  else
    n.text:SetText("")
    if node and node.owner then n.say = name .. ": held by " .. node.owner else n.say = name .. ": nobody has it" end
  end
end

-- The nearest graveyard's next wave (Timers.lua: spirit guides' casts, the game's
-- own healer timer when in range), and the enemy's soonest.
function S:Graveyard(now, zone)
  local gy = self.gy
  local SP = B.Timers.spirit
  local g, rem, label, enemy
  if B.test and not B.zone then
    rem = 30 - math.mod(now, 30)
    label = "Next res wave"
    gy.confirmed = true
  else
    rem = SP:MyWave(now)
    -- one wave for the whole game: the nearest graveyard only names it when known
    g = SP:Nearest()
    label = g and SP:Label(g, now) or "Next res wave"
    gy.confirmed = SP.waveAt ~= nil or SP.perGuide
    if SP.perGuide then enemy = B.enemy and SP:NextWave(B.enemy, now) end
  end
  if rem then
    gy.name:SetText(label)
    gy.time:SetText(Clock(rem))
    -- green when the wave is about to go; gold once locked on, white from the clock alone
    if rem <= 5 then gy.time:SetTextColor(0.4, 1, 0.45)
    elseif gy.confirmed then gy.time:SetTextColor(1, 0.82, 0)
    else gy.time:SetTextColor(1, 1, 1) end
    local inner = (B.db.bgscore.width or 300) - 16
    gy.sweep:SetWidth(math.max(1, inner * math.min(1, rem / 30)))
    if rem <= 5 then gy.sweep:SetVertexColor(0.4, 1, 0.45, 1) else gy.sweep:SetVertexColor(1, 0.82, 0.2, 1) end
    gy.sweep:Show()
    gy.say = "Next res wave in " .. math.ceil(rem - 0.05) .. " sec"
  else
    -- the instant before the battleground's clock starts
    gy.name:SetText("|cff999999Next res wave|r")
    gy.time:SetText("")
    gy.sweep:Hide()
    gy.say = nil
  end
  gy.enemy:SetText(enemy and ("enemy " .. Clock(enemy)) or "")
end

function S:Frame(elapsed)
  local db = B.db.bgscore
  local now = GetTime()
  local P, pred, zone = self:Data()
  local mode = ModeOf(P)
  self.wantMode = mode
  if mode ~= self.mode or zone ~= self.zoneMode or self:RowsKey() ~= self.rowsKey then self:Layout(mode, zone) end
  self.map:Fit(self.frame:GetWidth(), self.frame:GetHeight())
  -- the time: to the start, else since it began (or the game's own running time)
  local TM = B.Timers
  local obj = TM.obj
  local t
  if db.time then
    if obj.start and obj.start > now then
      t = "starts " .. Clock(obj.start - now)
    elseif obj.begunAt then
      t = Clock(now - obj.begunAt)
    elseif GetBattlefieldInstanceRunTime and B.zone then
      local ms = GetBattlefieldInstanceRunTime()
      if ms and ms > 0 then t = Clock(ms / 1000) end
    elseif B.test then
      t = "12:34"
    end
  end
  self.clock:SetText(t or "")
  if mode == "bars" then
    local inner = (db.width or 300) - 28 - 52
    for i = 1, 2 do
      local fac = SIDES[i]
      local p, b = P[fac] or {}, self.bars[fac]
      local max = p.max or ((zone == "AV") and 600) or 2000
      local want = math.min(1, (p.cur or 0) / math.max(1, max))
      -- glide to a new value in about a quarter of a second
      local v = b.v or want
      v = v + (want - v) * math.min(1, elapsed * 8)
      if math.abs(want - v) < 0.0005 then v = want end
      b.v = v
      b.fill:SetWidth(math.max(1, inner * v))
      b.fill:SetTexCoord(0, v, 0, 1)
      b.text:SetText((p.cur or 0) .. (p.max and ("/" .. p.max) or ""))
      if p.bases then
        b.bases:SetText(p.bases .. ((p.bases == 1) and " base" or " bases"))
      else
        b.bases:SetText("")
      end
    end
    if self.pred:IsShown() then
      local c = pred and U.FACTION[pred.winner]
      if pred then
        local left = pred.at - now
        self.pred.text:SetText(pred.winner .. " wins in " .. Clock(left) .. "  (" .. pred.max .. " to " .. pred.score .. ")")
        self.pred.text:SetTextColor(math.min(1, c[1] + 0.25), math.min(1, c[2] + 0.25), math.min(1, c[3] + 0.25))
        self.pred.say = pred.winner .. " wins in " .. Clock(left) .. " (" .. pred.max .. " to " .. pred.score .. ")"
      else
        self.pred.text:SetText("nobody is scoring")
        self.pred.text:SetTextColor(0.7, 0.7, 0.7)
        self.pred.say = nil
      end
    end
  elseif mode == "flags" then
    local F = B.Flags
    for i = 1, 2 do
      local fac = SIDES[i]
      local g, p = self.big[fac], P[fac] or {}
      local c = U.FACTION[fac]
      g.num:SetText(p.cur or 0)
      g.num:SetTextColor(math.min(1, c[1] + 0.25), math.min(1, c[2] + 0.25), math.min(1, c[3] + 0.25))
      if db.carriers and F and not F.docked then
        -- this side holds the OTHER side's flag
        local other = (fac == "Alliance") and "Horde" or "Alliance"
        local cr = F.carriers[other]
        if cr and cr.dropped then
          g.carrier:SetText("|cffbbbbbb" .. other .. " flag dropped|r")
        elseif cr then
          local r, gg, bb = U.ClassColor(cr.class)
          g.carrier:SetText(string.format("|cff%02x%02x%02x%s|r", r * 255, gg * 255, bb * 255, cr.name) .. " has it")
        else
          g.carrier:SetText("")
        end
      end
    end
  end
  if self.nodes[1]:IsShown() then
    for i = 1, 5 do NodeState(self.nodes[i], AB_NODES[i], now) end
  end
  -- the graveyard row, every frame
  if self.gy:IsShown() then self:Graveyard(now, zone) end
  -- lines the game shows that are not a score (time limits and such)
  local ex = (zone == B.zone) and TM.extra or nil
  local s = (ex and ex[1]) and table.concat(ex, "   ") or ""
  if s ~= self.extraText then
    self.extraText = s
    self.extra:SetText(s)
    self.frame:SetHeight(math.max(36, -(self.extraY or -30) + 6 + ((s ~= "") and 14 or 0)))
  end
end

-- ---------------------------------------------------------------- wiring

function S:Wanted()
  return B.db.bgscore.enabled and (B:IsBG() or B.test)
end

B:Every(0.25, function()
  local f = S.frame
  if not f then return end
  if S:Wanted() then
    if not f:IsShown() then
      S:Restyle()
      f:Show()
    end
  elseif f:IsShown() then
    f:Hide()
  end
end, true)

B:On("OBG_INIT", function()
  S:Build()
  -- this panel replaces the game's score frame: hidden once, the option brings it back
  if not B.db.bgscore.tookOver and B.db.tidy then
    B.db.bgscore.tookOver = true
    B.db.tidy.scoreFrame = true
  end
end)

B:On("OBG_ZONE", function()
  for i = 1, 2 do S.bars[SIDES[i]].v = nil end
  S.extraText = nil
  if S.frame then S:Restyle() end
end)
