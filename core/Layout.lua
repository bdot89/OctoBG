-- OctoBG :: moving panels (Arrange panels / Move frames)
-- In move mode every panel shows a blue box to drag. Hovering one opens a
-- small toolbar over it, so setting up needs no options page:
--   * On / Off   switches the feature (an off panel's box turns grey and
--                stays, so it can be switched back on)
--   * Size - +   the panel's own size (combat text areas: their text size)
--   * Opacity - + how see-through it is
--   * Reset      back to where it started, full size and opacity
--   * Options    that feature's options page
-- Mouse wheel over a box: size. Shift + wheel: opacity. Right-click: on / off.
-- The grip in a box's bottom right corner: drag to resize.
-- Sizes and opacities live in db.panels[key] = { scale, alpha }, except
-- where a feature already has its own setting (HUD, enemy list, cooldown
-- bars, combat text areas): then the toolbar changes that setting.

local B = OctoBG
local U = B.U
local L = {}
B.Layout = L

B.DEFAULTS.panels = {}

-- What each panel's switch, opacity and page are. (The combat text areas
-- moved to pfUI Octo with the combat text, 19 Oct 2026: /moveui there.)
L.INFO = {
  hud = { page = "hud", on = function() return B.db.hud.enabled end,
          set = function(v) B.db.hud.enabled = v B:RefreshActive() end,
          alpha = function(v)
            if v then
              B.db.hud.alpha = v
              if B.HUD then B.HUD:Layout() end
            end
            return B.db.hud.alpha
          end },
  list = { page = "list", on = function() return B.db.list.enabled end,
           set = function(v)
             B.db.list.enabled = v
             if B.Roster then B.Roster.closed = false B.Roster:Refresh() end
           end,
           alpha = function(v)
             if v then
               B.db.list.alpha = v
               B.db.list.alphaBG = v
               if B.Roster then B.Roster:Refresh() end
             end
             return B.db.list.alpha
           end },
  map = { page = "map", on = function() return B.db.map.enabled end, set = function(v) B.db.map.enabled = v end },
  flags = { page = "flags", on = function() return B.db.flags.enabled end,
            set = function(v)
              B.db.flags.enabled = v
              if B.Flags then B.Flags:Refresh() end
            end },
  timers = { page = "timers", on = function() return B.db.timers.enabled end, set = function(v) B.db.timers.enabled = v end },
  res = { page = "timers", on = function() return B.db.timers.big end, set = function(v) B.db.timers.big = v end },
  inc = { page = "inc", on = function() return B.db.inc.enabled end, set = function(v) B.db.inc.enabled = v end },
  cdbars = { page = "cdbars", on = function() return B.db.cd.bars end, set = function(v) B.db.cd.bars = v end,
             alpha = function(v)
               if v then B.db.cd.alpha = v end
               return B.db.cd.alpha
             end },
  focus = { page = "focus", on = function() return B.db.focus.strip end, set = function(v) B.db.focus.strip = v end },
  avbutton = { page = "tidy", on = function() return B.db.avmode.button end,
               set = function(v)
                 B.db.avmode.button = v
                 if B.BGTidy then B.BGTidy:PaintButton() end
               end },
}

local function Info(f) return L.INFO[f.key] or {} end

local function Cfg(f)
  local p = B.db.panels[f.key]
  if not p then
    p = { scale = 1, alpha = 1 }
    B.db.panels[f.key] = p
  end
  return p
end

-- Opacity of panels without a setting of their own (the panel frame itself).
function L:ApplyAlpha(f)
  if Info(f).alpha then return end
  f:SetAlpha(Cfg(f).alpha or 1)
end

function L:Alpha(f, v)
  local info = Info(f)
  if info.alpha then return info.alpha(v) end
  local p = Cfg(f)
  if v then
    p.alpha = v
    self:ApplyAlpha(f)
  end
  return p.alpha or 1
end

function L:Size(f, d)
  local info = Info(f)
  if info.size then return info.size(d) end
  local p = Cfg(f)
  if d then
    p.scale = math.max(0.5, math.min(2, math.floor(((p.scale or 1) + d * 0.05) * 100 + 0.5) / 100))
    f:SetScale(U.PanelScale(f))
  end
  return math.floor((p.scale or 1) * 100 + 0.5) .. "%"
end

function L:IsOn(f)
  local info = Info(f)
  if info.on then return info.on() and true or false end
  return true
end

-- Grey box and "(off)" for panels switched off; blue when on.
function L:Paint(f)
  local hd = f.handle
  if self:IsOn(f) then
    hd:SetBackdropColor(0.1, 0.45, 0.9, 0.3)
    hd:SetBackdropBorderColor(0.3, 0.7, 1, 1)
    hd.text:SetText(f.label)
    hd.text:SetTextColor(1, 1, 1)
  else
    hd:SetBackdropColor(0.25, 0.25, 0.25, 0.35)
    hd:SetBackdropBorderColor(0.55, 0.55, 0.55, 1)
    hd.text:SetText(f.label .. " |cffaaaaaa(off)|r")
    hd.text:SetTextColor(0.7, 0.7, 0.7)
  end
end

function L:PaintAll()
  for i = 1, table.getn(U.panels) do self:Paint(U.panels[i]) end
end

function U.TogglePanel(f)
  local info = Info(f)
  if not info.set then return end
  info.set(not L:IsOn(f))
  L:Paint(f)
  L:Fill()
  if B.Options then B.Options:Refresh() end
end

function U.WheelPanel(f, delta)
  if IsShiftKeyDown() then
    local a = L:Alpha(f)
    L:Alpha(f, math.max(0.1, math.min(1, math.floor((a + delta * 0.05) * 100 + 0.5) / 100)))
  else
    L:Size(f, delta)
  end
  L:Fill()
  if B.Options then B.Options:Refresh() end
end

function L:Reset(f)
  local info = Info(f)
  B.db.pos[f.key] = nil
  if info.reset then
    info.reset()
  else
    local p = Cfg(f)
    p.scale, p.alpha = 1, 1
    f:SetScale(U.PanelScale(f))
    self:ApplyAlpha(f)
    if info.alpha then info.alpha(1) end
    U.RestorePos(f)
  end
  self:Fill()
  if B.Options then B.Options:Refresh() end
end

-- ---------------------------------------------------------------- resize grip

-- Dragging a box's corner grip: right / down = bigger. Panels with a size
-- setting of their own (combat text areas: text size) step it every 12 px;
-- the rest scale, with their top left corner kept where it is.
local gripper
function U.GripStart(f)
  local hd = f.handle
  local l, r = hd:GetLeft(), hd:GetRight()
  local cx, cy = GetCursorPosition()
  if not l or not r or not cx then return end
  local w = (r - l) * hd:GetEffectiveScale()
  L.grip = { f = f, x = cx, y = cy, w = math.max(20, w), scale = Cfg(f).scale or 1, steps = 0 }
  if not gripper then
    gripper = CreateFrame("Frame", nil, UIParent)
    gripper:SetScript("OnUpdate", function() L:GripTick() end)
  end
  gripper:Show()
end

function L:GripTick()
  local g = self.grip
  if not g then
    gripper:Hide()
    return
  end
  local cx, cy = GetCursorPosition()
  if not cx then return end
  local amount = ((cx - g.x) + (g.y - cy)) / 2     -- right and down make it bigger
  local f = g.f
  if Info(f).size then
    local steps = math.floor(amount / 12 + 0.5)
    if steps ~= g.steps then
      self:Size(f, steps - g.steps)
      g.steps = steps
      self:Fill()
    end
    return
  end
  local s = math.max(0.5, math.min(2, math.floor(g.scale * (g.w + amount) / g.w * 100 + 0.5) / 100))
  local p = Cfg(f)
  if s == p.scale then return end
  -- keep the top left corner in place while the scale changes
  local left, top, eff = f:GetLeft(), f:GetTop(), f:GetEffectiveScale()
  p.scale = s
  f:SetScale(U.PanelScale(f))
  if left and top then
    local ne = f:GetEffectiveScale()
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left * eff / ne, top * eff / ne)
  end
  self:Fill()
end

function U.GripStop()
  local g = L.grip
  L.grip = nil
  if gripper then gripper:Hide() end
  if not g then return end
  if not Info(g.f).size then U.SavePos(g.f) end
  L:Fill()
  if B.Options then B.Options:Refresh() end
end

-- ---------------------------------------------------------------- the toolbar

local nbtn = 0
local function SmallButton(parent, text, w, tip, fn)
  nbtn = nbtn + 1
  local b = B.W.Button(parent, text, w, 18, "OctoBGMoveBarButton" .. nbtn)
  b.tip, b.fn = tip, fn
  b:SetScript("OnClick", function() this.fn() end)
  b:SetScript("OnEnter", function()
    if not this.tip then return end
    GameTooltip:SetOwner(this, "ANCHOR_TOP")
    GameTooltip:AddLine(this.tip, 1, 1, 1, 1)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return b
end

local function PlusMinus(parent, plus, fn)
  local b = B.W.Button(parent, plus and "+" or "-", 18, 16)
  b:SetScript("OnClick", fn)
  return b
end

function L:Build()
  local W = B.W
  local C = W.C
  local t = CreateFrame("Frame", "OctoBGMoveBar", UIParent)
  t:SetWidth(300)
  t:SetHeight(74)
  t:SetFrameStrata("FULLSCREEN_DIALOG")
  t:EnableMouse(true)
  W.Flat(t, C.bg, 0.96, C.lineHi)
  t:Hide()
  self.bar = t
  t.name = W.Font(t:CreateFontString(nil, "OVERLAY"), 12, C.accent[1], C.accent[2], C.accent[3])
  t.name:SetPoint("TOPLEFT", t, "TOPLEFT", 10, -9)
  t.name:SetWidth(150)
  t.name:SetJustifyH("LEFT")
  t.onoff = SmallButton(t, "Off", 50, "Switch this panel off (or on again). Same as right-clicking the box.",
    function() U.TogglePanel(L.target) end)
  t.onoff:SetPoint("TOPRIGHT", t, "TOPRIGHT", -72, -6)
  t.opt = SmallButton(t, "Options", 62, "Open this feature's options page.", function()
    local page = Info(L.target).page
    if B.Options and page then B.Options:Open(page) end
  end)
  t.opt:SetPoint("TOPRIGHT", t, "TOPRIGHT", -8, -6)

  -- size and opacity
  local sl = W.Font(t:CreateFontString(nil, "OVERLAY"), 11, C.text[1], C.text[2], C.text[3])
  sl:SetPoint("TOPLEFT", t, "TOPLEFT", 10, -33)
  sl:SetText("Size")
  local sm = PlusMinus(t, false, function() L:Size(L.target, -1) L:Fill() end)
  sm:SetPoint("LEFT", sl, "RIGHT", 6, 0)
  t.size = W.Font(t:CreateFontString(nil, "OVERLAY"), 11, C.accent[1], C.accent[2], C.accent[3])
  t.size:SetPoint("LEFT", sm, "RIGHT", 2, 0)
  t.size:SetWidth(40)
  local sp = PlusMinus(t, true, function() L:Size(L.target, 1) L:Fill() end)
  sp:SetPoint("LEFT", t.size, "RIGHT", 2, 0)
  local al = W.Font(t:CreateFontString(nil, "OVERLAY"), 11, C.text[1], C.text[2], C.text[3])
  al:SetPoint("LEFT", sp, "RIGHT", 14, 0)
  al:SetText("Opacity")
  local am = PlusMinus(t, false, function()
    L:Alpha(L.target, math.max(0.1, L:Alpha(L.target) - 0.1))
    L:Fill()
  end)
  am:SetPoint("LEFT", al, "RIGHT", 6, 0)
  t.alpha = W.Font(t:CreateFontString(nil, "OVERLAY"), 11, C.accent[1], C.accent[2], C.accent[3])
  t.alpha:SetPoint("LEFT", am, "RIGHT", 2, 0)
  t.alpha:SetWidth(36)
  local ap = PlusMinus(t, true, function()
    L:Alpha(L.target, math.min(1, L:Alpha(L.target) + 0.1))
    L:Fill()
  end)
  ap:SetPoint("LEFT", t.alpha, "RIGHT", 2, 0)
  t.reset = SmallButton(t, "Reset", 50, "Back to where it started, full size and opacity.", function() L:Reset(L.target) end)
  t.reset:SetPoint("TOPRIGHT", t, "TOPRIGHT", -8, -29)
  local hint = W.Font(t:CreateFontString(nil, "OVERLAY"), 9, C.dim[1], C.dim[2], C.dim[3])
  hint:SetPoint("BOTTOMLEFT", t, "BOTTOMLEFT", 10, 9)
  hint:SetText("Drag: move   Corner: resize   Wheel: size   Shift+wheel: opacity   Right-click: on/off")

  -- stays while the mouse is over the box or the toolbar
  t:SetScript("OnUpdate", function()
    local f = L.target
    if not f or B.db.locked then
      this:Hide()
      return
    end
    if MouseIsOver(this) or MouseIsOver(f.handle) then
      this.away = 0
    else
      this.away = (this.away or 0) + arg1
      if this.away > 0.35 then this:Hide() end
    end
  end)
end

function L:Fill()
  local t, f = self.bar, self.target
  if not t or not f or not t:IsShown() then return end
  local on = self:IsOn(f)
  t.name:SetText(f.label .. (on and "" or " |cffaaaaaa(off)|r"))
  t.onoff:SetText(on and "Off" or "On")
  if Info(f).set then t.onoff:Show() else t.onoff:Hide() end
  if Info(f).page then t.opt:Show() else t.opt:Hide() end
  t.size:SetText(self:Size(f))
  t.alpha:SetText(math.floor(self:Alpha(f) * 100 + 0.5) .. "%")
end

function U.HoverPanel(f)
  if B.db.locked then return end
  if not L.bar then L:Build() end
  local t = L.bar
  L.target = f
  t.away = 0
  t:ClearAllPoints()
  -- above the box, or below it near the top of the screen
  local top, screen = f.handle:GetTop(), UIParent:GetTop()
  if top and screen and top * f.handle:GetEffectiveScale() > screen * UIParent:GetEffectiveScale() - 90 then
    t:SetPoint("TOP", f.handle, "BOTTOM", 0, -2)
  else
    t:SetPoint("BOTTOM", f.handle, "TOP", 0, 2)
  end
  t:Show()
  L:Fill()
end

-- ---------------------------------------------------------------- setup

B:On("OBG_LAYOUT", function(ev, on)
  if on then L:PaintAll() elseif L.bar then L.bar:Hide() end
end)

-- switched on / off somewhere else (options, minimap): keep the boxes honest
B:Every(0.5, function()
  if B.test then L:PaintAll() end
end)

-- panel opacities once every panel exists (OBG_INIT runs the builders first)
B:On("PLAYER_ENTERING_WORLD", function()
  for i = 1, table.getn(U.panels) do L:ApplyAlpha(U.panels[i]) end
end)
