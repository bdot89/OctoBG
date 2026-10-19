-- OctoBG :: enemy list (Spy's Nearby window and the battleground roster)
-- One window for every enemy, in four modes (arrows in the title bar, or
-- Alt + mouse wheel over it, as in Spy):
--   Nearby        open world: Spy's list - enemies detected now (bright) and
--                 the ones no longer seen (greyed, for "Remove undetected
--                 after"), Kill On Sight first. In a battleground: the whole
--                 enemy team from the scoreboard - seen first, then out of
--                 sight, then the dead with the seconds to their next
--                 resurrection wave.
--   Last hour     everyone detected in the last 60 minutes
--   Kill On Sight / Ignore   the two lists, newest first
-- Each row: level (difficulty colour), name in class colour over a health
-- bar, a skull for Kill On Sight / a flag on the enemy flag carrier, what
-- they cast (else up to three cooldowns they used), xN = how many of your
-- group target them, a line-of-sight dot and the distance (light blue when a
-- teammate's OctoBG reports it). Damage they take shows as numbers on the row.
-- Left-click: target. Shift-click: Kill On Sight. Ctrl-click: ignore.
-- Alt-click: focus. Right-click: menu (announce, reasons, lists, focus).
-- Hover: everything OctoBG knows - Spy's record and the cooldowns.

local B = OctoBG
local U = B.U
local R = { rows = {}, list = {}, pool = {}, byName = {}, inScore = {}, onTarget = {}, cds = {}, drs = {},
            seen = {}, closed = false }
B.Roster = R

local MAX_ROWS, TITLE_H = 40, 18
local NAME_MIN = 56   -- px a name always keeps (about 11 narrow letters)
local RIGHT_W = 52    -- the right end of a row: "x2", sight dot, distance
local MODES = { "Nearby", "Last hour", "Ignore", "Kill On Sight" }   -- Spy's order
R.MODES = MODES

-- ---------------------------------------------------------------- data

local function SortKey(a, b, how)
  if how == "range" then
    if (a.dist ~= nil) ~= (b.dist ~= nil) then return a.dist ~= nil, true end
    if a.dist and b.dist and a.dist ~= b.dist then return a.dist < b.dist, true end
  elseif how == "class" then
    local ca, cb = a.class or "ZZZ", b.class or "ZZZ"
    if ca ~= cb then return ca < cb, true end
  elseif how == "time" then
    if a.order ~= b.order then return a.order > b.order, true end
  end
  return false, false
end

local sortHow, kosFirst = "range", true
local function Order(a, b)
  if kosFirst and a.kos ~= b.kos then return a.kos end
  if a.rank ~= b.rank then return a.rank < b.rank end
  local r, decided = SortKey(a, b, sortHow)
  if decided then return r end
  return a.name < b.name
end

local function ByTime(a, b)
  if a.rank ~= b.rank then return a.rank < b.rank end
  if a.t ~= b.t then return a.t > b.t end
  return a.name < b.name
end

function R:Entry(n, name)
  local e = self.pool[n]
  if not e then
    e = {}
    self.pool[n] = e
  end
  e.name, e.u, e.class, e.level, e.dist, e.team, e.t, e.order = name, nil, nil, nil, nil, nil, 0, 0
  e.rank, e.kos, e.dead, e.source = 2, false, nil, nil
  self.list[n] = e
  return e
end

-- Fill from a tracker unit (or Spy's record when the unit is unknown).
function R:Fill(e, u, now)
  local P = B.People
  local r = P:Get(e.name)
  e.u = u
  e.kos = P:IsKOS(e.name)
  e.class = (u and u.class) or e.class or (r and r.class)
  e.level = (u and u.level) or (r and r.level)
  e.team = u and not u.visible and u.teamAt and now - u.teamAt < B.Tracker.TEAM_FRESH and true or nil
  if u and u.dead then
    e.rank = 3
  elseif u and (u.visible or e.team) then
    e.rank = 1
  end
  e.dist = (e.rank == 1 and u) and u.dist or nil
end

function R:CollectNearby(now)
  local NB, T = B.Nearby, B.Tracker
  local seen, n = self.seen, 0
  for k in pairs(seen) do seen[k] = nil end
  local layer = NB:LayerOn()
  local P = B.People
  -- Spy's list (open world and, by choice, battlegrounds outside the roster)
  if layer then
    for name in pairs(NB.nearby) do
      n = n + 1
      local e = self:Entry(n, name)
      seen[name] = true
      self:Fill(e, T:FindByName(name), now)
      if e.rank ~= 1 and NB.active[name] then e.rank = 1 end
      if NB.dead[name] then e.rank = 3 end
      e.order = NB.first[name] or 0
      e.source = NB.comm[name] and NB.comm[name].source
    end
  end
  -- what the tracker sees and Spy does not list (layout samples, HUD-only world mode)
  for _, u in pairs(T.units) do
    if u.name and not seen[u.name] and (u.fake or u.visible or (u.teamAt and now - u.teamAt < T.TEAM_FRESH))
       and not P:IsIgnored(u.name) and (not layer or u.fake or NB:Wanted(u)) then
      n = n + 1
      local e = self:Entry(n, u.name)
      seen[u.name] = true
      self:Fill(e, u, now)
      e.order = 100000 + math.floor(u.first or 0)
    end
  end
  return n
end

-- The battleground roster: the scoreboard merged with the tracker by name.
function R:CollectRoster(now)
  local T = B.Tracker
  local inScore, n = self.inScore, 0
  for k in pairs(inScore) do inScore[k] = nil end
  local enemyFac = (B.faction == "Horde") and 1 or 0     -- scoreboard: 0 Horde, 1 Alliance
  for i = 1, GetNumBattlefieldScores() do
    local name, _, _, _, _, fac, _, _, class = GetBattlefieldScore(i)
    if name and fac == enemyFac and not inScore[name] then
      inScore[name] = true
      n = n + 1
      local e = self:Entry(n, name)
      e.class = U.ClassToken(class)
      self:Fill(e, T:FindByName(name), now)
    end
  end
  for _, u in pairs(T.units) do
    if u.name and not inScore[u.name] then
      n = n + 1
      local e = self:Entry(n, u.name)
      self:Fill(e, u, now)
    end
  end
  return n
end

-- Last hour / Ignore / Kill On Sight: names with a time.
function R:CollectNames(names, now)
  local T = B.Tracker
  local n = 0
  for name, t in pairs(names) do
    n = n + 1
    local e = self:Entry(n, name)
    e.t = t or 0
    local u = T:FindByName(name)
    self:Fill(e, (u and (u.visible or u.fake)) and u or nil, now)
    if e.rank == 3 then e.rank = 2 end
  end
  return n
end

function R:Roster()
  return B:IsBG() and B.db.list.roster and B.db.list.mode == 1
end

function R:Collect()
  local now = GetTime()
  local db = B.db.list
  local onTarget = self.onTarget
  for k in pairs(onTarget) do onTarget[k] = nil end
  -- what your group targets (in a raid "raidN" includes you)
  local nr = GetNumRaidMembers()
  local prefix, count = "raid", nr
  if nr == 0 then prefix, count = "party", GetNumPartyMembers() end
  for i = 1, count do
    local g = U.GuidOf(prefix .. i .. "target")
    if g then onTarget[g] = (onTarget[g] or 0) + 1 end
  end
  if nr == 0 then
    local g = U.GuidOf("target")
    if g then onTarget[g] = (onTarget[g] or 0) + 1 end
  end

  local mode, n = db.mode, 0
  if mode == 2 then
    n = self:CollectNames(B.Nearby.lastHour, now)
  elseif mode == 3 then
    n = self:CollectNames(B.People:IgnoreList(), now)
  elseif mode == 4 then
    n = self:CollectNames(B.People:KOSList(), now)
  elseif self:Roster() then
    n = self:CollectRoster(now)
  else
    n = self:CollectNearby(now)
  end
  for i = table.getn(self.list), n + 1, -1 do self.list[i] = nil end
  if mode == 1 then
    sortHow = B.zone and db.sortBG or db.sortWorld
    kosFirst = B.db.spy.PrioritiseKoS
    table.sort(self.list, Order)
  else
    table.sort(self.list, ByTime)
  end
  return n
end

-- The scoreboard only refreshes on request (it also gives the flag rows their classes).
B:Every(10, function()
  if B:IsBG() then RequestBattlefieldScoreData() end
end, true)

-- ---------------------------------------------------------------- tooltip

local function Line(text, r, g, b)
  GameTooltip:AddLine(text, r or 1, g or 1, b or 1)
end

-- Everything known about an enemy: Spy's record and OctoBG's live data.
-- Also used by the enemy map's hover.
function R:Tooltip(name, u, owner, anchor)
  local P, CD = B.People, B.CD
  local spy = B.db.spy
  local r = P:Get(name)
  local guid = u and u.guid
  if owner then GameTooltip:SetOwner(owner, anchor or "ANCHOR_LEFT") end
  local class = (u and u.class) or (r and r.class)
  local cr, cg, cb = U.ClassColor(class)
  Line(name, cr, cg, cb)
  if r and r.guild and r.guild ~= "" then Line("<" .. r.guild .. ">", 1, 1, 1)
  elseif u and u.guild then Line("<" .. u.guild .. ">", 1, 1, 1) end
  local level = (u and u.level) or (r and r.level)
  local race = (u and u.race) or (r and r.race)
  local desc = ""
  if level then desc = "Level " .. ((level == 0) and "??" or level) .. " " end
  if race then desc = desc .. race .. " " end
  if class then desc = desc .. (P.CLASS_NAME[class] or class) end
  if desc ~= "" then Line(desc, 0.85, 0.85, 0.85) end
  -- live state
  local info = {}
  if u and u.dead then
    table.insert(info, "dead")
  elseif u and u.visible then
    if u.hp and u.hpmax and u.hpmax > 0 then table.insert(info, math.floor(u.hp / u.hpmax * 100 + 0.5) .. "% health") end
    if u.dist then table.insert(info, math.floor(u.dist) .. " yd") end
    if u.los ~= nil then table.insert(info, u.los and "in sight" or "no line of sight") end
    if u.pvp == false then table.insert(info, "not PvP flagged") end
  elseif u and u.teamAt and GetTime() - u.teamAt < B.Tracker.TEAM_FRESH then
    if u.hp then table.insert(info, u.hp .. "% health") end
    if u.dist then table.insert(info, math.floor(u.dist) .. " yd") end
    table.insert(info, "seen by " .. (u.teamBy or "a teammate"))
  else
    table.insert(info, "not in sight")
  end
  local t = guid and self.onTarget[guid]
  if t then table.insert(info, t .. " of your group on them") end
  Line(table.concat(info, ", "), 0.8, 0.8, 0.8)
  if B.Nearby.comm[name] then Line("Reported by " .. B.Nearby.comm[name].source, 0.4, 1, 0.4) end
  if guid then
    local spell, _, _, rem = B.Casts:Get(guid)
    if spell then Line("Casting " .. spell .. " (" .. string.format("%.1f", rem) .. " s)", 1, 0.75, 0.15) end
    local left, imm = CD:ImmuneLeft(guid)
    if left then Line(imm .. " - immune for " .. CD.Time(left), 1, 0.82, 0.1) end
    local list = CD:GetActiveCooldowns(guid)
    if table.getn(list) > 0 then
      Line("Cooldowns", 1, 0.82, 0)
      for i = 1, table.getn(list) do
        GameTooltip:AddDoubleLine("  " .. list[i].spellName, CD.Time(list[i].remaining), 1, 1, 1, 1, 1, 1)
      end
    end
    local n = B.db.cd.showDR and CD:CollectDR(guid, self.drs) or 0
    if n > 0 then
      Line("Diminishing returns (next CC)", 1, 0.82, 0)
      for i = 1, n do
        local d = self.drs[i]
        GameTooltip:AddDoubleLine("  " .. d.label .. " " .. CD.FormatDR(d.multiplier), CD.Time(d.remaining) .. " to reset",
          d.r, d.g, d.b, 0.7, 0.7, 0.7)
      end
    end
  end
  -- Spy's record
  if r and spy.DisplayWinLossStatistics then
    Line("|cff40ff00Wins: " .. (r.wins or 0) .. "|r  |cff0070ddLosses: " .. (r.loses or 0) .. "|r")
  end
  if P:IsKOS(name) then
    Line("Kill On Sight", 1, 0.2, 0.2)
    local why = spy.DisplayKOSReason and P:ReasonText(name)
    if why then Line("    " .. why, 1, 0.2, 0.2) end
  end
  if P:IsIgnored(name) then Line("Ignored", 0.6, 0.6, 0.6) end
  if r and spy.DisplayLastSeen then
    if r.time then Line("Last seen " .. P.LastSeen(r.time), 1, 0.82, 0) end
    local loc = P:Location(r)
    if loc then Line(loc, 1, 0.82, 0) end
  end
  return true
end

local function RowTooltip()
  local e = this.entry
  if not e then return end
  local db = B.db.list
  if db.tipNear then
    GameTooltip:SetOwner(this, db.tipAnchor or "ANCHOR_LEFT")
  else
    GameTooltip_SetDefaultAnchor(GameTooltip, this)
  end
  R:Tooltip(e.name, e.u)
  GameTooltip:AddLine("Click: target  Shift: Kill On Sight  Ctrl: ignore  Alt: focus  Right: menu", 0.4, 0.8, 0.4)
  GameTooltip:Show()
end

-- ---------------------------------------------------------------- actions

function R:Target(name, u)
  local guid = u and not u.fake and u.guid
  if not U.TargetGuidOrName(guid, name) then
    UIErrorsFrame:AddMessage(name .. " is out of range", 1, 0.3, 0.2)
  end
end

function R:Focus(name, u)
  local guid = u and not u.fake and u.guid
  if not guid then
    local r = B.People:Get(name)
    guid = r and U.IsGuid(r.guid) and r.guid
  end
  if guid then
    B.Focus:Set(guid, name)
  else
    UIErrorsFrame:AddMessage(name .. " has not been close yet - focus needs to have seen them once", 1, 0.3, 0.2)
  end
end

-- ---------------------------------------------------------------- menu

local menuName, menuUnit
local function Add(info, level)
  UIDropDownMenu_AddButton(info, level)
end

local function MenuInit(level)
  level = level or 1
  local name, P = menuName, B.People
  if not name then return end
  local D = B.SpyData
  if level == 1 then
    Add({ text = name, isTitle = 1, notCheckable = 1 }, 1)
    Add({ text = "Target", notCheckable = 1, func = function() R:Target(name, menuUnit) end }, 1)
    Add({ text = "Set as focus", notCheckable = 1, func = function() R:Focus(name, menuUnit) end }, 1)
    Add({ text = "Announce", notCheckable = 1, hasArrow = 1, value = { key = "announce" } }, 1)
    if P:IsKOS(name) then
      Add({ text = "Kill On Sight reason", notCheckable = 1, hasArrow = 1, value = { key = "reasons" } }, 1)
      Add({ text = "Remove from Kill On Sight", notCheckable = 1, func = function() P:SetKOS(name, false) end }, 1)
    else
      Add({ text = "Add to Kill On Sight", notCheckable = 1, func = function() P:SetKOS(name, true) end }, 1)
    end
    if P:IsIgnored(name) then
      Add({ text = "Remove from ignore list", notCheckable = 1, func = function() P:SetIgnored(name, false) end }, 1)
    else
      Add({ text = "Add to ignore list", notCheckable = 1, func = function() P:SetIgnored(name, true) end }, 1)
    end
    if B.db.list.mode == 1 and B.Nearby.nearby[name] then
      Add({ text = "Remove from this list", notCheckable = 1, func = function() B.Nearby:Remove(name) end }, 1)
    end
  elseif level == 2 then
    local v = UIDROPDOWNMENU_MENU_VALUE
    if type(v) ~= "table" then return end
    if v.key == "announce" then
      local chans = { { "Party", "PARTY" }, { "Raid", "RAID" }, { "Guild", "GUILD" },
                      { "Battleground", "BATTLEGROUND" }, { "LocalDefense", "LOCAL" } }
      for i = 1, table.getn(chans) do
        local c = chans[i]
        Add({ text = c[1], notCheckable = 1, func = function() P:AnnounceTo(name, c[2]) end }, 2)
      end
    elseif v.key == "reasons" then
      for i = 1, table.getn(D.KOS_REASONS) do
        Add({ text = D.KOS_REASONS[i].title, notCheckable = 1, hasArrow = 1, value = { key = "reason", index = i } }, 2)
      end
      Add({ text = D.OTHER, notCheckable = 1, func = function() P:AskReason(name) end }, 2)
      Add({ text = "Clear reasons", notCheckable = 1, func = function() P:SetReason(name, nil) end }, 2)
    end
  elseif level == 3 then
    local v = UIDROPDOWNMENU_MENU_VALUE
    if type(v) ~= "table" or v.key ~= "reason" then return end
    local cat = D.KOS_REASONS[v.index]
    local r = P:Get(name)
    for i = 1, table.getn(cat.content) do
      local reason = cat.content[i]
      Add({ text = reason, checked = (r and r.reason and r.reason[reason]) and 1 or nil, keepShownOnClick = 1,
            func = function() P:SetReason(name, reason) end }, 3)
    end
  end
end

-- The same menu for the enemy map and the statistics window.
function R:Menu(name, u, anchor)
  if not name then return end
  menuName, menuUnit = name, u
  if not self.menu then self.menu = CreateFrame("Frame", "OctoBGEnemyMenu", UIParent, "UIDropDownMenuTemplate") end
  UIDropDownMenu_Initialize(self.menu, MenuInit, "MENU")
  ToggleDropDownMenu(1, nil, self.menu, anchor or "cursor", 0, 0)
end

local function RowClick()
  local e = this.entry
  if not e then return end
  local P = B.People
  if arg1 == "RightButton" then
    R:Menu(e.name, e.u)
  elseif IsShiftKeyDown() then
    P:ToggleKOS(e.name)
  elseif IsControlKeyDown() then
    P:ToggleIgnore(e.name)
  elseif IsAltKeyDown() then
    R:Focus(e.name, e.u)
  else
    R:Target(e.name, e.u)
  end
end

-- ---------------------------------------------------------------- frame

local function Icon(parent, file, tip, fn)
  local b = CreateFrame("Button", nil, parent)
  b:SetWidth(14)
  b:SetHeight(14)
  b:SetNormalTexture(U.MEDIA .. file)
  b:SetHighlightTexture(U.MEDIA .. "button-highlight")
  b.tip, b.fn = tip, fn
  b:SetScript("OnClick", function() this.fn() end)
  b:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_TOP")
    GameTooltip:AddLine(this.tip[1])
    if this.tip[2] then GameTooltip:AddLine(this.tip[2], 1, 1, 1, 1) end
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return b
end

function R:PostCount()
  local n = 0
  if self:Roster() then
    for i = 1, table.getn(self.list) do
      if self.list[i].rank == 1 then n = n + 1 end
    end
  else
    n = B.Nearby:ActiveCount()
  end
  local msg = "Nearby enemy players: " .. n
  if B:IsBG() then
    U.SendBG(msg)
  elseif GetNumRaidMembers() > 0 then
    SendChatMessage(msg, "RAID")
  elseif GetNumPartyMembers() > 0 then
    SendChatMessage(msg, "PARTY")
  else
    SendChatMessage(msg, "SAY")
  end
end

function R:Build()
  local db = B.db.list
  local f = U.Panel("OctoBGList", "list", "Enemy list", db.width, TITLE_H + 10 * db.rowHeight, "CENTER", 260, -40)
  f.growUp = db.growUp
  U.RestorePos(f)
  U.Backdrop(f, 0.75)
  f:Hide()
  self.frame = f

  -- title bar: drag (unless locked), Alt + wheel switches the list
  local bar = CreateFrame("Frame", nil, f)
  bar:SetHeight(TITLE_H)
  bar:EnableMouse(true)
  bar:EnableMouseWheel(true)
  bar.bg = U.Tex(bar, U.WHITE, "BACKGROUND")
  bar.bg:SetAllPoints(bar)
  bar.bg:SetVertexColor(0.16, 0.16, 0.2, 0.9)
  bar:SetScript("OnMouseDown", function()
    if arg1 == "LeftButton" and not B.db.list.locked then
      f:StartMoving()
      f.moving = true
    end
  end)
  bar:SetScript("OnMouseUp", function()
    if f.moving then
      f:StopMovingOrSizing()
      f.moving = nil
      U.SavePos(f)
    end
  end)
  bar:SetScript("OnMouseWheel", function()
    if IsAltKeyDown() then R:SetMode(B.db.list.mode + ((arg1 > 0) and -1 or 1)) end
  end)
  self.bar = bar
  f.title = U.Text(bar, 10)
  f.title:SetPoint("LEFT", bar, "LEFT", 5, 0)
  f.title:SetJustifyH("LEFT")

  local close = Icon(bar, "button-clear", { "Close", "Hides the list until the next enemy is detected (\"Show on detection\"), or the key binding / minimap menu." },
    function() R:Close() end)
  close:SetPoint("RIGHT", bar, "RIGHT", -3, 0)
  local nextB = Icon(bar, "button-right", { "Next list", "Nearby, Last hour, Ignore, Kill On Sight. Alt + mouse wheel on the title does the same." },
    function() R:SetMode(B.db.list.mode + 1) end)
  nextB:SetPoint("RIGHT", close, "LEFT", -2, 0)
  local prevB = Icon(bar, "button-left", { "Previous list" }, function() R:SetMode(B.db.list.mode - 1) end)
  prevB:SetPoint("RIGHT", nextB, "LEFT", 0, 0)
  local clear = Icon(bar, "button-crosshairs", { "Clear the Nearby list", "Shift-click: detection sounds on / off. Ctrl-click: world PvP detection on / off." },
    function() B.Nearby:ClearButton() R:Refresh() end)
  clear:SetPoint("RIGHT", prevB, "LEFT", -4, 0)
  local stats = Icon(bar, "button-file", { "Statistics", "Every enemy you have met: wins, losses, Kill On Sight reasons." },
    function() if B.Stats then B.Stats:Toggle() end end)
  stats:SetPoint("RIGHT", clear, "LEFT", -2, 0)
  f.count = CreateFrame("Button", nil, bar)
  f.count:SetWidth(28)
  f.count:SetHeight(TITLE_H)
  f.count:SetPoint("RIGHT", stats, "LEFT", -2, 0)
  f.count.text = U.Text(f.count, 12)
  f.count.text:SetPoint("RIGHT", f.count, "RIGHT", 0, 0)
  f.count:SetScript("OnClick", function() R:PostCount() end)
  f.count:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_TOP")
    GameTooltip:AddLine("Enemies seen right now")
    GameTooltip:AddLine("Click: post \"Nearby enemy players: N\" to battleground, raid, party or say.", 1, 1, 1, 1)
    GameTooltip:Show()
  end)
  f.count:SetScript("OnLeave", function() GameTooltip:Hide() end)

  -- width grip
  local grip = CreateFrame("Button", nil, f)
  grip:SetWidth(12)
  grip:SetHeight(12)
  grip:SetNormalTexture(U.MEDIA .. "resize-bottomright")
  grip:SetAlpha(0.25)
  grip:SetFrameLevel(f:GetFrameLevel() + 5)
  grip:SetScript("OnEnter", function() this:SetAlpha(1) end)
  grip:SetScript("OnLeave", function() if not this.sizing then this:SetAlpha(0.25) end end)
  grip:SetScript("OnMouseDown", function()
    if B.db.list.locked then return end
    this.sizing = true
    this.x0 = GetCursorPosition() / f:GetEffectiveScale()
    this.w0 = B.db.list.width
  end)
  grip:SetScript("OnMouseUp", function()
    this.sizing = nil
    this:SetAlpha(0.25)
  end)
  grip:SetScript("OnUpdate", function()
    if not this.sizing then return end
    local x = GetCursorPosition() / f:GetEffectiveScale()
    local w = math.max(190, math.min(420, math.floor(this.w0 + x - this.x0)))
    if w ~= B.db.list.width then
      B.db.list.width = w
      R:Layout()
    end
  end)
  self.grip = grip

  for i = 1, MAX_ROWS do self.rows[i] = self:NewRow() end
  self:Layout()
end

function R:NewRow()
  local f = self.frame
  local r = CreateFrame("Button", nil, f)
  r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  r.bar = U.Tex(r, nil, "BACKGROUND")
  r.bar:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 0)
  r.mark = U.Tex(r, nil, "ARTWORK")
  r.level = U.Text(r, 9, U.NARROW)
  r.level:SetJustifyH("CENTER")
  r.name = U.Text(r, 10, U.NARROW)
  r.name:SetJustifyH("LEFT")
  r.cast = U.Text(r, 9, U.NARROW)
  r.cast:SetJustifyH("LEFT")
  r.castbar = U.Tex(r, U.WHITE, "BORDER")
  r.cd = {}
  for j = 1, 3 do
    local ic = U.Tex(r, nil, "ARTWORK")
    ic:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    local t = U.Text(r, 8, U.NARROW)
    t:SetPoint("CENTER", ic, "CENTER", 0, 0)
    r.cd[j] = { icon = ic, text = t }
  end
  r.onT = U.Text(r, 9, U.NARROW)
  r.onT:SetTextColor(1, 0.55, 0.2)
  r.los = U.Tex(r, U.MEDIA .. "disc", "ARTWORK")
  r.los:SetWidth(7)
  r.los:SetHeight(7)
  r.dist = U.Text(r, 10)
  r.dist:SetJustifyH("RIGHT")
  r.fb = U.Text(r, 11)
  r.fb:SetPoint("CENTER", r, "CENTER", 10, 0)
  r.fb:Hide()
  r:SetScript("OnClick", RowClick)
  r:SetScript("OnEnter", RowTooltip)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  r:SetScript("OnUpdate", function()
    if this.fbT then
      this.fbT = this.fbT - arg1
      if this.fbT <= 0 then
        this.fbT = nil
        this.fb:Hide()
      elseif this.fbT < 0.6 then
        this.fb:SetAlpha(this.fbT / 0.6)
      end
    end
  end)
  r:Hide()
  return r
end

-- Sizes and fonts from the settings (called when they change).
function R:Layout()
  local f = self.frame
  if not f then return end
  local db = B.db.list
  local W, H = db.width, db.rowHeight
  f:SetWidth(W)
  local bar = self.bar
  bar:ClearAllPoints()
  if db.growUp then
    bar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 1, 1)
    bar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
  else
    bar:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
  end
  self.grip:ClearAllPoints()
  if db.growUp then self.grip:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0) else self.grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0) end
  local font = db.font or U.NARROW
  local tex = B.SpyData.BarFile(db.bar)
  local fs = math.max(8, math.floor(H * 0.68))
  -- columns, left to right: mark, level, name, casts / cooldowns, "x2", sight, distance.
  -- Names keep NAME_MIN px; the cooldown column shows as many icons as fit (up to 3),
  -- so nothing is drawn over a name at any width.
  local left = (H - 2) + 18 + 1                            -- where names start
  local free = (W - 4) - left - RIGHT_W - 4                -- names + the middle column
  local step = H                                           -- one icon (H - 2) and a 2 px gap
  local icons = math.max(0, math.min(3, math.floor((free - NAME_MIN) / step)))
  local mid = math.max(icons * step, math.floor(free * 0.42))
  local nameW = free - mid
  local midX = left + nameW + 2                            -- the middle column's left edge
  for i = 1, MAX_ROWS do
    local r = self.rows[i]
    r:SetWidth(W - 4)
    r:SetHeight(H - 1)
    r:ClearAllPoints()
    if db.growUp then
      r:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 2, TITLE_H + 3 + (i - 1) * H)
    else
      r:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -(TITLE_H + 3) - (i - 1) * H)
    end
    r.bar:SetTexture(tex)
    r.bar:SetHeight(H - 1)
    r.mark:SetWidth(H - 3)
    r.mark:SetHeight(H - 3)
    r.mark:SetPoint("LEFT", r, "LEFT", 1, 0)
    r.level:SetFont(font, fs - 1, "OUTLINE")
    r.level:SetWidth(18)
    r.level:SetPoint("LEFT", r, "LEFT", H - 2, 0)
    r.name:SetFont(font, fs, "OUTLINE")
    r.name:SetWidth(nameW)
    r.name:SetHeight(H)
    r.name:ClearAllPoints()
    r.name:SetPoint("LEFT", r, "LEFT", left, 0)
    r.cast:SetFont(font, fs - 1, "OUTLINE")
    r.cast:SetWidth(mid)
    r.cast:SetHeight(H)
    r.cast:ClearAllPoints()
    r.cast:SetPoint("LEFT", r, "LEFT", midX, 1)
    r.castbar:SetHeight(2)
    r.castbar:ClearAllPoints()
    r.castbar:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", midX, 1)
    for j = 1, 3 do
      local ic = r.cd[j].icon
      ic:SetWidth(H - 2)
      ic:SetHeight(H - 2)
      ic:ClearAllPoints()
      ic:SetPoint("LEFT", r, "LEFT", midX + (j - 1) * step, 0)
      r.cd[j].text:SetFont(font, math.max(7, fs - 3), "OUTLINE")
    end
    r.onT:SetFont(font, fs - 1, "OUTLINE")
    r.onT:SetPoint("RIGHT", r, "RIGHT", -38, 0)
    r.los:SetPoint("RIGHT", r, "RIGHT", -28, 0)
    r.dist:SetFont(font, fs, "OUTLINE")
    r.dist:SetWidth(26)
    r.dist:SetPoint("RIGHT", r, "RIGHT", -1, 0)
  end
  self.W, self.mid, self.nIcons = W - 4, mid, icons
end

-- A cooldown's time short enough to sit inside its icon: "59", "2m".
local function IconTime(s)
  s = math.ceil((s or 0) - 0.05)
  if s < 60 then return tostring(math.max(0, s)) end
  return math.ceil(s / 60) .. "m"
end

-- ---------------------------------------------------------------- painting

local function LevelColor(level)
  if not level or level == 0 then return 1, 0.1, 0.1 end
  local diff = level - (UnitLevel("player") or 60)
  if diff >= 5 then return 1, 0.1, 0.1 end
  if diff >= 3 then return 1, 0.5, 0 end
  if diff >= -2 then return 1, 1, 0 end
  if diff >= -9 then return 0.25, 1, 0.25 end
  return 0.55, 0.55, 0.55
end

local RAID_ICONS = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"

function R:Paint(r, e, tg, efcName, respawn, mode)
  local db = B.db.list
  local u = e.u
  local guid = u and u.guid
  local P = B.People
  r.entry = e
  local cr, cg, cb = U.ClassColor(e.class)
  local alpha = (e.rank == 1) and 1 or 0.45
  -- flag on the enemy carrier, else a skull for Kill On Sight
  if efcName and e.name == efcName then
    r.mark:SetTexture(U.FLAG[B.faction or "Alliance"])
    r.mark:SetTexCoord(0, 1, 0, 1)
    r.mark:SetVertexColor(1, 1, 1, 1)
    r.mark:Show()
  elseif e.kos then
    r.mark:SetTexture(RAID_ICONS)
    r.mark:SetTexCoord(0.75, 1, 0.25, 0.5)
    r.mark:SetVertexColor(1, 1, 1, alpha)
    r.mark:Show()
  else
    r.mark:Hide()
  end
  -- level and name
  if e.level then
    r.level:SetText((e.level == 0) and "??" or tostring(e.level))
    local lr, lg, lb = LevelColor(e.level)
    r.level:SetTextColor(lr, lg, lb, alpha)
  else
    r.level:SetText("")
  end
  r.name:SetText(e.name)
  r.name:SetTextColor(cr, cg, cb, alpha)
  -- health
  if e.rank == 1 and u and u.hp and u.hpmax and u.hpmax > 0 then
    r.bar:SetWidth(math.max(1, self.W * u.hp / u.hpmax))
    if B.CD:ImmuneLeft(guid) then
      r.bar:SetVertexColor(1, 0.82, 0.1, 0.5)
    elseif tg and guid == tg then
      r.bar:SetVertexColor(1, 1, 1, 0.35)
    else
      r.bar:SetVertexColor(cr, cg, cb, 0.4)
    end
    r.bar:Show()
  elseif e.rank == 2 and mode == 1 then
    r.bar:SetWidth(self.W)
    r.bar:SetVertexColor(cr, cg, cb, 0.1)
    r.bar:Show()
  else
    r.bar:Hide()
  end
  -- middle: cast, else dead + resurrection, else cooldowns (Nearby) / record (other lists)
  local spell, _, prog, _, chan
  if mode == 1 and db.casts and e.rank ~= 3 and guid then spell, _, prog, _, chan = B.Casts:Get(guid) end
  local showCds = false
  if spell then
    r.cast:SetText(spell)
    if chan then r.cast:SetTextColor(0.5, 0.75, 1) else r.cast:SetTextColor(1, 0.8, 0.2) end
    r.castbar:SetWidth(math.max(1, self.mid * (chan and (1 - prog) or prog)))
    if chan then r.castbar:SetVertexColor(0.3, 0.6, 1, 1) else r.castbar:SetVertexColor(1, 0.75, 0.15, 1) end
    r.castbar:Show()
  elseif e.rank == 3 then
    r.cast:SetText(respawn and ("dead - res " .. math.ceil(respawn)) or "dead")
    r.cast:SetTextColor(0.6, 0.6, 0.6)
    r.castbar:Hide()
  elseif mode ~= 1 then
    local rec = P:Get(e.name)
    local text = ""
    if mode == 4 then text = P:ReasonText(e.name) or "" end
    if text == "" and rec and rec.guild then text = "<" .. rec.guild .. ">" end
    r.cast:SetText(text)
    r.cast:SetTextColor(0.75, 0.75, 0.75)
    r.castbar:Hide()
  else
    r.cast:SetText((e.source and e.rank ~= 1) and ("via " .. e.source) or "")
    r.cast:SetTextColor(0.4, 0.9, 0.4)
    r.castbar:Hide()
    showCds = guid and e.rank == 1 and true or false
  end
  local n = (showCds and (self.nIcons or 0) > 0) and B.CD:Important(guid, self.nIcons, self.cds) or 0
  for j = 1, 3 do
    local c = r.cd[j]
    if j <= n and self.cds[j].tex then
      c.icon:SetTexture(self.cds[j].tex)
      c.icon:Show()
      c.text:SetText(IconTime(self.cds[j].rem))
    else
      c.icon:Hide()
      c.text:SetText("")
    end
  end
  -- how many of your group are on them
  local t = mode == 1 and db.targeted and guid and self.onTarget[guid]
  r.onT:SetText(t and ("x" .. t) or "")
  -- sight and distance (other lists: how long ago)
  if e.rank == 1 and u and u.los ~= nil and db.distance then
    if u.los then r.los:SetVertexColor(0.3, 1, 0.3) else r.los:SetVertexColor(1, 0.25, 0.2) end
    r.los:Show()
  else
    r.los:Hide()
  end
  if mode ~= 1 and e.rank ~= 1 then
    r.dist:SetText(P.Ago(e.t))
    r.dist:SetTextColor(0.7, 0.7, 0.7)
  elseif db.distance and e.dist then
    r.dist:SetText(tostring(math.floor(e.dist)))
    -- light blue: the distance comes from a teammate's report (team sync)
    if e.team then r.dist:SetTextColor(0.45, 0.75, 1) else r.dist:SetTextColor(1, 1, 1) end
  elseif mode == 1 and e.rank == 2 and B.Nearby.inactive[e.name] then
    r.dist:SetText(P.Ago(B.Nearby.inactive[e.name]))
    r.dist:SetTextColor(0.55, 0.55, 0.55)
  else
    r.dist:SetText("")
  end
  r.guid = guid
  r:Show()
end

function R:Update()
  local f = self.frame
  local db = B.db.list
  local total = self:Collect()
  local rows = math.min(db.rows, MAX_ROWS)
  local tg = U.GuidOf("target")
  local efc = B.Flags:Enemy()
  local efcName = efc and not efc.dropped and efc.name
  local respawn = B.Timers.spirit:NextWave(B.enemy)
  local mode = db.mode
  local seen, dead = 0, 0
  for i = 1, total do
    local e = self.list[i]
    if e.rank == 1 then seen = seen + 1 elseif e.rank == 3 then dead = dead + 1 end
    if i <= rows then self:Paint(self.rows[i], e, tg, efcName, respawn, mode) end
  end
  local shown = math.min(total, rows)
  for i = shown + 1, MAX_ROWS do
    self.rows[i]:Hide()
    self.rows[i].entry = nil
  end
  local title
  if self:Roster() then
    title = "Enemies " .. total .. "  |cffaaaaaa" .. dead .. " dead|r"
  elseif mode == 1 then
    title = "Nearby" .. ((total > shown) and ("  |cffaaaaaa+" .. (total - shown) .. "|r") or "")
  else
    title = MODES[mode] .. "  |cffaaaaaa" .. total .. "|r"
  end
  f.title:SetText(title)
  f.count.text:SetText(tostring(seen))
  if seen > 0 then f.count.text:SetTextColor(1, 1, 0) else f.count.text:SetTextColor(0.5, 0.5, 0.5) end
  f:SetHeight(TITLE_H + 4 + math.max(1, shown) * db.rowHeight)
  f:SetAlpha((B.zone or B.Nearby.inInstance) and db.alphaBG or db.alpha)
end

-- ---------------------------------------------------------------- show / hide

function R:Wanted()
  local db = B.db.list
  if not db.enabled or self.closed then return false end
  if B.test or B.zone then return true end
  if not db.world then return false end
  local NB = B.Nearby
  if NB:LayerOn() then
    if db.hideEmpty and db.mode == 1 and NB.n == 0 then return false end
    return true
  end
  -- detection off: the list follows the HUD / map open-world switches
  return B.active and ((B.db.hud.enabled and B.db.hud.world) or (B.db.map.enabled and B.db.map.world)) or false
end

function R:SetMode(m)
  local n = table.getn(MODES)
  if m > n then m = 1 elseif m < 1 then m = n end
  B.db.list.mode = m
  self:Refresh()
end

function R:Close()
  self.closed = true
  if self.frame then self.frame:Hide() end
end

function R:Open()
  self.closed = false
  B.db.list.enabled = true
  self:Refresh()
end

function R:Toggle()
  if self.frame and self.frame:IsShown() then self:Close() else self:Open() end
end

function R:Refresh()
  self.dirty = true
  self.t = 99
end

R.t = 0
B:Every(0.1, function()
  local f = R.frame
  if not f then return end
  R.t = R.t + 0.1
  if R:Wanted() then
    if not f:IsShown() then
      f:Show()
      R.t = 99
    end
    if R.t >= 1 / math.max(1, B.db.list.rate or 4) or R.dirty then
      R.t, R.dirty = 0, nil
      R:Update()
    end
  elseif f:IsShown() then
    f:Hide()
  end
end)

B:On("OBG_NEARBY", function() R.dirty = true end)
B:On("OBG_PEOPLE", function() R.dirty = true end)
B:On("OBG_ZONE", function(ev, zone)
  if zone and zone ~= "ARENA" then R.closed = false end
end)

-- Damage numbers on the rows (SuperWoW fires UNIT_COMBAT for GUIDs, as Spy's
-- rows and ShaguScan read it).
B:On("UNIT_COMBAT", function(ev, unit, action, crit, amount)
  if not B.db.list.feedback or not U.IsGuid(unit) or not R.frame or not R.frame:IsShown() then return end
  for i = 1, MAX_ROWS do
    local r = R.rows[i]
    if r:IsShown() and r.guid == unit then
      local text, cr, cg, cb = nil, 1, 1, 1
      if action == "WOUND" and amount and amount > 0 then
        text, cr, cg, cb = "-" .. amount, 1, 0.3, 0.3
      elseif action == "HEAL" and amount and amount > 0 then
        text, cr, cg, cb = "+" .. amount, 0.3, 1, 0.3
      elseif action and action ~= "WOUND" and action ~= "HEAL" then
        text = string.lower(action)
      end
      if text then
        r.fb:SetText(text)
        r.fb:SetTextColor(cr, cg, cb)
        r.fb:SetTextHeight((crit == "CRITICAL") and 13 or 10)
        r.fb:SetAlpha(1)
        r.fb:Show()
        r.fbT = 1.4
      end
      return
    end
  end
end, true)

B:On("OBG_ACTIVE", function(ev, on)
  if not on and R.frame and not R:Wanted() then R.frame:Hide() end
end)

B:On("OBG_INIT", function() R:Build() end)

-- Settings changed on the options page.
function R:Restyle()
  if not self.frame then return end
  self.frame.growUp = B.db.list.growUp
  U.RestorePos(self.frame)
  self:Layout()
  self:Refresh()
end

function OctoBG_ToggleList() R:Toggle() end
