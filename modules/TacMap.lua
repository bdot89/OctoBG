-- OctoBG :: enemy map
-- The battleground's (or zone's) own map with live markers, built to show at
-- a glance where every enemy is:
--   * enemies: class-coloured triangles with a black rim; one that is
--     running becomes an arrowhead pointing the way they run. Always full
--     colour; only a last known spot fades (to half). A white ring marks your
--     target, a red ring Kill On Sight, a gold ring an immunity (Ice Block...).
--   * names under your target and Kill On Sight enemies (or all, or none)
--   * zoom (slider or mouse wheel): the view follows you; enemies outside it
--     sit on the edge, smaller, so none is ever lost
--   * hover an enemy for everything OctoBG knows, click to target, right-click
--     for the enemy menu (focus, Kill On Sight, announce)
--   * you (arrow), raid members (small class dots), both flag carriers,
--     objective icons, stealth marks; under the map: the enemy carrier's
--     whereabouts and how many enemies are on it
--
-- Drawing order is fixed with child frames: regions sharing one draw layer
-- have no set order in this client (the map tiles and the panel backdrop were
-- both BACKGROUND and swapped at random, blacking the map out). Zooming crops
-- each map tile with SetTexCoord instead of a scroll frame, so nothing
-- depends on how this client clips or scrolls.

local B = OctoBG
local U = B.U
local M = B.Map
local TM = { tiles = {}, pals = {}, foes = {}, pois = {}, flags = {}, ghosts = {}, hits = {}, nhits = 0 }
B.TacMap = TM

-- The world map draws a 1002 x 668 area from a 4 x 3 grid of 256 px tiles;
-- map coordinates 0..1 span that area.
local MAP_W, MAP_H = 1002, 668
local POI = "Interface\\Minimap\\POIIcons"
local MAX_FOES = 60

local function Dot(parent, file, layer, size)
  local t = U.Tex(parent, file, layer)
  t:SetWidth(size)
  t:SetHeight(size)
  t:Hide()
  return t
end

local function Layer(f, level)
  local l = CreateFrame("Frame", nil, f)
  l:SetAllPoints(f)
  l:SetFrameLevel(level)
  return l
end

local function Size(t, s)
  t:SetWidth(s)
  t:SetHeight(s)
end

-- ---------------------------------------------------------------- view (zoom)

-- Map coordinates (0..1) -> frame pixels for the current view. Off the view
-- returns the point pulled onto the edge and true.
function TM:ToFrame(mx, my)
  local x = (mx * MAP_W - self.vx) * self.k
  local y = (my * MAP_H - self.vy) * self.k
  local w, h = self.w, self.h
  if x >= 0 and x <= w and y >= 0 and y <= h then return x, y, false end
  local m = 5
  if x < m then x = m elseif x > w - m then x = w - m end
  if y < m then y = m elseif y > h - m then y = h - m end
  return x, y, true
end

local function Place(t, f, x, y)
  t:SetPoint("CENTER", f, "TOPLEFT", x, -y)
  t:Show()
end

-- Sets the visible window on the map: whole map at zoom 1, else a window
-- around (cx, cy) kept inside the map. Re-crops the tiles when it moves and
-- returns true then (markers placed by map coordinates must move too).
-- The zoom that applies here: battlegrounds and the open world have their own.
function TM:ZoomKey()
  return B.zone and "zoom" or "zoomWorld"
end

-- The view's centre: where you dragged it to, else you (map coordinates).
function TM:Center(pmx, pmy)
  if self.pan then return self.pan[1], self.pan[2] end
  return pmx, pmy
end

function TM:SetView(cx, cy)
  local z = (B.zone or B.test) and (B.db.map.zoom or 1) or (B.db.map.zoomWorld or 1)
  if z < 1 then z = 1 end
  local vw, vh = MAP_W / z, MAP_H / z
  local vx, vy = 0, 0
  if z > 1 and cx then
    vx = cx * MAP_W - vw / 2
    vy = cy * MAP_H - vh / 2
    if vx < 0 then vx = 0 elseif vx > MAP_W - vw then vx = MAP_W - vw end
    if vy < 0 then vy = 0 elseif vy > MAP_H - vh then vy = MAP_H - vh end
  end
  self.k = self.w / vw
  -- a dragged view stops at the map's edge
  if self.pan then self.pan[1], self.pan[2] = (vx + vw / 2) / MAP_W, (vy + vh / 2) / MAP_H end
  if self.vx and math.abs(vx - self.vx) < 0.5 and math.abs(vy - self.vy) < 0.5 and self.vz == z then return false end
  self.vx, self.vy, self.vz = vx, vy, z
  local k = self.k
  for i = 1, 12 do
    local row = math.floor((i - 1) / 4)
    local col = math.mod(i - 1, 4)
    local tx0, ty0 = col * 256, row * 256
    local tx1 = tx0 + ((col == 3) and (MAP_W - 768) or 256)
    local ty1 = ty0 + ((row == 2) and (MAP_H - 512) or 256)
    local ix0, iy0 = math.max(tx0, vx), math.max(ty0, vy)
    local ix1, iy1 = math.min(tx1, vx + vw), math.min(ty1, vy + vh)
    local t = self.tiles[i]
    if ix1 - ix0 > 0.01 and iy1 - iy0 > 0.01 and self.file then
      t:ClearAllPoints()
      t:SetWidth((ix1 - ix0) * k)
      t:SetHeight((iy1 - iy0) * k)
      t:SetPoint("TOPLEFT", self.frame, "TOPLEFT", (ix0 - vx) * k, -(iy0 - vy) * k)
      t:SetTexCoord((ix0 - tx0) / 256, (ix1 - tx0) / 256, (iy0 - ty0) / 256, (iy1 - ty0) / 256)
      t:Show()
    else
      t:Hide()
    end
  end
  self:CropOverlays(vx, vy, vw, vh, k)
  return true
end

-- Places a marker at map coordinates and keeps them on it (t.mx, t.my), so a
-- moving view can carry it along (Repin). edge: allowed on the view's edge.
function TM:Pin(t, mx, my, edge)
  t.mx, t.my, t.edgeOk = mx, my, edge
  local x, y, off = self:ToFrame(mx, my)
  if off and not edge then
    t:Hide()
    return nil
  end
  Place(t, self.frame, x, y)
  return x, y, off
end

local function Repin(self, list)
  for i, t in pairs(list) do
    if t.mx and t:IsShown() then self:Pin(t, t.mx, t.my, t.edgeOk) end
  end
end

-- "EFC +4" under the carrier's ring.
function TM:PlaceEfcText()
  local r = self.efcRing
  if not r:IsShown() or not r.mx then
    self.efcText:Hide()
    return
  end
  local x, y = self:ToFrame(r.mx, r.my)
  self.efcText:ClearAllPoints()
  self.efcText:SetPoint("TOP", self.frame, "TOPLEFT", x, -y - 14)
  self.efcText:Show()
end

function TM:Repin()
  Repin(self, self.pois)
  self:DrawBases(true)
  Repin(self, self.flags)
  if self.efcRing and self.efcRing:IsShown() and self.efcRing.mx then
    self:Pin(self.efcRing, self.efcRing.mx, self.efcRing.my, true)
    self:PlaceEfcText()
  end
  for i = 1, table.getn(self.ghosts) do
    local gh = self.ghosts[i]
    if gh.ring.mx and gh.ring:IsShown() then
      self:Pin(gh.ring, gh.ring.mx, gh.ring.my, true)
      self:Pin(gh.pip, gh.ring.mx, gh.ring.my, true)
      if gh.area:IsShown() then self:Pin(gh.area, gh.ring.mx, gh.ring.my, true) end
    end
  end
end

-- ---------------------------------------------------------------- build

function TM:Build()
  local w = B.db.map.width
  local f = U.Panel("OctoBGMap", "map", "Enemy map", w, w * MAP_H / MAP_W, "TOPLEFT", 30, -170)
  U.Backdrop(f, 0.9)
  f:Hide()
  self.frame = f
  local lv = f:GetFrameLevel()
  self.canvas = Layer(f, lv + 1)    -- the zone's base tiles
  self.ovl = Layer(f, lv + 2)       -- explored-area pictures, darkening, objective icons
  self.palLayer = Layer(f, lv + 3)  -- raid members, you
  self.foeLayer = Layer(f, lv + 4)  -- enemies
  self.topLayer = Layer(f, lv + 5)  -- rings, names, flag carriers

  for i = 1, 12 do self.tiles[i] = U.Tex(self.canvas, nil, "BACKGROUND") end
  self.ovTex, self.ovList = {}, {}
  self.dim = U.Tex(self.ovl, U.WHITE, "BORDER")
  self.dim:SetAllPoints(f)

  -- you: above your raid's dots but under the enemies, so an enemy standing
  -- next to you is never hidden by your own arrow (zoomed out on a zone map
  -- 10 yards is a pixel or two; user's report, Gadgetzan, 19 Oct 2026)
  self.me = Dot(self.palLayer, U.MEDIA .. "player", "OVERLAY", 14)
  self.flags.Alliance = Dot(self.topLayer, U.FLAG.Alliance, "OVERLAY", 18)
  self.flags.Horde = Dot(self.topLayer, U.FLAG.Horde, "OVERLAY", 18)
  -- the enemy flag carrier: a red ring round their flag and "EFC +4" (escort) under it
  self.efcRing = Dot(self.topLayer, U.MEDIA .. "circle", "ARTWORK", 30)
  self.efcRing:SetVertexColor(1, 0.2, 0.15, 1)
  self.efcText = U.Text(self.topLayer, 10, U.NARROW)
  self.efcText:SetTextColor(1, 0.35, 0.3)
  self.efcText:Hide()
  self.where = U.Text(f, 10, U.NARROW)
  self.where:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 2, -2)
  self.where:SetJustifyH("LEFT")
  self.count = U.Text(f, 10, U.NARROW)
  self.count:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", -2, -2)
  self.count:SetJustifyH("RIGHT")
  self.zoomText = U.Text(self.topLayer, 9, U.NARROW)
  self.zoomText:SetPoint("TOPRIGHT", f, "TOPRIGHT", -3, -3)
  self.zoomText:SetTextColor(0.8, 0.8, 0.8)

  -- hover, click and wheel
  f:SetScript("OnEnter", function() TM.hover = true end)
  f:SetScript("OnLeave", function()
    TM.hover = nil
    if TM.tipFor then
      TM.tipFor = nil
      GameTooltip:Hide()
    end
  end)
  -- left button down + move = drag the zoomed view; a press without moving is a click
  f:SetScript("OnMouseDown", function() if arg1 == "LeftButton" then TM:DragStart() end end)
  f:SetScript("OnMouseUp", function()
    if TM:DragStop() then return end
    TM:Click(arg1)
  end)
  f:SetScript("OnHide", function()
    TM.dragFrom = nil
    TM:ReleaseAddonButtons(true)
  end)
  f:SetScript("OnMouseWheel", function()
    local db, key = B.db.map, TM:ZoomKey()
    db[key] = math.max(1, math.min(6, (db[key] or 1) + ((arg1 > 0) and 0.5 or -0.5)))
    if db[key] <= 1 then TM.pan = nil end
    TM.vx = nil
    if B.Options then B.Options:Refresh() end
  end)
  -- "Back to me": shown while the view is dragged away from you
  local back = CreateFrame("Button", nil, self.topLayer)
  back:SetHeight(14)
  back:SetWidth(70)
  back:SetPoint("TOPLEFT", f, "TOPLEFT", 3, -3)
  U.Backdrop(back, 0.85)
  back.text = U.Text(back, 9, U.NARROW)
  back.text:SetPoint("CENTER", back, "CENTER", 0, 0)
  back.text:SetText("Back to me")
  back:SetScript("OnClick", function()
    TM.pan = nil
    TM.vx = nil
    this:Hide()
  end)
  back:Hide()
  self.back = back
  -- the big map (used as the world map): the zone's name on top, Escape closes it
  self.title = U.Text(self.topLayer, 14)
  self.title:SetPoint("TOP", f, "TOP", 0, -6)
  self.title:SetTextColor(1, 0.9, 0.6)
  self.title:Hide()
  local esc = CreateFrame("Frame", "OctoBGBigMap", UIParent)
  esc:Hide()
  esc:SetScript("OnHide", function() if TM.big then TM:SetBig(false) end end)
  table.insert(UISpecialFrames, "OctoBGBigMap")
  self.esc = esc
  -- pfUI's addon buttons (the minimap arrow's panel of addon icons), opened
  -- from the map's corner and shown beside the map
  local ab = B.W.Button(self.topLayer, "", 16, 16)
  ab:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -3, 3)
  ab.arrow = B.W.Arrow(ab, 9, "right", { 1, 0.9, 0.1 })
  ab.arrow:SetPoint("CENTER", ab, "CENTER", 0, 0)
  ab:SetScript("OnClick", function() TM:ToggleAddonButtons() end)
  B.W.Tip(ab, "Addon buttons", "Opens pfUI's panel of addon icons (the minimap arrow's) right next to this map. Click again to close it.")
  ab:Hide()
  self.abButton = ab
  -- the counting area of the base under the mouse
  self.baseMarks = {}
  -- smooth movement between the redraws (only while the map shows); an error
  -- is recorded once (/obg errors) and the markers fall back to 0.2 s steps
  f:SetScript("OnUpdate", function()
    if TM.fastBroken then return end
    local ok, err = pcall(TM.DragTick, TM)
    if ok then ok, err = pcall(TM.Fast, TM) end
    if ok and TM.abOwned then ok, err = pcall(TM.KeepAddonButtons, TM) end
    if not ok then
      TM.fastBroken = true
      B:Error(err)
    end
  end)
  self:Layout()
end

function TM:Layout()
  local f = self.frame
  if not f then return end
  local db = B.db.map
  local w = self.big and (db.bigWidth or 720) or db.width
  if self.title then
    if self.big then self.title:Show() else self.title:Hide() end
  end
  local h = w * MAP_H / MAP_W
  f:SetWidth(w)
  f:SetHeight(h)
  self.w, self.h = w, h
  self.vx = nil
  self.dim:SetVertexColor(0, 0, 0, db.dim or 0)
  f:EnableMouse(db.mouse and true or false)
  f:EnableMouseWheel(db.mouse and true or false)

  -- marker sizes grow with the map: stealth ring, its centre, enemy marker, raid member
  self.ringS = math.max(12, math.min(20, w / 32))
  self.pipS = self.ringS * 0.55
  self.triS = self.ringS * 1.15
  self.palS = self.ringS * 0.6
  for i = 1, table.getn(self.pals) do Size(self.pals[i], self.palS) end
end

function TM:SetFile(file)
  local explore = B.db.map.explore and true or false
  if file == self.file and explore == self.explore then return end
  self.file, self.explore = file, explore
  self.vx = nil
  for i = 1, 12 do
    if file then
      self.tiles[i]:SetTexture("Interface\\WorldMap\\" .. file .. "\\" .. file .. i)
    else
      self.tiles[i]:Hide()
    end
  end
  self:BuildOverlays(file)
end

-- Every explored-area picture of the zone (data\MapOverlays.lua, from the
-- client's WorldMapOverlay.dbc), so the whole zone shows as if explored. Each
-- picture is cut into 256 px tiles exactly as WorldMapFrame.lua does (the
-- last row / column sits in a texture of the next power of two); here each
-- tile becomes a rectangle in map pixels with its texture's used part (u1,
-- v1), and SetView crops them to the view like the base tiles.
function TM:BuildOverlays(file)
  local list = {}
  self.ovList = list
  local data = file and self.explore and B.MapOverlays and B.MapOverlays[file]
  if data then
    local base = "Interface\\WorldMap\\" .. file .. "\\"
    for i = 1, table.getn(data), 5 do
      local name, tw, th, ox, oy = data[i], data[i + 1], data[i + 2], data[i + 3], data[i + 4]
      local wide, tall = math.ceil(tw / 256), math.ceil(th / 256)
      for j = 1, tall do
        local ph, fh = 256, 256
        if j == tall then
          ph = math.mod(th, 256)
          if ph == 0 then ph = 256 end
          fh = 16
          while fh < ph do fh = fh * 2 end
        end
        for k = 1, wide do
          local pw, fw = 256, 256
          if k == wide then
            pw = math.mod(tw, 256)
            if pw == 0 then pw = 256 end
            fw = 16
            while fw < pw do fw = fw * 2 end
          end
          table.insert(list, { tex = base .. name .. ((j - 1) * wide + k), x = ox + 256 * (k - 1), y = oy + 256 * (j - 1),
                               w = pw, h = ph, u = pw / fw, v = ph / fh })
        end
      end
    end
  end
  for i = table.getn(list) + 1, table.getn(self.ovTex) do self.ovTex[i]:Hide() end
end

-- Crops the explored-area pictures to the view (vx, vy, vw, vh in map pixels).
function TM:CropOverlays(vx, vy, vw, vh, k)
  local list = self.ovList
  for i = 1, table.getn(list) do
    local o = list[i]
    local t = self.ovTex[i]
    if not t then
      t = U.Tex(self.ovl, nil, "BACKGROUND")
      self.ovTex[i] = t
    end
    local ix0, iy0 = math.max(o.x, vx), math.max(o.y, vy)
    local ix1, iy1 = math.min(o.x + o.w, vx + vw), math.min(o.y + o.h, vy + vh)
    if ix1 - ix0 > 0.01 and iy1 - iy0 > 0.01 then
      t:SetTexture(o.tex)
      t:ClearAllPoints()
      t:SetWidth((ix1 - ix0) * k)
      t:SetHeight((iy1 - iy0) * k)
      t:SetPoint("TOPLEFT", self.frame, "TOPLEFT", (ix0 - vx) * k, -(iy0 - vy) * k)
      t:SetTexCoord((ix0 - o.x) / o.w * o.u, (ix1 - o.x) / o.w * o.u, (iy0 - o.y) / o.h * o.v, (iy1 - o.y) / o.h * o.v)
      t:Show()
    else
      t:Hide()
    end
  end
end

-- ---------------------------------------------------------------- height marks
-- Up to three short white bars with a black rim, stacked ABOVE a marker when
-- that player is higher than you and BELOW it when lower: one bar from
-- db.map.heightStep yards (10), two from twice that, three from four times
-- (M.HeightTier). No colour of their own (every colour is some class's) and
-- no triangles (enemies are triangles): place and count say it. Within the
-- step nothing is drawn, so a slope never counts and ten players on one roof
-- are ten small bar stacks, not ten icons. Anchored to the marker, the bars
-- move with it every frame. db.map.height "off" switches them off.
local BAR_GAP = 3
local function LevelMark(layer, owner, width)
  local m = { owner = owner, bars = {} }
  for i = 1, 3 do
    local bg = U.Tex(layer, U.WHITE, "ARTWORK")      -- the black rim (ARTWORK under OVERLAY: a set order)
    bg:SetVertexColor(0, 0, 0, 0.9)
    bg:SetWidth(width + 2)
    bg:SetHeight(4)
    local fg = U.Tex(layer, U.WHITE, "OVERLAY")
    fg:SetVertexColor(1, 1, 1, 1)
    fg:SetWidth(width)
    fg:SetHeight(2)
    fg:SetPoint("CENTER", bg, "CENTER", 0, 0)
    bg:Hide()
    fg:Hide()
    m.bars[i] = { bg = bg, fg = fg }
  end
  m.Hide = function(self)
    for i = 1, 3 do
      self.bars[i].bg:Hide()
      self.bars[i].fg:Hide()
    end
  end
  return m
end

-- The height step of a player at world height z (nil = no mark).
function TM:FloorOf(x, y, z)
  if (B.db.map.height or "on") == "off" or not z then return nil end
  local _, _, pz = M:PlayerWorld()
  return M.HeightTier(z, pz, B.db.map.heightStep or 10)
end

function TM:SetLevel(m, tier)
  if not tier or tier == 0 then
    m:Hide()
    return
  end
  local n = math.abs(tier)
  local up = tier > 0
  for i = 1, 3 do
    local b = m.bars[i]
    if i <= n then
      b.bg:ClearAllPoints()
      if up then
        b.bg:SetPoint("BOTTOM", m.owner, "TOP", 0, 1 + (i - 1) * BAR_GAP)
      else
        b.bg:SetPoint("TOP", m.owner, "BOTTOM", 0, -1 - (i - 1) * BAR_GAP)
      end
      b.bg:Show()
      b.fg:Show()
    else
      b.bg:Hide()
      b.fg:Hide()
    end
  end
end

-- One enemy marker: triangle / arrowhead, rings, a name and a height mark.
function TM:Foe(i)
  local o = self.foes[i]
  if not o then
    o = {
      tri = Dot(self.foeLayer, U.MEDIA .. "tri", "ARTWORK", self.triS),
      -- target / Kill On Sight: the same shape a little bigger BEHIND the
      -- triangle (a white or red rim), never a ring over the neighbours
      ring = Dot(self.foeLayer, U.MEDIA .. "tri", "BORDER", self.triS * 1.4),
      imm = Dot(self.topLayer, U.MEDIA .. "circle", "ARTWORK", self.triS * 1.3),
      name = U.Text(self.topLayer, 9, U.NARROW),
    }
    o.lvl = LevelMark(self.topLayer, o.tri, math.max(8, self.triS * 0.7))
    o.imm:SetVertexColor(1, 0.82, 0.1, 1)
    o.name:Hide()
    self.foes[i] = o
  end
  return o
end

function TM:HideFoe(o)
  o.live, o.guid, o.hit = nil, nil, nil
  o.lvl:Hide()
  o.tri:Hide()
  o.ring:Hide()
  o.imm:Hide()
  o.name:Hide()
end

function TM:Ghost(i)
  local gh = self.ghosts[i]
  if not gh then
    local c = U.STEALTH
    gh = {
      area = Dot(self.foeLayer, U.MEDIA .. "ring", "BORDER", 10),
      ring = Dot(self.foeLayer, U.MEDIA .. "badge", "ARTWORK", self.ringS),
      pip = Dot(self.foeLayer, U.MEDIA .. "pip", "OVERLAY", self.pipS),
    }
    gh.area:SetVertexColor(c[1], c[2], c[3], 0.6)
    gh.ring:SetVertexColor(c[1], c[2], c[3], 1)
    self.ghosts[i] = gh
  end
  return gh
end

function TM:Pal(i)
  local t = self.pals[i]
  if not t then
    t = Dot(self.palLayer, U.MEDIA .. "pip", "ARTWORK", self.palS)
    t.lvl = LevelMark(self.palLayer, t, math.max(7, self.palS * 0.8))
    self.pals[i] = t
  end
  return t
end

-- ---------------------------------------------------------------- drawing

-- Where enemies went into stealth, with a circle (to map scale) for how far
-- they may have moved since.
function TM:DrawStealth(f, now)
  local T = B.Tracker
  local d = M:Cur()
  local yd = d and (self.k * MAP_W / (d.L - d.R)) or 0     -- frame pixels per yard
  local n = 0
  for guid, m in pairs(T.stealth) do
    local u = T.units[guid]
    if m.x and d and not (u and u.visible) and n < 20 then
      local mx, my = M:ToMap(m.x, m.y)
      if mx and mx >= 0 and mx <= 1 and my >= 0 and my <= 1 then
        n = n + 1
        local gh = self:Ghost(n)
        local r, g, b = U.ClassColor(m.class)
        gh.pip:SetVertexColor(r, g, b, 1)
        local _, _, edge = self:Pin(gh.ring, mx, my, true)
        self:Pin(gh.pip, mx, my, true)
        local rad = T:StealthRadius(m, now) * yd
        if rad >= 4 and not edge then
          Size(gh.area, rad * 2 * 64 / 61.5)
          self:Pin(gh.area, mx, my, true)
        else
          gh.area:Hide()
        end
      end
    end
  end
  for i = n + 1, table.getn(self.ghosts) do
    local gh = self.ghosts[i]
    gh.area:Hide()
    gh.ring:Hide()
    gh.pip:Hide()
  end
end

-- An enemy marker at frame position x, y. kind: "marked" names, "edge" small.
function TM:PaintFoe(o, f, u, x, y, edge, a, now, tg)
  local db = B.db.map
  local r, g, b = U.ClassColor(u.class)
  local s = edge and self.triS * 0.65 or self.triS
  o.s = s
  local moving = db.heading and B.Tracker.Moving(u, now)
  o.tri:SetTexture(U.MEDIA .. (moving and "dart" or "tri"))
  if moving then U.Rotate(o.tri, u.head) else o.tri:SetTexCoord(0, 1, 0, 1) end
  Size(o.tri, moving and s * 1.1 or s)
  o.tri:SetVertexColor(r, g, b, a)
  Place(o.tri, f, x, y)
  local P = B.People
  local kos = P:IsKOS(u.name)
  local isTarget = tg and u.guid == tg
  if isTarget or kos then
    -- a rim: the marker's own shape (and turn) behind it, 40 % bigger
    o.ring:SetTexture(U.MEDIA .. (moving and "dart" or "tri"))
    if moving then U.Rotate(o.ring, u.head) else o.ring:SetTexCoord(0, 1, 0, 1) end
    if isTarget then o.ring:SetVertexColor(1, 1, 1, a) else o.ring:SetVertexColor(1, 0.15, 0.15, a) end
    Size(o.ring, (moving and s * 1.1 or s) * 1.45)
    Place(o.ring, f, x, y)
  else
    o.ring:Hide()
  end
  if B.db.hud.immune and not edge and B.CD:ImmuneLeft(u.guid) then
    Size(o.imm, s * 1.3)
    Place(o.imm, f, x, y)
  else
    o.imm:Hide()
  end
  local names = db.names
  if not edge and u.name and (names == "all" or (names == "marked" and (isTarget or kos))) then
    o.name:SetText(u.name)
    o.name:SetTextColor(r, g, b, a)
    o.name:ClearAllPoints()
    o.name:SetPoint("TOP", f, "TOPLEFT", x, -y - s * 0.55)
    o.name:Show()
  else
    o.name:Hide()
  end
end

function TM:DrawEnemies(f, now)
  local ne, team = 0, 0
  self.nhits = 0
  self.nUp, self.nDown = 0, 0
  if B.db.map.enemies then
    local tg = U.GuidOf("target")
    local stealth = B.Tracker.stealth
    for guid, u in pairs(B.Tracker.units) do
      if u.x and not u.dead and now - (u.posAt or 0) < 10 and ne < MAX_FOES and not (stealth[guid] and not u.visible) then
        local mx, my = M:ToMap(u.x, u.y)
        if mx and mx >= 0 and mx <= 1 and my >= 0 and my <= 1 then
          ne = ne + 1
          if not u.visible and not u.fake then team = team + 1 end
          local x, y, edge = self:ToFrame(mx, my)
          local age = now - (u.posAt or 0)
          local a = (age > 2) and math.max(0.5, 1 - (age - 2) / 8) or 1
          local o = self:Foe(ne)
          self:PaintFoe(o, f, u, x, y, edge, a, now, tg)
          -- height only from this client's own sight (a teammate's report has no z)
          local tier = (not edge and u.visible) and self:FloorOf(u.x, u.y, u.z) or nil
          self:SetLevel(o.lvl, tier)
          if tier and tier > 0 then self.nUp = self.nUp + 1 elseif tier and tier < 0 then self.nDown = self.nDown + 1 end
          local h = self.hits[ne]
          if not h then
            h = {}
            self.hits[ne] = h
          end
          h.x, h.y = x, y
          if edge then h.u = nil else h.u = u end
          self.nhits = ne
          -- in sight: Fast moves it every frame from its live position
          o.guid, o.hit = guid, h
          o.live = (u.visible and not u.fake) and true or nil
        end
      end
    end
  end
  for i = ne + 1, table.getn(self.foes) do self:HideFoe(self.foes[i]) end
  for i = ne + 1, table.getn(self.hits) do
    local h = self.hits[i]
    if h then h.u = nil end
  end
  self.nfoes = ne
  return ne, team
end

-- Raid (or party) members.
function TM:DrawFriends(f)
  local nf = 0
  local nr = GetNumRaidMembers()
  local prefix, count = "raid", nr
  if nr == 0 then prefix, count = "party", GetNumPartyMembers() end
  for i = 1, count do
    local unit = prefix .. i
    if not UnitIsUnit(unit, "player") then
      local mx, my = M:UnitMap(unit)
      if mx then
        local x, y, edge = self:ToFrame(mx, my)
        if not edge then
          nf = nf + 1
          local t = self:Pal(nf)
          local _, class = UnitClass(unit)
          local r, g, b = U.ClassColor(class)
          t:SetVertexColor(r, g, b, UnitIsDeadOrGhost(unit) and 0.3 or 1)
          Place(t, f, x, y)
          t.unit = unit
          self:SetLevel(t.lvl, self:FloorOf(U.Position(unit)))
        end
      end
    end
  end
  for i = nf + 1, table.getn(self.pals) do
    self.pals[i]:Hide()
    self.pals[i].lvl:Hide()
    self.pals[i].unit = nil
  end
end

function TM:Samples(f)
  self:SetFile("WarsongGulch")
  self:SetView(0.5, 0.55)
  local fx, fy = self:ToFrame(0.52, 0.8)
  Place(self.flags.Alliance, f, fx, fy)
  self:Pin(self.efcRing, 0.52, 0.8, true)
  self.efcText:SetText("EFC +3")
  self:PlaceEfcText()
  fx, fy = self:ToFrame(0.47, 0.35)
  Place(self.flags.Horde, f, fx, fy)
  U.Rotate(self.me, 0.6)
  local x, y = self:ToFrame(0.5, 0.55)
  Place(self.me, f, x, y)
  local now = GetTime()
  local spots = {
    { 0.52, 0.8, "ROGUE", "Testrogue", nil }, { 0.49, 0.62, "MAGE", "Testmage", 0.4 },
    { 0.51, 0.6, "PRIEST", "Testpriest", nil }, { 0.53, 0.63, "HUNTER", "Testhunter", -2.2 },
  }
  local tg = "sampletarget"
  for i = 1, table.getn(spots) do
    local s = spots[i]
    local u = { class = s[3], name = s[4], guid = (i == 2) and tg or ("map" .. i), head = s[5], headAt = s[5] and now or nil }
    local mx, my = self:ToFrame(s[1], s[2])
    local o = self:Foe(i)
    self:PaintFoe(o, f, u, mx, my, false, 1, now, tg)
    -- height marks as they look: the mage on a roof, the hunter on the lower level
    local lvl = ((B.db.map.height or "on") ~= "off") and ((i == 2) and 2 or ((i == 4) and -1 or nil)) or nil
    self:SetLevel(o.lvl, lvl)
  end
  for i = table.getn(spots) + 1, table.getn(self.foes) do self:HideFoe(self.foes[i]) end
  self.nhits = 0
  local p = self:Pal(1)
  local r, g, b = U.ClassColor("WARRIOR")
  p:SetVertexColor(r, g, b, 1)
  x, y = self:ToFrame(0.5, 0.61)
  Place(p, f, x, y)
  local gh = self:Ghost(1)
  r, g, b = U.ClassColor("DRUID")
  gh.pip:SetVertexColor(r, g, b, 1)
  x, y = self:ToFrame(0.44, 0.5)
  Place(gh.ring, f, x, y)
  Place(gh.pip, f, x, y)
  Size(gh.area, self.w * 0.09)
  Place(gh.area, f, x, y)
  self.where:SetText("|cffff5555EFC|r Testrogue - Horde base - lower level")
  self.count:SetText("4 enemies")
end

function TM:Update()
  local f = self.frame
  local d = M:Cur()
  local now = GetTime()
  local db = B.db.map

  local z = (B.zone or B.test) and (db.zoom or 1) or (db.zoomWorld or 1)
  self.zoomText:SetText(z > 1 and (z .. "x") or "")
  if self.big then self.title:SetText(GetRealZoneText() or "") end
  if pfUI and pfUI.addonbuttons then self.abButton:Show() else self.abButton:Hide() end
  if not d then
    -- layout mode outside a battleground: Warsong Gulch with sample markers
    self.drawn = nil
    self:Samples(f)
    return
  end
  self.drawn = d
  self:SetFile(d.file)
  local pmx, pmy = M:UnitMap("player")
  self:SetView(self:Center(pmx, pmy))
  if self.pan and self.vz and self.vz > 1 then self.back:Show() else self.back:Hide() end

  -- objective icons
  local marks = M:Landmarks()
  local np = 0
  for i = 1, table.getn(marks) do
    local m = marks[i]
    if m.tex and WorldMap_GetPOITextureCoords then
      local _, _, edge = self:ToFrame(m.mx, m.my)
      if not edge then
        np = np + 1
        local t = self.pois[np]
        if not t then
          t = Dot(self.ovl, POI, "ARTWORK", 14)
          self.pois[np] = t
        end
        t:SetTexCoord(WorldMap_GetPOITextureCoords(m.tex))
        self:Pin(t, m.mx, m.my, false)
      end
    end
  end
  for i = np + 1, table.getn(self.pois) do self.pois[i]:Hide() end
  self:DrawBases()

  self:DrawFriends(f)
  local ne, team = self:DrawEnemies(f, now)
  self:DrawStealth(f, now)

  -- flag carriers (server-sent positions)
  local F = B.Flags
  if not self.flagLvl then
    self.flagLvl = { Alliance = LevelMark(self.topLayer, self.flags.Alliance, 11),
                     Horde = LevelMark(self.topLayer, self.flags.Horde, 11) }
  end
  for fac, t in pairs(self.flags) do
    local p = F.pos[fac]
    if p and now - p.t < 6 then
      self:Pin(t, p.mx, p.my, true)
      -- the carrier's floor, when this client sees them (your own team: always)
      local c = F.carriers[fac]
      local lvl
      if c and not c.dropped then
        local x, y, z
        if c.unit then
          x, y, z = U.Position(c.unit)
        elseif c.guid and B.Tracker.units[c.guid] and B.Tracker.units[c.guid].visible then
          local u = B.Tracker.units[c.guid]
          x, y, z = u.x, u.y, u.z
        end
        lvl = self:FloorOf(x, y, z)
      end
      self:SetLevel(self.flagLvl[fac], lvl)
    else
      t:Hide()
      self.flagLvl[fac]:Hide()
    end
  end
  local efc = F:Enemy()
  local ep = B.faction and F.pos[B.faction]   -- the enemy carries our flag
  if efc and not efc.dropped then
    local n = F:Escort(efc)
    self.where:SetText("|cffff5555EFC|r " .. efc.name .. (efc.where and (" - " .. efc.where) or "")
      .. ((n > 0) and (" - with " .. n) or ""))
    if ep and now - ep.t < 6 then
      self:Pin(self.efcRing, ep.mx, ep.my, true)
      self.efcText:SetText("EFC" .. ((n > 0) and (" +" .. n) or ""))
      self:PlaceEfcText()
    else
      self.efcRing:Hide()
      self.efcText:Hide()
    end
  else
    self.where:SetText("")
    self.efcRing:Hide()
    self.efcText:Hide()
  end
  if not B.env.position then
    -- without SuperWoW there are no enemy positions: say why the map is empty
    -- (shown even with the count switched off)
    self.count:SetText("|cffff7a3ano enemy positions: start WoW with SuperWoW|r"
      .. ((ne > 0) and (" |cff73bfff(" .. ne .. " via team)|r") or ""))
  elseif db.count then
    if ne > 0 then
      -- how many are above / below you (the height bars, summed up)
      local hs = ""
      if (self.nUp or 0) > 0 or (self.nDown or 0) > 0 then
        local parts = {}
        if self.nUp > 0 then table.insert(parts, self.nUp .. " above") end
        if self.nDown > 0 then table.insert(parts, self.nDown .. " below") end
        hs = " |cffdddddd- " .. table.concat(parts, ", ") .. "|r"
      end
      self.count:SetText(ne .. (ne == 1 and " enemy" or " enemies") .. ((team > 0) and (" |cff73bfff(" .. team .. " via team)|r") or "") .. hs)
    else
      self.count:SetText("|cff888888no enemies in sight|r")
    end
  else
    self.count:SetText("")
  end

  -- me
  if pmx then
    U.Rotate(self.me, M:Facing() or 0)
    local x, y = self:ToFrame(pmx, pmy)
    Place(self.me, f, x, y)
  else
    self.me:Hide()
  end
end

-- ---------------------------------------------------------------- every frame

-- The full redraw (Update) runs every 0.2 s; in between, every frame moves
-- you, your raid members and the enemies in sight to where they are now, so
-- the markers glide instead of jumping five times a second. Positions come
-- from the same calls as Update (the map position for raid members and you,
-- SuperWoW's UnitPosition for enemies); enemies only a teammate reports and
-- last known spots stay put until the next redraw.
function TM:MoveFoe(o, f, x, y)
  o.tri:SetPoint("CENTER", f, "TOPLEFT", x, -y)
  if o.ring:IsShown() then o.ring:SetPoint("CENTER", f, "TOPLEFT", x, -y) end
  if o.imm:IsShown() then o.imm:SetPoint("CENTER", f, "TOPLEFT", x, -y) end
  if o.name:IsShown() then o.name:SetPoint("TOP", f, "TOPLEFT", x, -y - (o.s or self.triS) * 0.55) end
  if o.hit then o.hit.x, o.hit.y = x, y end
end

function TM:Fast()
  local d = self.drawn
  if not d or d ~= M:Cur() or not M:EnsureMap() then return end
  local f = self.frame
  local pmx, pmy = GetPlayerMapPosition("player")
  if pmx and (pmx ~= 0 or pmy ~= 0) then
    if self:SetView(self:Center(pmx, pmy)) then self:Repin() end   -- zoomed: the view follows you (or stays where dragged)
    U.Rotate(self.me, M:Facing() or 0)
    local x, y = self:ToFrame(pmx, pmy)
    Place(self.me, f, x, y)
  end
  for i = 1, table.getn(self.pals) do
    local t = self.pals[i]
    if t.unit then
      local mx, my = GetPlayerMapPosition(t.unit)
      if mx and (mx ~= 0 or my ~= 0) then
        local x, y, edge = self:ToFrame(mx, my)
        if edge then
          t:Hide()
          t.lvl:Hide()
        else
          Place(t, f, x, y)
        end
      end
    end
  end
  for i = 1, self.nfoes or 0 do
    local o = self.foes[i]
    if o.live then
      local mx, my = M:ToMap(U.Position(o.guid))
      if mx then
        local x, y = self:ToFrame(mx, my)
        self:MoveFoe(o, f, x, y)
      end
    end
  end
end

-- ---------------------------------------------------------------- mouse

-- The cursor in frame pixels from the map's top left (y downwards), or nil.
function TM:Cursor()
  local f = self.frame
  local s = f:GetEffectiveScale()
  local cx, cy = GetCursorPosition()
  local left, top = f:GetLeft(), f:GetTop()
  if not left or not top or not cx then return nil end
  return cx / s - left, top - cy / s
end

-- Dragging the zoomed view: the map point under the cursor stays under it.
-- Only once the mouse moved 4 px, so a plain click stays a click.
function TM:DragStart()
  self.dragMoved = nil
  if not self.vz or self.vz <= 1 or not self.k or not self.vx then return end
  local cx, cy = self:Cursor()
  if not cx then return end
  self.dragFrom = { cx, cy, (self.vx + self.w / self.k / 2) / MAP_W, (self.vy + self.h / self.k / 2) / MAP_H }
end

function TM:DragTick()
  local d = self.dragFrom
  if not d then return end
  local cx, cy = self:Cursor()
  if not cx then return end
  local dx, dy = cx - d[1], cy - d[2]
  if not self.dragMoved and dx * dx + dy * dy < 16 then return end
  self.dragMoved = true
  self.pan = { d[3] - dx / self.k / MAP_W, d[4] - dy / self.k / MAP_H }
  if self.tipFor then
    self.tipFor = nil
    GameTooltip:Hide()
  end
  if self.drawn then self:Update() end
end

-- Ends a drag; true when it was one (the mouse-up is then not a click).
function TM:DragStop()
  local moved = self.dragMoved
  self.dragFrom, self.dragMoved = nil, nil
  return moved
end

-- The enemy under the cursor (within 10 px), or nil.
function TM:Under()
  local cx, cy = self:Cursor()
  if not cx then return nil end
  local best, bestD = nil, 100
  for i = 1, self.nhits do
    local h = self.hits[i]
    if h and h.u then
      local dx, dy = h.x - cx, h.y - cy
      local dd = dx * dx + dy * dy
      if dd < bestD then best, bestD = h.u, dd end
    end
  end
  return best
end

-- The INC bar's base under the cursor (within 14 px of its spot), or nil.
function TM:BaseUnder()
  local I = B.Incoming
  if not I or not self.drawn or not self.vx then return nil end   -- no view yet (between a zoom and the next redraw)
  local cx, cy = self:Cursor()
  if not cx then return nil end
  local best, bestD = nil, 196
  for i = 1, table.getn(I.bases) do
    local b = I.bases[i]
    if b.x and not b.wide then
      local mx, my = M:ToMap(b.x, b.y)
      if mx then
        local x, y, off = self:ToFrame(mx, my)
        local dx, dy = x - cx, y - cy
        if not off and dx * dx + dy * dy < bestD then best, bestD = b, dx * dx + dy * dy end
      end
    end
  end
  return best
end

-- ---------------------------------------------------------------- bases

-- Every base of the INC bar (AB nodes, WSG flag rooms / midfield) gets its
-- counting circle (db.inc.radius, to map scale) and a label on the circle's
-- top edge: "ST 3" (+2 when more run in). The label is a button above the
-- enemy markers, so it can always be clicked however crowded the base is
-- (user: "hard to hover over the base when many arrows are there").
-- Click: post "3 AT STABLES"; right-click: pick it on the INC bar.
function TM:BaseTip(owner, base)
  local I = B.Incoming
  local msg, at, coming = I:AtText(base)
  GameTooltip:SetOwner(owner, "ANCHOR_CURSOR")
  GameTooltip:AddLine(base.name)
  GameTooltip:AddLine(at .. " enemies inside the circle, " .. coming .. " running to it", 1, 1, 1)
  GameTooltip:AddLine("Click: post \"" .. msg .. "\"", 0.4, 0.8, 0.4)
  GameTooltip:AddLine("Right-click: pick it on the INC bar", 0.4, 0.8, 0.4)
  GameTooltip:Show()
end

function TM:BaseClick(base, button)
  local I = B.Incoming
  if button == "RightButton" then
    I.pinned = base.name
    I:Paint()
    UIErrorsFrame:AddMessage("INC bar: " .. base.name, 1, 0.82, 0)
  else
    I:Post("at", nil, base)
  end
end

function TM:BaseMark(i)
  local m = self.baseMarks[i]
  if m then return m end
  m = {}
  m.ring = Dot(self.ovl, U.MEDIA .. "ring", "OVERLAY", 10)
  local b = CreateFrame("Button", nil, self.topLayer)
  b:SetHeight(14)
  b:SetWidth(40)
  b:SetFrameLevel(self.topLayer:GetFrameLevel() + 3)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  B.W.Flat(b, B.W.C.bg, 0.85, B.W.C.lineHi)
  b.text = U.Text(b, 9, U.NARROW)
  b.text:SetPoint("CENTER", b, "CENTER", 0, 0)
  b:SetScript("OnEnter", function()
    this:SetBackdropBorderColor(1, 1, 1, 1)
    if this.base then TM:BaseTip(this, this.base) end
  end)
  b:SetScript("OnLeave", function()
    this:SetBackdropBorderColor(B.W.C.lineHi[1], B.W.C.lineHi[2], B.W.C.lineHi[3], 1)
    GameTooltip:Hide()
  end)
  b:SetScript("OnClick", function() if this.base then TM:BaseClick(this.base, arg1) end end)
  m.badge = b
  self.baseMarks[i] = m
  return m
end

-- quick: only move them (the view moved); counts and labels are redrawn every 0.2 s
function TM:DrawBases(quick)
  local I, d, n = B.Incoming, M:Cur(), 0
  if I and d and B.zone and B.db.map.bases and self.vx then
    local yd = self.k * MAP_W / (d.L - d.R)       -- frame pixels per yard
    local rad = B.db.inc.radius * yd
    for i = 1, table.getn(I.bases) do
      local base = I.bases[i]
      local mx, my
      if base.x and not base.wide then mx, my = M:ToMap(base.x, base.y) end
      if mx then
        local x, y, off = self:ToFrame(mx, my)
        if not off then
          n = n + 1
          local m = self:BaseMark(n)
          Size(m.ring, rad * 2 * 64 / 61.5)
          self:Pin(m.ring, mx, my, false)
          local b = m.badge
          if not quick or b.base ~= base then
            local at, coming = I:Counts(base)
            if at > 0 then m.ring:SetVertexColor(1, 0.35, 0.25, 0.75) else m.ring:SetVertexColor(0.45, 0.8, 1, 0.45) end
            b.base = base
            b.text:SetText(base.short .. " " .. at .. ((coming > 0) and (" |cffffb030+" .. coming .. "|r") or ""))
            if at > 0 then b.text:SetTextColor(1, 0.45, 0.35) else b.text:SetTextColor(0.75, 0.85, 0.95) end
            b:SetWidth(math.max(30, (b.text:GetStringWidth() or 20) + 10))
          end
          b:ClearAllPoints()
          b:SetPoint("CENTER", self.frame, "TOPLEFT", x, -math.max(8, y - rad))
          b:Show()
        end
      end
    end
  end
  for i = n + 1, table.getn(self.baseMarks) do
    self.baseMarks[i].ring:Hide()
    self.baseMarks[i].badge:Hide()
    self.baseMarks[i].badge.base = nil
  end
end

function TM:HoverTick()
  if not self.hover or not B.db.map.mouse or self.dragMoved then return end
  local u = self:Under()
  local base = not u and self:BaseUnder()
  local what = u or base
  if what == self.tipFor and not base then return end
  self.tipFor = what
  local drag = (self.vz and self.vz > 1) and "  Drag: look around" or ""
  if u and u.name then
    B.Roster:Tooltip(u.name, u, self.frame, "ANCHOR_CURSOR")
    GameTooltip:AddLine("Click: target  Right-click: menu  Wheel: zoom" .. drag, 0.4, 0.8, 0.4)
    GameTooltip:Show()
  elseif base then
    self:BaseTip(self.frame, base)     -- refreshed every tick while hovered, so the counts stay live
  else
    GameTooltip:Hide()
  end
end

function TM:Click(button)
  local u = self:Under()
  if u and u.name then
    if button == "RightButton" then
      B.Roster:Menu(u.name, u)
    else
      B.Roster:Target(u.name, u)
    end
    return
  end
  local base = self:BaseUnder()
  if base then self:BaseClick(base, button) end
end

-- ---------------------------------------------------------------- driver

-- ---------------------------------------------------------------- pfUI's addon buttons

-- pfUI.addonbuttons (pfUI\modules\addonbuttons.lua) is the panel its minimap
-- arrow opens. pfUI places it against the minimap every time it shows and
-- every 5 s (SetupMainFrame via ProcessButtons), so while it was opened from
-- here (TM.abOwned) KeepAddonButtons puts it back beside the map each frame;
-- closing it, or hiding the map, gives it back to pfUI.
local function AB() return pfUI and pfUI.addonbuttons end

function TM:ToggleAddonButtons()
  local p = AB()
  if not p then return end
  if p:IsShown() and self.abOwned then
    p:Hide()
    self:ReleaseAddonButtons()
  else
    self.abOwned = true
    p:Show()                 -- pfUI's OnShow fills it (and places it at the minimap)
    self:KeepAddonButtons()
  end
end

function TM:KeepAddonButtons()
  local p = AB()
  if not self.abOwned or not p then return end
  if not p:IsShown() then          -- closed some other way (pfUI's own arrow)
    self:ReleaseAddonButtons()
    return
  end
  local f = self.frame
  local _, rel = p:GetPoint(1)
  if rel == f then return end
  -- beside the map: right of it, or left when there is no room on the right
  local right = f:GetRight()
  local room = right and UIParent:GetRight() and
    (UIParent:GetRight() * UIParent:GetEffectiveScale() - right * f:GetEffectiveScale()) > (p:GetWidth() + 8) * p:GetEffectiveScale()
  p:ClearAllPoints()
  if room or not right then
    p:SetPoint("TOPLEFT", f, "TOPRIGHT", 4, 0)
  else
    p:SetPoint("TOPRIGHT", f, "TOPLEFT", -4, 0)
  end
end

-- hide: the map went away, so the panel goes with it
function TM:ReleaseAddonButtons(hide)
  if not self.abOwned then return end
  self.abOwned = nil
  local p = AB()
  if not p then return end
  if hide and p:IsShown() then p:Hide() end
  if p.ProcessButtons then pcall(p.ProcessButtons, p) end   -- pfUI places it at the minimap again
end

-- ---------------------------------------------------------------- as the world map

-- db.map.worldKey: what the M key (ToggleWorldMap) opens - "game" the game's
-- world map, "obg" this map big in the middle of the screen (anywhere, with
-- the zone's name on top; M or Escape closes it), "off" nothing.
function TM:SetBig(on)
  local f = self.frame
  if not f then return end
  on = on and true or nil
  if on == self.big then return end
  self.big = on
  if on then
    self.closed = nil
    M.checkedZone = nil      -- look the zone up again now
    M:RefreshWorld()
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 30)
    f:SetFrameStrata("DIALOG")
    self.esc:Show()
  else
    f:SetFrameStrata("MEDIUM")
    U.RestorePos(f)
    self.esc:Hide()
    self.pan = nil
  end
  B:RefreshActive()
  self:Layout()
  if on then
    f:Show()
    self:Update()
  elseif not self:Wanted() then
    f:Hide()
  end
end

function TM:ToggleBig() self:SetBig(not self.big) end

local gameToggle
local function MapKey()
  local mode = B.db.map.worldKey
  if mode == "obg" and TM.frame then
    TM:ToggleBig()
  elseif mode == "off" then
    UIErrorsFrame:AddMessage("World map switched off - OctoBG options, Enemy map, \"The M key opens\"", 1, 0.82, 0)
  elseif gameToggle then
    gameToggle()
  end
end

-- The M key and the minimap's world map button both call ToggleWorldMap.
-- pfUI's map module defines its own ToggleWorldMap when pfUI loads (after
-- OctoBG: addons load in name order), so the hook is (re)applied at login and
-- on entering the world, wrapping whichever version is current - pfUI's
-- movable, map-revealing world map stays what "game" opens.
local function HookMapKey()
  if ToggleWorldMap and ToggleWorldMap ~= MapKey then
    gameToggle = ToggleWorldMap
    ToggleWorldMap = MapKey
  end
end
TM.HookMapKey = HookMapKey
B:On("OBG_INIT", HookMapKey)
B:On("PLAYER_LOGIN", HookMapKey)
B:On("PLAYER_ENTERING_WORLD", HookMapKey)

function TM:Wanted()
  local db = B.db.map
  if self.big then return true end
  if not db.enabled or self.closed then return false end
  if B.test then return true end
  if B.zone then return M.DATA[B.zone] ~= nil end
  return db.world and M.world ~= nil and B.active
end

B:Every(0.2, function()
  local f = TM.frame
  if not f then return end
  if TM:Wanted() then
    if not f:IsShown() then f:Show() end
    TM:Update()
  elseif f:IsShown() then
    f:Hide()
  end
end, true)

B:Every(0.1, function() TM:HoverTick() end, true)

B:On("OBG_ACTIVE", function(ev, on)
  if not on and TM.frame then TM.frame:Hide() end
end)

B:On("OBG_INIT", function() TM:Build() end)
-- a new zone: the view follows you again
B:On("OBG_ZONE", function()
  TM.pan = nil
  TM.vx = nil
end)

function OctoBG_ToggleMap()
  local db = B.db.map
  if TM.frame and TM.frame:IsShown() then
    TM.closed = true
    TM.frame:Hide()
  else
    TM.closed = nil
    db.enabled = true
    if not B.zone and not db.world then
      db.world = true
      B:RefreshActive()
    end
  end
  if B.Options then B.Options:Refresh() end
end
