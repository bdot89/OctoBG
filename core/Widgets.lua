-- OctoBG :: option widgets
-- A page is a title (with an ON / OFF switch where the feature has one), a
-- one-line summary, and a stack of folding cards. Inside a card the small
-- controls (tick boxes, sliders, dropdowns, colours) sit two to a row; text
-- boxes, buttons, key bindings and notes take the whole row. What a setting
-- does is in its tooltip (hover it), not under it.
--
-- The look is flat (user's choice, 17 Oct 2026): dark panels with 1 px
-- borders, slim toggle switches, square tick boxes, thin sliders, OctoBG blue
-- for what is on or picked - drawn from a white texture and OctoBG's own
-- disc / tri textures, no game artwork. W.Skin, W.Bar, W.Ornament and
-- W.Header (the game's art) stay for the other windows that use them.
--
-- Layout flows: each widget is anchored under the one before it (or beside
-- it, for the right-hand column), cards under each other, so a folded card
-- pulls everything below it up. Fonts are set by path, so a UI replacing the
-- game's font objects (pfUI) cannot make text spill out. After a page is
-- drawn, open cards and the scroll height are measured (a frame each).
-- Every widget has a Refresh that re-reads its setting, and every labelled
-- one goes into W.index for the window's "Find a setting" box.

local B = OctoBG
local U = B.U
local W = { menus = {}, index = {} }
B.W = W

W.WIDTH = 540      -- page body width
local X = 6        -- page margin
W.CW = 508         -- width inside a card
local HALF = 246   -- a cell of the two-column grid
local COL2 = 260   -- where the right-hand column starts
local CTRL = 196   -- whole-row controls start here, after their label
local CARD_HEAD = 24
local CARD_TOP = 32 -- card top to its first control

local MEDIA = "Interface\\AddOns\\OctoBG\\media\\"

-- The flat palette.
local C = {
  bg = { 0.067, 0.071, 0.078 },     -- the window
  panel = { 0.094, 0.098, 0.11 },   -- top bar, topic list, page
  card = { 0.125, 0.13, 0.145 },
  head = { 0.165, 0.17, 0.19 },     -- card bars
  field = { 0.07, 0.073, 0.08 },    -- boxes you type or pick in
  btn = { 0.18, 0.19, 0.21 },
  line = { 0.23, 0.24, 0.27 },      -- borders
  lineHi = { 0.36, 0.38, 0.43 },
  text = { 0.92, 0.92, 0.93 },
  dim = { 0.6, 0.61, 0.65 },
  accent = { 0.2, 0.7, 1 },         -- OctoBG blue
  on = { 0.22, 0.72, 0.42 },
  off = { 0.3, 0.31, 0.35 },
}
W.C = C

-- The game's artwork, for the windows that keep it (statistics, alert box,
-- move toolbar). All checked in this client's MPQs.
local ART = {
  dialogBg = "Interface\\DialogFrame\\UI-DialogBox-Background",
  goldBorder = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
  dialogBorder = "Interface\\DialogFrame\\UI-DialogBox-Border",
  header = "Interface\\DialogFrame\\UI-DialogBox-Header",
  tipBg = "Interface\\Tooltips\\UI-Tooltip-Background",
  tipBorder = "Interface\\Tooltips\\UI-Tooltip-Border",
  bar = "Interface\\AuctionFrame\\UI-AuctionFrame-FilterBg",
  glow = "Interface\\QuestFrame\\UI-QuestTitleHighlight",
  ornament = "Interface\\QuestFrame\\UI-HorizontalBreak",
  -- OctoBG's own (tools\MakeTextures.ps1): white, coloured in game
  disc = MEDIA .. "disc",
  tri = MEDIA .. "tri",
}
W.ART = ART

-- Fonts set by path, never by font object. The options use Roboto (OFL, in
-- media\fonts) once it is known to load; Friz Quadrata until then / if not.
W.FONT = U.FONT
local ROBOTO = MEDIA .. "fonts\\Roboto.ttf"
local fontChecked
function W.UIFont()
  if not fontChecked and B.SpyData and B.SpyData.FontOK then
    fontChecked = true
    if B.SpyData.FontOK(ROBOTO) then W.FONT = ROBOTO end
  end
  return W.FONT
end
function W.Font(fs, size, r, g, b)
  fs:SetFont(W.UIFont(), size or 12, "")
  fs:SetShadowColor(0, 0, 0, 0.8)
  fs:SetShadowOffset(1, -1)
  if r then fs:SetTextColor(r, g, b) end
  return fs
end

-- A flat panel: one colour inside, a 1 px border.
function W.Flat(f, col, alpha, line)
  f:SetBackdrop({ bgFile = U.WHITE, edgeFile = U.WHITE, tile = false, tileSize = 0, edgeSize = 1,
                  insets = { left = 1, right = 1, top = 1, bottom = 1 } })
  col = col or C.panel
  line = line or C.line
  f:SetBackdropColor(col[1], col[2], col[3], alpha or 1)
  f:SetBackdropBorderColor(line[1], line[2], line[3], 1)
end

-- A plain colour texture.
function W.Fill(parent, col, alpha, layer)
  local t = parent:CreateTexture(nil, layer or "BACKGROUND")
  t:SetTexture(U.WHITE)
  t:SetVertexColor(col[1], col[2], col[3], alpha or 1)
  return t
end

-- The mouse-over light on a button.
local function Hover(b, alpha)
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetTexture(U.WHITE)
  hl:SetVertexColor(1, 1, 1, alpha or 0.07)
  hl:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
  hl:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
  return hl
end

-- A small triangle (OctoBG's tri.tga) pointing "up", "down", "right" or "left".
local TURN = { up = 0, left = 1.5708, down = 3.1416, right = -1.5708 }
function W.Arrow(parent, size, way, col)
  local t = parent:CreateTexture(nil, "OVERLAY")
  t:SetTexture(ART.tri)
  t:SetWidth(size)
  t:SetHeight(size)
  col = col or C.dim
  t:SetVertexColor(col[1], col[2], col[3], 1)
  U.Rotate(t, TURN[way or "down"])
  return t
end
function W.Turn(t, way) U.Rotate(t, TURN[way]) end

-- Game-art backdrops for the other windows: "window" (gold dialog frame),
-- "dialog" (silver), "panel" (tooltip border, dark inside).
function W.Skin(f, kind, alpha)
  if kind == "window" or kind == "dialog" then
    f:SetBackdrop({ bgFile = ART.dialogBg, edgeFile = (kind == "window") and ART.goldBorder or ART.dialogBorder,
                    tile = true, tileSize = 32, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 } })
    f:SetBackdropColor(1, 1, 1, alpha or 1)
  else
    f:SetBackdrop({ bgFile = ART.tipBg, edgeFile = ART.tipBorder, tile = true, tileSize = 16, edgeSize = 16,
                    insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    f:SetBackdropColor(0.04, 0.04, 0.05, alpha or 0.85)
    f:SetBackdropBorderColor(0.75, 0.75, 0.75, 1)
  end
end

-- The Auction House category bar behind a region, in three slices.
function W.Bar(region, alpha, layer)
  local function Slice(l, r)
    local t = region:CreateTexture(nil, layer or "BACKGROUND")
    t:SetTexture(ART.bar)
    t:SetTexCoord(l, r, 0, 0.625)
    t:SetVertexColor(1, 1, 1, alpha or 1)
    return t
  end
  local left, mid, right = Slice(0, 0.03125), Slice(0.03125, 0.5), Slice(0.5, 0.53125)
  left:SetWidth(8)
  left:SetPoint("TOPLEFT", region, "TOPLEFT", 0, 0)
  left:SetPoint("BOTTOMLEFT", region, "BOTTOMLEFT", 0, 0)
  right:SetWidth(8)
  right:SetPoint("TOPRIGHT", region, "TOPRIGHT", 0, 0)
  right:SetPoint("BOTTOMRIGHT", region, "BOTTOMRIGHT", 0, 0)
  mid:SetPoint("TOPLEFT", left, "TOPRIGHT", 0, 0)
  mid:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT", 0, 0)
  return left, mid, right
end

-- The gold ornament (cropped to its art).
function W.Ornament(parent, width)
  local orn = parent:CreateTexture(nil, "ARTWORK")
  orn:SetTexture(ART.ornament)
  orn:SetTexCoord(0.0898, 0.9063, 0.2188, 0.7813)
  orn:SetWidth(width)
  orn:SetHeight(16)
  return orn
end

-- The stone header plaque on top of a window, with its title.
function W.Header(f, text, width)
  local h = f:CreateTexture(nil, "ARTWORK")
  h:SetTexture(ART.header)
  h:SetWidth(width or 320)
  h:SetHeight(64)
  h:SetPoint("TOP", f, "TOP", 0, 12)
  local t = W.Font(f:CreateFontString(nil, "OVERLAY"), 13, 1, 0.82, 0)
  t:SetPoint("TOP", h, "TOP", 0, -14)
  t:SetText(text)
  return t, h
end

-- Hover help: the setting's name, what it does in white.
function W.Tip(frame, title, text)
  if not title and not text then return end
  frame.tipTitle, frame.tipText = title, text
  frame:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
    if this.tipTitle then GameTooltip:AddLine(this.tipTitle) end
    if this.tipText then GameTooltip:AddLine(this.tipText, 1, 1, 1, 1) end
    GameTooltip:Show()
  end)
  frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local count = 0
local function Name(kind)
  count = count + 1
  return "OctoBGOpt" .. kind .. count
end
W.Name = Name

local function Track(p, item)
  table.insert(p.items, item)
  return item
end

-- Labelled widgets are found by the window's search box.
local function Index(p, label, desc, region)
  if not label or not p.key then return end
  table.insert(W.index, { page = p, card = p.cur, label = label, desc = desc, region = region })
end

-- ---------------------------------------------------------------- flat parts

-- A flat button; b:SetText works (its font string is the button's).
function W.Button(parent, text, width, height, name)
  local b = CreateFrame("Button", name, parent)
  b:SetWidth(width or 120)
  b:SetHeight(height or 22)
  W.Flat(b, C.btn, 1, C.line)
  local fs = W.Font(b:CreateFontString(nil, "OVERLAY"), 11, C.text[1], C.text[2], C.text[3])
  fs:SetPoint("CENTER", b, "CENTER", 0, 0)
  b:SetFontString(fs)
  b.label = fs
  b:SetText(text)
  Hover(b)
  b:SetScript("OnMouseDown", function() this:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1) end)
  b:SetScript("OnMouseUp", function() if not this.picked then this:SetBackdropBorderColor(C.line[1], C.line[2], C.line[3], 1) end end)
  return b
end

-- A button shown as the picked one of a row (tabs).
function W.Pick(b, on)
  b.picked = on
  local l = on and C.accent or C.line
  b:SetBackdropBorderColor(l[1], l[2], l[3], 1)
  if on then b.label:SetTextColor(1, 1, 1) else b.label:SetTextColor(C.dim[1], C.dim[2], C.dim[3]) end
  local f = on and C.head or C.btn
  b:SetBackdropColor(f[1], f[2], f[3], 1)
end

-- A square tick box: blue inside when ticked.
function W.CheckBox(parent, size)
  local cb = CreateFrame("CheckButton", nil, parent)
  cb:SetWidth(size or 16)
  cb:SetHeight(size or 16)
  W.Flat(cb, C.field, 1, C.lineHi)
  cb:SetCheckedTexture(U.WHITE)
  local t = cb:GetCheckedTexture()
  if t then
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", cb, "TOPLEFT", 3, -3)
    t:SetPoint("BOTTOMRIGHT", cb, "BOTTOMRIGHT", -3, 3)
    t:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 1)
  end
  Hover(cb, 0.12)
  return cb
end

-- A slim toggle switch: a pill (disc caps and a bar) with a knob; green and
-- the knob right when on. b.Set(on) paints it.
function W.Toggle(parent)
  local b = CreateFrame("Button", nil, parent)
  b:SetWidth(32)
  b:SetHeight(16)
  local function Disc(size, layer)
    local t = b:CreateTexture(nil, layer or "ARTWORK")
    t:SetTexture(ART.disc)
    t:SetWidth(size)
    t:SetHeight(size)
    return t
  end
  local l, r = Disc(18), Disc(18)
  l:SetPoint("LEFT", b, "LEFT", -1, 0)
  r:SetPoint("RIGHT", b, "RIGHT", 1, 0)
  local m = b:CreateTexture(nil, "ARTWORK")
  m:SetTexture(U.WHITE)
  m:SetPoint("TOPLEFT", b, "TOPLEFT", 8, -1)
  m:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -8, 1)
  local knob = Disc(14, "OVERLAY")
  knob:SetVertexColor(0.95, 0.95, 0.96, 1)
  function b.Set(on)
    local col = on and C.on or C.off
    l:SetVertexColor(col[1], col[2], col[3], 1)
    r:SetVertexColor(col[1], col[2], col[3], 1)
    m:SetVertexColor(col[1], col[2], col[3], 1)
    knob:ClearAllPoints()
    if on then knob:SetPoint("RIGHT", b, "RIGHT", -1, 0) else knob:SetPoint("LEFT", b, "LEFT", 1, 0) end
    b.on = on
  end
  b.Set(false)
  return b
end

-- A thin slider: grey track, the part up to the knob in blue, a round knob.
-- Call W.SliderPaint(s) after its value changes.
function W.SliderBar(parent, width, name)
  local s = CreateFrame("Slider", name, parent)
  s:SetOrientation("HORIZONTAL")
  s:SetWidth(width)
  s:SetHeight(16)
  s:EnableMouse(true)
  s:SetThumbTexture(ART.disc)
  local th = s:GetThumbTexture()
  if th then
    th:SetWidth(14)
    th:SetHeight(14)
    th:SetVertexColor(0.95, 0.95, 0.96, 1)
  end
  local track = W.Fill(s, C.off, 1, "BACKGROUND")
  track:SetHeight(4)
  track:SetPoint("LEFT", s, "LEFT", 3, 0)
  track:SetPoint("RIGHT", s, "RIGHT", -3, 0)
  s.fill = W.Fill(s, C.accent, 1, "BORDER")
  s.fill:SetHeight(4)
  s.fill:SetPoint("LEFT", s, "LEFT", 3, 0)
  s.fill:SetWidth(1)
  s.width = width
  return s
end
function W.SliderPaint(s)
  local lo, hi = s:GetMinMaxValues()
  local f = 0
  if hi and lo and hi > lo then f = (s:GetValue() - lo) / (hi - lo) end
  s.fill:SetWidth(math.max(1, f * (s.width - 14) + 4))
end

-- A flat text box. Focus is tracked (1.12 has no EditBox:HasFocus(), pfQuest
-- notes the same) and lights the border; eb.OnFocus(on) is called if set.
function W.EditBox(parent, width, name)
  local eb = CreateFrame("EditBox", name, parent)
  eb:SetWidth(width)
  eb:SetHeight(20)
  W.Flat(eb, C.field, 1, C.line)
  eb:SetTextInsets(6, 6, 0, 0)
  eb:SetFont(W.UIFont(), 12, "")
  eb:SetTextColor(C.text[1], C.text[2], C.text[3])
  eb:SetAutoFocus(false)
  eb:EnableMouse(true)
  eb:SetScript("OnEscapePressed", function() this:ClearFocus() end)
  eb:SetScript("OnEditFocusGained", function()
    this.typing = true
    this:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
    if this.OnFocus then this.OnFocus(true) end
  end)
  eb:SetScript("OnEditFocusLost", function()
    this.typing = nil
    this:SetBackdropBorderColor(C.line[1], C.line[2], C.line[3], 1)
    if this.OnFocus then this.OnFocus(false) end
  end)
  return eb
end

-- ---------------------------------------------------------------- page and flow

-- A container is the page body or a card's inside: where its last widget is
-- (and how far right), and a left cell waiting for its right-hand neighbour.
local function Cur(p) return p.cur or p end

-- The scroll bar of a UIPanelScrollFrameTemplate made flat: no arrow buttons
-- (1.12 names them <frame>ScrollBarScrollUpButton / ...DownButton), a thin
-- track down the right edge and a plain thumb. Mouse wheel still scrolls.
function W.FlatScroll(sf)
  local n = sf:GetName()
  local sb = n and getglobal(n .. "ScrollBar")
  if not sb then return end
  local up, down = getglobal(n .. "ScrollBarScrollUpButton"), getglobal(n .. "ScrollBarScrollDownButton")
  if up then up:Hide() up:SetAlpha(0) end
  if down then down:Hide() down:SetAlpha(0) end
  sb:ClearAllPoints()
  sb:SetPoint("TOPLEFT", sf, "TOPRIGHT", 10, 0)
  sb:SetPoint("BOTTOMLEFT", sf, "BOTTOMRIGHT", 10, 0)
  sb:SetWidth(6)
  local track = W.Fill(sb, C.field, 1, "BACKGROUND")
  track:SetAllPoints(sb)
  sb:SetThumbTexture(U.WHITE)
  local th = sb:GetThumbTexture()
  if th then
    th:SetWidth(6)
    th:SetHeight(40)
    th:SetVertexColor(C.lineHi[1], C.lineHi[2], C.lineHi[3], 1)
  end
end

function W.Page(parent)
  local sf = CreateFrame("ScrollFrame", Name("Scroll"), parent, "UIPanelScrollFrameTemplate")
  sf:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, -8)
  sf:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -24, 8)
  W.FlatScroll(sf)
  local body = CreateFrame("Frame", nil, sf)
  body:SetWidth(W.WIDTH)
  body:SetHeight(20)
  sf:SetScrollChild(body)
  sf:Hide()
  return { frame = sf, body = body, items = {}, cards = {},
           parent = body, x0 = X, y0 = 0, width = W.WIDTH - 2 * X, lastX = 0 }
end

-- Anchors a region on a new line of container c, x from its left edge.
local function Put(c, region, x, gap)
  x = x or 0
  region:ClearAllPoints()
  if c.last then
    region:SetPoint("TOPLEFT", c.last, "BOTTOMLEFT", x - c.lastX, -(gap or 4))
  else
    region:SetPoint("TOPLEFT", c.parent, "TOPLEFT", c.x0 + x, -(c.y0 + (gap or 4)))
  end
  c.last, c.lastX, c.half = region, x, nil
  return region
end

-- A cell of the two-column grid: left on a new line, or right of the cell
-- waiting there. The taller of the two carries the line on.
local function PutHalf(c, cell, gap)
  local left = c.half
  if left then
    cell:ClearAllPoints()
    cell:SetPoint("TOPLEFT", left, "TOPLEFT", COL2, 0)
    if cell:GetHeight() > left:GetHeight() then c.last, c.lastX = cell, c.lastX + COL2 end
    c.half = nil
  else
    Put(c, cell, 0, gap)
    c.half = cell
  end
  return cell
end

-- A cell frame in the current container; half width unless full.
local function Cell(p, h, full)
  local c = Cur(p)
  local f = CreateFrame("Frame", nil, c.parent)
  f:SetWidth(full and c.width or HALF)
  f:SetHeight(h)
  return f, c
end

-- Anchors a region on its own line (indent from the left).
function W.Place(p, region, indent, gap)
  return Put(Cur(p), region, indent, gap)
end

-- A blank row of a fixed height for custom controls; children go relative to it.
function W.Row(p, h, indent, gap)
  local c = Cur(p)
  local r = CreateFrame("Frame", nil, c.parent)
  r:SetWidth(c.width - (indent or 0))
  r:SetHeight(h)
  return Put(c, r, indent, gap)
end

-- Open cards are measured one frame after drawing, the page the frame after
-- (its height depends on the cards'). p.after runs once everything is placed.
function W.Measure(p)
  if not p.body then return end   -- pages with their own layout (spell filter)
  p.body:SetScript("OnUpdate", function()
    this:SetScript("OnUpdate", nil)
    for i = 1, table.getn(p.cards) do
      local c = p.cards[i]
      if c.last and W.IsOpen(c) then
        local top, bottom = c.parent:GetTop(), c.last:GetBottom()
        if top and bottom then
          c.h = math.max(1, top - bottom)
          c.parent:SetHeight(c.h)
          c.card:SetHeight(CARD_TOP + c.h + 10)
        end
      end
    end
    this:SetScript("OnUpdate", function()
      this:SetScript("OnUpdate", nil)
      local top, bottom = this:GetTop(), p.last and p.last:GetBottom()
      if top and bottom then
        this:SetHeight(math.max(20, top - bottom + 18))
        p.frame:UpdateScrollChildRect()
      end
      if p.after then
        local fn = p.after
        p.after = nil
        fn()
      end
    end)
  end)
end

function W.Done(p)
  p.cur = nil
  W.Measure(p)
end

function W.Refresh(p)
  for i = 1, table.getn(p.items) do p.items[i].Refresh() end
  W.Measure(p)
end

function W.CloseMenus()
  for i = 1, table.getn(W.menus) do W.menus[i]:Hide() end
end

function W.Space(p, h)
  W.Row(p, h or 6, 0, 0)
end

-- An empty framed box for a preview; the caller fills it.
function W.Box(p, h)
  local c = Cur(p)
  local f = CreateFrame("Frame", nil, c.parent)
  f:SetWidth(c.width)
  f:SetHeight(h)
  W.Flat(f, C.field, 0.9, C.line)
  return Put(c, f, 0, 6)
end

-- ---------------------------------------------------------------- switches

-- An ON / OFF toggle with its word beside it (green ON, grey OFF).
function W.Switch(parent, get, set, tip)
  local f = CreateFrame("Frame", nil, parent)
  f:SetWidth(64)
  f:SetHeight(18)
  local tg = W.Toggle(f)
  tg:SetPoint("RIGHT", f, "RIGHT", 0, 0)
  local word = W.Font(f:CreateFontString(nil, "OVERLAY"), 11)
  word:SetPoint("RIGHT", tg, "LEFT", -6, 0)
  function f.Refresh()
    local on = get() and true or false
    tg.Set(on)
    word:SetText(on and "ON" or "OFF")
    if on then word:SetTextColor(C.on[1] + 0.15, C.on[2] + 0.15, C.on[3] + 0.15) else word:SetTextColor(C.dim[1], C.dim[2], C.dim[3]) end
  end
  tg:SetScript("OnClick", function()
    set(not get())
    f.Refresh()
    if B.Options then B.Options:Refresh() end
  end)
  W.Tip(tg, "On / off", tip)
  f.toggle = tg
  return f
end

-- A line of small tick boxes: { { label, get, set, tip }, ... }
function W.Toggles(p, list)
  local row = W.Row(p, 22, 0, 4)
  local x = 0
  for i = 1, table.getn(list) do
    local d = list[i]
    local cb = W.CheckBox(row, 14)
    cb:SetPoint("LEFT", row, "LEFT", x, 0)
    local fs = W.Font(row:CreateFontString(nil, "OVERLAY"), 11, C.dim[1], C.dim[2], C.dim[3])
    fs:SetPoint("LEFT", cb, "RIGHT", 6, 0)
    fs:SetText(d[1])
    cb.get, cb.set = d[2], d[3]
    cb:SetScript("OnClick", function()
      this.set(this:GetChecked() and true or false)
      if B.Options then B.Options:Refresh() end
    end)
    W.Tip(cb, d[1], d[4])
    Index(p, d[1], d[4], row)
    Track(p, { Refresh = function() cb:SetChecked(cb.get() and 1 or nil) end })
    x = x + 34 + (fs:GetStringWidth() or 60)
  end
  return row
end

-- ---------------------------------------------------------------- text

-- Page title with a thin line under it. o (all optional):
--   text  = the one-line summary under it
--   about = the long explanation, shown when hovering "How it works"
--   on    = { get, set, tip } - the feature's ON / OFF switch, top right
--   extra = { { label, get, set, tip }, ... } - tick boxes under the summary
function W.Heading(p, text, o)
  o = o or {}
  p.title = text
  local fs = W.Font(p.body:CreateFontString(nil, "OVERLAY"), 17, C.text[1], C.text[2], C.text[3])
  fs:SetText(text)
  Put(p, fs, 2, 6)
  if o.about then
    local h = CreateFrame("Button", nil, p.body)
    h:SetWidth(90)
    h:SetHeight(18)
    h:SetPoint("LEFT", fs, "RIGHT", 12, -1)
    local t = W.Font(h:CreateFontString(nil, "OVERLAY"), 11, C.accent[1], C.accent[2], C.accent[3])
    t:SetPoint("LEFT", h, "LEFT", 0, 0)
    t:SetText("How it works")
    W.Tip(h, text, o.about)
  end
  if o.on then
    local sw = W.Switch(p.body, o.on[1], o.on[2], o.on[3])
    sw:SetPoint("TOPRIGHT", p.body, "TOPRIGHT", -X - 2, -6)
    Track(p, { Refresh = sw.Refresh })
  end
  Index(p, text, o.text, fs)
  local line = W.Fill(p.body, C.line, 1, "ARTWORK")
  line:SetWidth(W.WIDTH - 2 * X)
  line:SetHeight(1)
  Put(p, line, 0, 8)
  if o.text then
    local n = W.Font(p.body:CreateFontString(nil, "OVERLAY"), 11, C.dim[1], C.dim[2], C.dim[3])
    n:SetWidth(W.WIDTH - 2 * X - 4)
    n:SetJustifyH("LEFT")
    n:SetJustifyV("TOP")
    n:SetSpacing(3)
    n:SetText(o.text)
    Put(p, n, 2, 8)
  end
  if o.extra then W.Toggles(p, o.extra) end
  return fs
end

-- A folding card. o (all optional):
--   folded = shut until opened (the open / shut state is remembered)
--   on     = { get, set, tip } - an ON / OFF switch in the card's bar
--   tip    = hover text for the bar
--   text   = one plain line at the top of the card: what it is for
-- Everything added after it goes inside, until the next card or W.Done.
function W.Card(p, title, o)
  o = o or {}
  p.cur = nil
  local card = CreateFrame("Frame", nil, p.body)
  card:SetWidth(W.WIDTH - 2 * X)
  card:SetHeight(CARD_HEAD)
  W.Flat(card, C.card, 1, C.line)
  Put(p, card, 0, (table.getn(p.cards) == 0) and 10 or 6)
  local head = CreateFrame("Button", nil, card)
  head:SetPoint("TOPLEFT", card, "TOPLEFT", 1, -1)
  head:SetPoint("TOPRIGHT", card, "TOPRIGHT", -1, -1)
  head:SetHeight(CARD_HEAD - 2)
  local bg = W.Fill(head, C.head, 1, "BACKGROUND")
  bg:SetAllPoints(head)
  Hover(head, 0.05)
  local icon = W.Arrow(head, 10, "down")
  icon:SetPoint("LEFT", head, "LEFT", 8, 0)
  local t = W.Font(head:CreateFontString(nil, "OVERLAY"), 12, C.text[1], C.text[2], C.text[3])
  t:SetPoint("LEFT", icon, "RIGHT", 7, 0)
  t:SetText(title)
  local inside = CreateFrame("Frame", nil, card)
  inside:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -CARD_TOP)
  inside:SetWidth(W.CW)
  inside:SetHeight(1)
  local c = { parent = inside, x0 = 0, y0 = 0, lastX = 0, width = W.CW, card = card, icon = icon,
              title = title, page = p, key = (p.key or "?") .. ":" .. title, default = not o.folded }
  if o.on then
    local sw = W.Switch(head, o.on[1], o.on[2], o.on[3])
    sw:SetPoint("RIGHT", head, "RIGHT", -8, 0)
    Track(p, { Refresh = sw.Refresh })
  end
  W.Tip(head, o.tip and title, o.tip)
  head.c = c
  head:SetScript("OnClick", function() W.SetOpen(this.c, not W.IsOpen(this.c)) end)
  table.insert(p.cards, c)
  Index(p, title, o.tip or o.text, head)
  p.cur = c
  W.ApplyCard(c)
  -- what the card is for, in one plain line at its top
  if o.text then
    local n = W.Note(p, o.text)
    n:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
    W.Space(p, 2)
  end
  return c
end
-- Older pages called their sections Sub.
W.Sub = W.Card

function W.IsOpen(c)
  local s = B.db.optCards and B.db.optCards[c.key]
  if s == nil then return c.default end
  return s
end

function W.ApplyCard(c)
  if W.IsOpen(c) then
    W.Turn(c.icon, "down")
    c.parent:Show()
    c.card:SetHeight(c.h and (CARD_TOP + c.h + 10) or CARD_HEAD)
  else
    W.Turn(c.icon, "right")
    c.parent:Hide()
    c.card:SetHeight(CARD_HEAD)
  end
end

function W.SetOpen(c, open)
  if not B.db.optCards then B.db.optCards = {} end
  B.db.optCards[c.key] = open and true or false
  W.ApplyCard(c)
  W.CloseMenus()
  W.Measure(c.page)
end

-- A paragraph: grey by default, white when bright is set. Height follows the text.
function W.Note(p, text, indent, bright)
  indent = indent or 0
  local c = Cur(p)
  local fs = W.Font(c.parent:CreateFontString(nil, "OVERLAY"), 11)
  fs:SetWidth(c.width - indent)
  fs:SetJustifyH("LEFT")
  fs:SetJustifyV("TOP")
  fs:SetSpacing(3)
  fs:SetText(text)
  if bright then fs:SetTextColor(C.text[1], C.text[2], C.text[3]) else fs:SetTextColor(C.dim[1], C.dim[2], C.dim[3]) end
  Put(c, fs, indent, (indent > 0) and 2 or 6)
  return fs
end

-- A line whose text comes from fn() each time the page is shown.
function W.Live(p, fn, lines)
  local c = Cur(p)
  local fs = W.Font(c.parent:CreateFontString(nil, "OVERLAY"), 11, C.text[1], C.text[2], C.text[3])
  fs:SetWidth(c.width)
  fs:SetJustifyH("LEFT")
  fs:SetJustifyV("TOP")
  fs:SetSpacing(3)
  fs:SetText(" ")
  Put(c, fs, 0, 6)
  Track(p, { Refresh = function() fs:SetText(fn()) end })
  return fs
end

-- ---------------------------------------------------------------- controls

-- The label of a whole-row control (text box, key binding).
local function Label(row, text)
  local fs = W.Font(row:CreateFontString(nil, "OVERLAY"), 12, C.text[1], C.text[2], C.text[3])
  fs:SetPoint("LEFT", row, "LEFT", 2, 0)
  fs:SetWidth(CTRL - 10)
  fs:SetHeight(26)            -- two lines at most; a longer label is cut, never spills
  fs:SetJustifyH("LEFT")
  fs:SetJustifyV("MIDDLE")
  fs:SetText(text)
  return fs
end

-- The label of a grid cell: one line along its top.
local function TopLabel(row, text, width)
  local fs = W.Font(row:CreateFontString(nil, "OVERLAY"), 12, C.text[1], C.text[2], C.text[3])
  fs:SetPoint("TOPLEFT", row, "TOPLEFT", 2, -1)
  fs:SetWidth(width)
  fs:SetHeight(14)
  fs:SetJustifyH("LEFT")
  fs:SetText(text)
  return fs
end

-- A mouse area over a label, for its tooltip.
local function HoverArea(row, fs, title, desc)
  if not desc then return end
  local h = CreateFrame("Frame", nil, row)
  h:SetPoint("TOPLEFT", fs, "TOPLEFT", -2, 2)
  h:SetPoint("BOTTOMRIGHT", fs, "BOTTOMRIGHT", 2, -2)
  h:EnableMouse(true)
  W.Tip(h, title, desc)
end

-- full: take the whole row (a label too long for half a row does by itself).
function W.Check(p, label, desc, get, set, full)
  local row, c = Cell(p, 22, full)
  local cb = W.CheckBox(row, 16)
  cb:SetPoint("LEFT", row, "LEFT", 2, 0)
  local fs = W.Font(row:CreateFontString(nil, "OVERLAY"), 12, C.text[1], C.text[2], C.text[3])
  fs:SetPoint("LEFT", cb, "RIGHT", 8, 0)
  fs:SetText(label)
  if not full and (fs:GetStringWidth() or 0) > HALF - 30 then full = true end
  row:SetWidth(full and c.width or HALF)
  local function Click()
    set(cb:GetChecked() and true or false)
    if B.Options then B.Options:Refresh() end
  end
  cb:SetScript("OnClick", Click)
  -- the label toggles too
  local hit = CreateFrame("Button", nil, row)
  hit:SetPoint("TOPLEFT", fs, "TOPLEFT", -2, 2)
  hit:SetPoint("BOTTOMRIGHT", fs, "BOTTOMRIGHT", 2, -2)
  hit:SetScript("OnClick", function()
    cb:SetChecked(not cb:GetChecked() and 1 or nil)
    Click()
  end)
  W.Tip(cb, label, desc)
  W.Tip(hit, label, desc)
  if full then Put(c, row, 0, 6) else PutHalf(c, row, 6) end
  Index(p, label, desc, row)
  Track(p, { Refresh = function() cb:SetChecked(get() and 1 or nil) end })
  return cb
end

local function Decimals(step)
  if step >= 1 then return 0 end
  if step >= 0.1 then return 1 end
  return 2
end

-- fmt: a function(value) -> text, or nil for a plain number
function W.Slider(p, label, desc, min, max, step, get, set, fmt)
  local row, c = Cell(p, 38)
  local lab = TopLabel(row, label, HALF - 64)
  local val = W.Font(row:CreateFontString(nil, "OVERLAY"), 12, C.accent[1], C.accent[2], C.accent[3])
  val:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -1)
  val:SetJustifyH("RIGHT")
  local s = W.SliderBar(row, HALF - 12, Name("Slider"))
  s:SetPoint("TOPLEFT", row, "TOPLEFT", 2, -19)
  s:SetMinMaxValues(min, max)
  s:SetValueStep(step)
  local dec = Decimals(step)
  local function Show(v)
    if fmt then val:SetText(fmt(v)) else val:SetText(string.format("%." .. dec .. "f", v)) end
    W.SliderPaint(s)
  end
  s:SetScript("OnValueChanged", function()
    if this.loading then return end
    local v = min + math.floor((this:GetValue() - min) / step + 0.5) * step
    if v > max then v = max end
    set(v)
    Show(v)
  end)
  W.Tip(s, label, desc)
  HoverArea(row, lab, label, desc)
  PutHalf(c, row, 6)
  Index(p, label, desc, row)
  Track(p, { Refresh = function()
    local v = get() or min
    s.loading = true
    s:SetValue(v)
    s.loading = nil
    Show(v)
  end })
  return s
end

-- A list menu; entries light up on hover. An option with a `font` is written
-- in that font (a font list shows what each looks like); an option with
-- `group` starts a heading line. More than MENU_ROWS lines wrap into further
-- columns so a long list stays on screen. Returns the menu.
local MENU_ROWS = 20
function W.Menu(anchor, options, width, onPick)
  local menu = CreateFrame("Frame", nil, UIParent)
  local n = table.getn(options)
  local cols = math.ceil(n / MENU_ROWS)
  local rows = math.min(n, MENU_ROWS)
  menu:SetWidth(width * cols)
  menu:SetFrameStrata("FULLSCREEN_DIALOG")
  menu:SetClampedToScreen(true)
  W.Flat(menu, C.card, 0.98, C.lineHi)
  menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
  menu:Hide()
  table.insert(W.menus, menu)
  for i = 1, n do
    local o = options[i]
    local col = math.floor((i - 1) / MENU_ROWS)
    local row = math.mod(i - 1, MENU_ROWS)
    local e = CreateFrame("Button", nil, menu)
    e:SetWidth(width - 8)
    e:SetHeight(17)
    e:SetPoint("TOPLEFT", menu, "TOPLEFT", 4 + col * width, -4 - row * 17)
    local t = W.Font(e:CreateFontString(nil, "OVERLAY"), 11, C.text[1], C.text[2], C.text[3])
    t:SetPoint("LEFT", e, "LEFT", 6, 0)
    t:SetWidth(width - 20)
    t:SetJustifyH("LEFT")
    if o.font then t:SetFont(o.font, 13, "") end   -- a font that fails keeps the one it had
    if o.group then t:SetTextColor(C.accent[1], C.accent[2], C.accent[3]) end
    t:SetText(o.label)
    if o.key ~= nil then
      local hl = e:CreateTexture(nil, "HIGHLIGHT")
      hl:SetAllPoints(e)
      hl:SetTexture(U.WHITE)
      hl:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.25)
      e.key = o.key
      e:SetScript("OnClick", function()
        menu:Hide()
        onPick(this.key)
      end)
    end
  end
  menu:SetHeight(rows * 17 + 8)
  return menu
end

-- A flat dropdown box with a small arrow. Returns the frame, its text, and
-- the button (twice: older callers wanted the arrow and the box apart).
function W.DropBox(parent, width)
  local f = CreateFrame("Button", nil, parent)
  f:SetWidth(width)
  f:SetHeight(20)
  W.Flat(f, C.field, 1, C.line)
  Hover(f, 0.05)
  local text = W.Font(f:CreateFontString(nil, "OVERLAY"), 11, C.text[1], C.text[2], C.text[3])
  text:SetPoint("LEFT", f, "LEFT", 7, 0)
  text:SetPoint("RIGHT", f, "RIGHT", -20, 0)
  text:SetJustifyH("LEFT")
  local arrow = W.Arrow(f, 9, "down")
  arrow:SetPoint("RIGHT", f, "RIGHT", -7, 0)
  return f, text, f, f
end

-- A compact dropdown for custom rows: options { { key, label } }.
function W.MiniDrop(parent, width, options, get, set, menuWidth)
  local f, text, btn, hit = W.DropBox(parent, width)
  local menu = W.Menu(f, options, menuWidth or math.max(width, 120), function(k)
    set(k)
    if B.Options then B.Options:Refresh() end
  end)
  local function Toggle()
    local open = menu:IsShown()
    W.CloseMenus()
    if not open then menu:Show() end
  end
  btn:SetScript("OnClick", Toggle)
  local function Refresh()
    local k = get()
    for i = 1, table.getn(options) do
      local o = options[i]
      if o.key == k then
        W.Font(text, 11, C.text[1], C.text[2], C.text[3])
        if o.font then text:SetFont(o.font, 12, "") end   -- the chosen font, as it will look
        text:SetText(o.label)
        return
      end
    end
    W.Font(text, 11, C.text[1], C.text[2], C.text[3])
    text:SetText(tostring(k))
  end
  return f, Refresh, hit
end

-- A key binding set right here: click, press a key (with Shift / Ctrl / Alt),
-- done - the same calls the game's key binding window makes (SetBinding,
-- SaveBindings(GetCurrentBindingSet()), Blizzard_BindingUI in patch-4).
-- Escape cancels, right-click clears.
local nkey = 0
local function KeyName(action)
  local k = GetBindingKey and GetBindingKey(action)
  return k or "Not set"
end
function W.KeyBind(p, label, desc, action)
  local row = W.Row(p, 26, 0, 6)
  local lab = Label(row, label)
  HoverArea(row, lab, label, desc)
  nkey = nkey + 1
  local b = W.Button(row, KeyName(action), 150, 22, Name("Key" .. nkey))
  b:SetPoint("LEFT", row, "LEFT", CTRL + 2, 0)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  local function Show()
    b:SetText(KeyName(action))
  end
  local function Stop()
    b.waiting = nil
    b:EnableKeyboard(false)
    W.Pick(b, false)
    b.label:SetTextColor(C.text[1], C.text[2], C.text[3])
    Show()
  end
  b:SetScript("OnClick", function()
    if arg1 == "RightButton" then
      local k1, k2 = GetBindingKey(action)
      if k1 then SetBinding(k1) end
      if k2 then SetBinding(k2) end
      SaveBindings(GetCurrentBindingSet and GetCurrentBindingSet() or 1)
      Stop()
      return
    end
    b.waiting = true
    b:EnableKeyboard(true)
    W.Pick(b, true)
    b:SetText("Press a key...")
  end)
  b:SetScript("OnKeyDown", function()
    if not this.waiting then return end
    local key = arg1
    if key == "ESCAPE" then Stop() return end
    if key == "SHIFT" or key == "CTRL" or key == "ALT" or key == "UNKNOWN" then return end
    if IsShiftKeyDown() then key = "SHIFT-" .. key end
    if IsControlKeyDown() then key = "CTRL-" .. key end
    if IsAltKeyDown() then key = "ALT-" .. key end
    local old = GetBindingAction(key)
    local k1, k2 = GetBindingKey(action)
    if k1 then SetBinding(k1) end
    if k2 then SetBinding(k2) end
    SetBinding(key, action)
    SaveBindings(GetCurrentBindingSet and GetCurrentBindingSet() or 1)
    if old and old ~= "" and old ~= action then
      B:Print(key .. " was \"" .. (GetBindingText and GetBindingText(old, "BINDING_NAME_") or old) .. "\" - it is now this key.")
    end
    Stop()
  end)
  b:SetScript("OnHide", function() if this.waiting then Stop() end end)
  W.Tip(b, label, (desc and (desc .. "\n\n") or "") .. "Click, then press the key you want (Shift, Ctrl and Alt work too). "
    .. "Escape cancels, right-click clears.")
  Index(p, label, desc, row)
  Track(p, { Refresh = Show })
  return b
end

-- options: { { key = ..., label = ... }, ... }
function W.Dropdown(p, label, desc, options, get, set)
  local row, c = Cell(p, 40)
  local lab = TopLabel(row, label, HALF - 8)
  HoverArea(row, lab, label, desc)
  local f, Refresh, hit = W.MiniDrop(row, HALF - 12, options, get, set, math.max(HALF - 12, 200))
  f:SetPoint("TOPLEFT", row, "TOPLEFT", 2, -18)
  W.Tip(hit, label, desc)
  PutHalf(c, row, 6)
  Index(p, label, desc, row)
  Track(p, { Refresh = Refresh })
  return f
end

-- A flat colour swatch; get() -> r, g, b, a.
function W.Swatch(parent, size)
  local sw = CreateFrame("Button", nil, parent)
  sw:SetWidth(size or 18)
  sw:SetHeight(size or 18)
  W.Flat(sw, C.field, 1, C.lineHi)
  local fill = sw:CreateTexture(nil, "ARTWORK")
  fill:SetTexture(U.WHITE)
  fill:SetPoint("TOPLEFT", sw, "TOPLEFT", 2, -2)
  fill:SetPoint("BOTTOMRIGHT", sw, "BOTTOMRIGHT", -2, 2)
  Hover(sw, 0.2)
  sw.fill = fill
  return sw
end

function W.Color(p, label, desc, get, set)
  local row, c = Cell(p, 22)
  local sw = W.Swatch(row, 16)
  sw:SetPoint("LEFT", row, "LEFT", 2, 0)
  local fs = W.Font(row:CreateFontString(nil, "OVERLAY"), 12, C.text[1], C.text[2], C.text[3])
  fs:SetPoint("LEFT", sw, "RIGHT", 8, 0)
  fs:SetText(label)
  local function Apply() sw.fill:SetVertexColor(get()) end
  sw:SetScript("OnClick", function()
    local r, g, b, a = get()
    ColorPickerFrame.func = function()
      local nr, ng, nb = ColorPickerFrame:GetColorRGB()
      set(nr, ng, nb, 1 - OpacitySliderFrame:GetValue())
      Apply()
    end
    ColorPickerFrame.opacityFunc = ColorPickerFrame.func
    ColorPickerFrame.cancelFunc = function()
      set(r, g, b, a)
      Apply()
    end
    ColorPickerFrame.hasOpacity = 1
    ColorPickerFrame.opacity = 1 - (a or 1)
    ColorPickerFrame:SetColorRGB(r, g, b)
    ColorPickerFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    ShowUIPanel(ColorPickerFrame)
  end)
  W.Tip(sw, label, desc or "Click to pick a colour.")
  PutHalf(c, row, 6)
  Index(p, label, desc, row)
  Track(p, { Refresh = Apply })
  return sw
end

-- list: { { text, fn, width, tip }, ... } in one row
function W.Buttons(p, list)
  local row = W.Row(p, 24, 0, 6)
  local x = 0
  for i = 1, table.getn(list) do
    local d = list[i]
    local b = W.Button(row, d[1], d[3] or 130, 22, Name("Btn"))
    b:SetPoint("LEFT", row, "LEFT", x, 0)
    b.fn = d[2]
    b:SetScript("OnClick", function()
      this.fn()
      if B.Options then B.Options:Refresh() end
    end)
    W.Tip(b, d[4] and d[1], d[4])
    Index(p, d[1], d[4], row)
    x = x + (d[3] or 130) + 6
  end
  return row
end

function W.Edit(p, label, desc, get, set, width)
  local row = W.Row(p, 26, 0, 6)
  local lab = Label(row, label)
  HoverArea(row, lab, label, desc)
  local eb = W.EditBox(row, math.min(width or 220, Cur(p).width - CTRL - 16), Name("Edit"))
  eb:SetPoint("LEFT", row, "LEFT", CTRL + 2, 0)
  eb:SetScript("OnEnterPressed", function()
    set(this:GetText())
    this:ClearFocus()
    if B.Options then B.Options:Refresh() end
  end)
  W.Tip(eb, label, (desc and (desc .. " ") or "") .. "Press Enter to save.")
  Index(p, label, desc, row)
  Track(p, { Refresh = function()
    if not eb.typing then eb:SetText(get() or "") end
  end })
  return eb
end

-- ---------------------------------------------------------------- search

-- A short glow over a region (a search result found on its page).
function W.Flash(region)
  local f = W.flash
  if not f then
    f = CreateFrame("Frame", nil, UIParent)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    W.Flat(f, C.accent, 0.18, C.accent)
    f:SetScript("OnUpdate", function()
      this.t = this.t - (arg1 or 0)
      if this.t <= 0 then this:Hide() else this:SetAlpha(math.min(1, this.t)) end
    end)
    W.flash = f
  end
  f:ClearAllPoints()
  f:SetPoint("TOPLEFT", region, "TOPLEFT", -4, 3)
  f:SetPoint("BOTTOMRIGHT", region, "BOTTOMRIGHT", 4, -3)
  f.t = 2
  f:SetAlpha(1)
  f:Show()
end

-- Index entries whose label, help, card or page title hold text.
function W.Find(text)
  local out = {}
  text = string.lower(text or "")
  if string.len(text) < 2 then return out end
  for i = 1, table.getn(W.index) do
    local e = W.index[i]
    local hay = string.lower(e.label .. " " .. (e.desc or "") .. " " .. (e.card and e.card.title or "") .. " " .. (e.page.title or ""))
    if string.find(hay, text, 1, true) then table.insert(out, e) end
  end
  return out
end
