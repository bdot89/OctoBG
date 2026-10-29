-- OctoBG :: options window and slash commands
-- One window, a topic list on the left, one page per feature on the right.
-- Every page starts with what the feature does and every setting explains
-- itself (core\Widgets.lua). /obg opens it; /obg <command> for the rest.

local B = OctoBG
local U = B.U
local W = B.W
local O = { pages = {}, nav = {} }
B.Options = O

local WIDTH, HEIGHT, NAV_W, NAV_ROW = 800, 640, 168, 19

-- ---------------------------------------------------------------- popups

StaticPopupDialogs["OCTOBG_AUTOPOST"] = {
  text = "OctoBG: post INC calls to /bg automatically when enemies reach the base you are standing at?\n\n(At most one call every 20 seconds, only for 2 or more enemies.)",
  button1 = YES,
  button2 = NO,
  OnAccept = function()
    B.db.inc.autoPost = true
    O:Refresh()
  end,
  OnCancel = function()
    B.db.inc.autoPost = false
    O:Refresh()
  end,
  timeout = 0,
  whileDead = 1,
  hideOnEscape = 1,
}

-- Spy's automatic announcements post to chat: asked first (OctoBG's rule).
-- Automatic EFC calls post to /bg: asked first (OctoBG's rule).
StaticPopupDialogs["OCTOBG_EFC_CALL"] = {
  text = "OctoBG: post where the enemy flag carrier is, and how many are with them, to /bg automatically?\n\n(When they reach a new part of the map, at most every 10 seconds.)",
  button1 = YES,
  button2 = NO,
  OnAccept = function()
    B.db.flags.autoCall = true
    O:Refresh()
  end,
  timeout = 0,
  whileDead = 1,
  hideOnEscape = 1,
}

StaticPopupDialogs["OCTOBG_SPY_ANNOUNCE"] = {
  text = "OctoBG: post every newly detected enemy player to %s chat automatically?",
  button1 = YES,
  button2 = NO,
  OnAccept = function()
    B.db.spy.Announce = O.pendingAnnounce or "None"
    O:Refresh()
  end,
  timeout = 0,
  whileDead = 1,
  hideOnEscape = 1,
}

-- ---------------------------------------------------------------- helpers

local function Mark(ok)
  return ok and "|cff55ff55yes|r" or "|cffff5555no|r"
end

function O:StatusLine()
  local e = B.env
  local cal
  if B.Map:CalibrationDone() then cal = "|cff55ff55calibrated|r" else cal = "|cffffd100learning (run forward a bit)|r" end
  return "SuperWoW " .. Mark(e.superwow) .. "  nampower " .. Mark(e.nampower) .. "  UnitXP " .. Mark(e.unitxp)
    .. "  ClassicAPI " .. Mark(e.classicapi) .. "  facing " .. cal
end

-- Check / slider bound to a key of a settings table (tbl is a function so
-- a reset of B.db.cd is picked up).
local function Chk(p, label, desc, tbl, key, after)
  return W.Check(p, label, desc, function() return tbl()[key] end, function(v)
    tbl()[key] = v
    if after then after(v) end
  end)
end

local function Sld(p, label, desc, min, max, step, tbl, key, after, fmt)
  return W.Slider(p, label, desc, min, max, step, function() return tbl()[key] end, function(v)
    tbl()[key] = v
    if after then after(v) end
  end, fmt)
end

local function Drop(p, label, desc, options, tbl, key, after)
  return W.Dropdown(p, label, desc, options, function() return tbl()[key] end, function(v)
    tbl()[key] = v
    if after then after(v) end
  end)
end

local function Pct(v) return math.floor(v * 100 + 0.5) .. "%" end
local function Pct100(v) return v .. "%" end
local function Yd(v) return v .. " yd" end
local function Sec(v) return v .. " s" end
local function Px(v) return v .. " px" end

local function F() return B.db.flags end
local function T() return B.db.timers end
local function I() return B.db.inc end
local function H() return B.db.hud end
local function L() return B.db.list end
local function M() return B.db.map end
local function S() return B.db.stealth end
local function C() return B.db.cd end
local function DB() return B.db end
local function SP() return B.db.spy end
local function Zone() if B.Nearby then B.Nearby:ZoneCheck() end end
local function ListStyle() if B.Roster then B.Roster:Restyle() end end

-- An ON / OFF switch bound to a key of a settings table: { get, set, tip }.
local function On(tbl, key, after, tip)
  return { function() return tbl()[key] end, function(v)
    tbl()[key] = v
    if after then after(v) end
  end, tip }
end

local function HudLayout() if B.HUD then B.HUD:Layout() end end
local function MapLayout() if B.TacMap then B.TacMap:Layout() end end
local function Active() B:RefreshActive() end

-- ---------------------------------------------------------------- pages
-- Wording rule (user, 17 Oct 2026: "clearer descriptions ... easier to
-- understand"): every card starts with one plain line saying what it is for,
-- every setting has a tooltip that says what you will see, in everyday words.

local BUILD = {}
-- Pages in other files can use the same builders and helpers.
O.BUILD = BUILD
O.Chk, O.Sld, O.Drop, O.On = Chk, Sld, Drop, On
O.Pct, O.Px, O.Sec, O.Yd = Pct, Px, Sec, Yd

BUILD.start = function(p)
  W.Heading(p, "Welcome to OctoBG", {
    text = "Everything for PvP in one addon. Tick a feature to use it, untick it to hide it everywhere. Click a "
      .. "topic on the left for its settings. Hover anything to see what it does." })
  W.Card(p, "Features", { text = "Each tick box switches one whole feature on or off." })
  Chk(p, "Enemy map", "A map with every enemy as a coloured triangle. Hover one to see who it is, click to target them.", M, "enabled")
  Chk(p, "Flag carriers", "Warsong Gulch: who has each flag, their health and where they are. Click to target them.", F, "enabled",
    function() if B.Flags then B.Flags:Refresh() end end)
  Chk(p, "Timers", "Bars counting down to the next resurrection, base captures, the battle start and who wins Arathi Basin.", T, "enabled")
  Chk(p, "INC call bar", "Buttons that post \"3 INC STABLES\" to battleground chat in one click.", I, "enabled")
  Chk(p, "Team sync", "Teammates with OctoBG share the enemies they see, so your map shows more.", function() return B.db.sync end, "enabled")
  Chk(p, "Enemy list", "A list of the enemies near you (or the whole enemy team in a battleground) with health and distance.", L, "enabled")
  Chk(p, "Radar HUD", "A see-through radar around your character showing where enemies are.", H, "enabled", Active)
  W.Check(p, "Spy detection", "Spy's world PvP warnings: a sound when an enemy player shows up, a big warning for people on your Kill On Sight list.",
    function() return B.db.spy.Enabled end, function(v) B.Nearby:SetEnabled(v) end)
  Chk(p, "Stealth alert", "A warning when an enemy near you goes into stealth.", S, "alert")
  Chk(p, "Stealth marks", "A purple circle on the radar and map where a rogue vanished.", S, "enabled")
  Chk(p, "Cooldown bars", "Bars under your target showing which big spells they used and when they are ready again.", C, "bars")
  Chk(p, "Nameplate cooldowns", "Small spell icons above every enemy's nameplate showing what they used.", C, "nameplates")
  Chk(p, "Keep target", "If a hunter feigns death and you lose your target, OctoBG targets them again.", function() return B.db.retarget end, "enabled")
  Chk(p, "Focus strip", "A small bar under your focus showing their cooldowns and range.", function() return B.db.focus end, "strip")
  W.Card(p, "First steps", { text = "Put the panels where you want them. You only need to do this once." })
  W.Buttons(p, {
    { "Move frames", function() U.SetLocked(false) end, 130,
      "Every panel appears with pretend enemies and a blue box. Drag the boxes where you want them. Hover a box to resize it, fade it or switch it off. Click Done when finished." },
    { "Done", function() U.SetLocked(true) end, 70, "Puts the panels away again." },
    { "Reset positions", function() U.ResetPositions() end, 120, "Moves every panel back to where it started." },
  })
  W.Buttons(p, {
    { "Max view distance", function() O:MaxView(false) end, 150,
      "Lets you see players and nameplates from further away. /obg maxview off undoes it." },
    { "Key bindings", function() if KeyBindingFrame_LoadUI then KeyBindingFrame_LoadUI() end if KeyBindingFrame then ShowUIPanel(KeyBindingFrame) end end, 120,
      "Opens the game's key bindings. OctoBG's keys are under OctoBG (target the enemy flag carrier, INC calls, radar...)." },
  })
  W.Note(p, "Most panels only show up inside battlegrounds. Move frames shows them all so you can place them anywhere.")
  W.Card(p, "Your client", { text = "The game add-ons (DLLs) OctoBG can use. Green = found. Missing ones only switch off a few extras." })
  W.Live(p, function()
    local e = B.env
    return "SuperWoW " .. Mark(e.superwow) .. " |cff999999- enemy positions, spell names|r\n"
      .. "nampower " .. Mark(e.nampower) .. " |cff999999- finding enemies, nameplates, cooldown lengths|r\n"
      .. "UnitXP_SP3 " .. Mark(e.unitxp) .. " |cff999999- distances and line of sight|r\n"
      .. "ClassicAPI " .. Mark(e.classicapi) .. " |cff999999- which way you face, spell icons, copy to clipboard|r"
  end, 4)
  local old = B.CD:OldLoaded() or B.People:SpyLoaded()
  W.Card(p, "The old addons", { folded = not old,
    text = "Spy and EnemyCooldowns are built into OctoBG. Switch the old ones off so nothing shows twice." })
  W.Live(p, function()
    local s
    if B.CD:OldLoaded() then
      s = "EnemyCooldowns: |cffffd100still switched on|r - switch it off so nothing shows twice."
    else
      s = "EnemyCooldowns: |cff55ff55not running|r - its folder can be deleted."
    end
    if B.People:SpyLoaded() then
      s = s .. "\nSpy: |cffffd100still switched on|r - OctoBG's Spy warnings wait until it is off."
    else
      s = s .. "\nSpy: |cff55ff55not running|r - its folder can be deleted."
    end
    return s
  end, 2)
  W.Buttons(p, {
    { "Switch EnemyCooldowns off", function()
      if B.CD:OldLoaded() then StaticPopup_Show("OCTOBG_OLD_ECD") else B:Print("EnemyCooldowns is not running") end
    end, 180, "Switches the old addon off and reloads the interface. Its settings were already copied." },
    { "Switch Spy off", function()
      if B.People:SpyLoaded() then StaticPopup_Show("OCTOBG_OLD_SPY") else B:Print("Spy is not running") end
    end, 120, "Switches the old addon off and reloads the interface. Its lists were already copied." },
  })
end

-- ---------------------------------------------------------------- battlegrounds

local MAP_NAMES = { { key = "none", label = "No names" }, { key = "marked", label = "Target and Kill On Sight" },
                    { key = "all", label = "Every enemy" } }
local function Zoom(v) return (v <= 1) and "whole map" or (v .. "x") end

BUILD.map = function(p)
  W.Heading(p, "Enemy map", {
    on = On(M, "enabled", nil, "Show the enemy map."),
    text = "A map of the battleground with every enemy on it as a triangle in their class colour.",
    about = "A triangle turns into an arrow while that enemy is running, pointing the way they go. Enemies you can no "
      .. "longer see fade to half.\n\nRings: white = your target, red = Kill On Sight, gold = can't be hurt right now "
      .. "(Ice Block, Divine Shield).\n\nAlso shown: you (arrow), your group (small dots), both flag carriers, the bases "
      .. "and purple circles where rogues vanished. The enemy flag carrier gets a red ring and \"EFC +4\" (how many "
      .. "enemies are with them).\n\nHover an enemy to see who it is, click to target them, right-click for more, mouse "
      .. "wheel to zoom. Zoomed in, drag the map to look somewhere else - \"Back to me\" (top left) follows you again.\n\n"
      .. "Bases: hover one to see its counting circle and how many enemies are there or on the way; click it to post "
      .. "\"3 INC STABLES\" to battleground chat; right-click it to pick it on the INC bar.\n\nA key binding (under "
      .. "OctoBG) and /obg map show or hide it.",
    extra = { { "Outside battlegrounds too", function() return B.db.map.world end, function(v) B.db.map.world = v Active() end,
                "Also show the map (with enemies) in the open world." } } })
  W.Card(p, "What is drawn", { text = "Choose what appears on the map." })
  Chk(p, "Enemies", "Off: the map only shows you, your group and the bases.", M, "enemies")
  Chk(p, "Arrows for runners", "A running enemy's triangle points the way they are going. Off: always plain triangles.", M, "heading")
  Chk(p, "Hover and click enemies", "Hover an enemy to see who it is, click to target them. Off: clicks go through the map to the game.", M, "mouse", MapLayout)
  Chk(p, "Enemy count under it", "A line under the map: how many enemies it shows and where the enemy flag carrier is.", M, "count")
  Drop(p, "Names", "Small names under the triangles: none, only your target and Kill On Sight, or everyone.", MAP_NAMES, M, "names")
  W.Space(p, 2)
  Chk(p, "Base circles", "Battlegrounds: a circle round every base (Arathi Basin nodes, Warsong Gulch flag rooms) with a "
    .. "label - \"ST 3 +2\" = 3 enemies there, 2 running in. Click the label to post \"3 AT STABLES\", right-click it to "
    .. "pick the base on the INC bar.", M, "bases")
  Chk(p, "Whole zone uncovered", "Draws every part of the zone map as if you had explored it all - every zone, OctoWoW's new ones too (from the game's own map data).",
    M, "explore", MapLayout)
  W.Card(p, "Height: above or below you", { text = "A small mark by a player who is higher (a roof, a hill) or lower "
    .. "than you, and a box on the map with how many enemies are above and below." })
  local function Redraw() if B.TacMap and B.TacMap.frame and B.TacMap.frame:IsShown() then B.TacMap:Update() end end
  local function Col(key)
    return function() local c = B.db.map[key] return c[1], c[2], c[3] end,
           function(r, g, b) B.db.map[key] = { r, g, b } Redraw() end
  end
  W.Check(p, "Height marks", "Only for players your own client sees (height is not shared by teammates).",
    function() return (B.db.map.height or "on") ~= "off" end, function(v) B.db.map.height = v and "on" or "off" Redraw() end)
  Drop(p, "On whom", nil, { { key = "both", label = "Enemies and my team" }, { key = "enemies", label = "Enemies only" },
    { key = "friends", label = "My team only" } }, M, "heightWho", Redraw)
  Drop(p, "Look", "Bars: one, two or three (more = further). Yards: \"+15\". Signs: + ++ +++ / - -- ---.",
    { { key = "bars", label = "Small bars" }, { key = "number", label = "Yards (+15 / -22)" },
      { key = "signs", label = "Signs (+ ++ / - --)" } }, M, "heightStyle", Redraw)
  Drop(p, "Where on the marker", "Beside it keeps them clear of the names under the markers.",
    { { key = "side", label = "Right side (higher top, lower bottom)" }, { key = "left", label = "Left side" },
      { key = "stack", label = "Above / below the marker" } }, M, "heightPlace", Redraw)
  local gu, su = Col("heightUp")
  W.Color(p, "Colour when higher", nil, gu, su)
  local gd, sd = Col("heightDown")
  W.Color(p, "Colour when lower", nil, gd, sd)
  Sld(p, "Show from", "How much higher or lower before a mark shows - a few yards of slope never count. Two marks "
    .. "from double this, three from four times.", 5, 30, 1, M, "heightStep", nil, function(v) return v .. " yd" end)
  Chk(p, "Above / below box on the map", "A small box: how many enemies in sight are higher and lower than you.", M,
    "heightBox", Redraw)
  Drop(p, "Box in the corner", nil, { { key = "BOTTOMLEFT", label = "Bottom left" }, { key = "BOTTOMRIGHT", label = "Bottom right" },
    { key = "TOPLEFT", label = "Top left" }, { key = "TOPRIGHT", label = "Top right" } }, M, "heightBoxAt", Redraw)
  W.Card(p, "Map look", { text = "The frame round the map, in the game's own art." })
  Drop(p, "Border", nil, B.TacMap.BORDERS, M, "border", MapLayout)
  W.Color(p, "Border colour", "For the line, tooltip and solid borders.", function() local c = B.db.map.borderColor return c[1], c[2], c[3] end,
    function(r, g, b) B.db.map.borderColor = { r, g, b } MapLayout() end)
  Chk(p, "Title plaque with the zone's name", "The stone plaque of the game's windows on top of the map.", M, "plaque", MapLayout)
  W.Card(p, "As your world map", { text = "Use this map instead of the game's world map: press M and it opens big in the middle of the screen." })
  Drop(p, "The M key opens", "The game's world map (pfUI's, if pfUI is on), this map big, or nothing at all.",
    { { key = "game", label = "The game's world map" }, { key = "obg", label = "OctoBG's map (big)" },
      { key = "off", label = "Nothing (world map off)" } }, M, "worldKey")
  Sld(p, "Big map width", "How wide the map is when M opens it. Mouse wheel zooms, drag to look around, M or Escape closes it.",
    400, 1200, 20, M, "bigWidth", MapLayout, Px)
  W.Buttons(p, { { "Open it big now", function() if B.TacMap then B.TacMap:SetBig(true) end end, 130,
    "Opens the map big in the middle of the screen (M or Escape closes it)." } })
  W.Card(p, "Size and zoom", { text = "How big the map is and how far it zooms in. The mouse wheel zooms too." })
  Sld(p, "Width", "How wide the map is on screen.", 180, 560, 10, M, "width", MapLayout, Px)
  Sld(p, "Darken the map", "Makes the map picture darker so the triangles are easier to see.", 0, 0.9, 0.05, M, "dim", MapLayout, Pct)
  Sld(p, "Zoom in battlegrounds", "1 = the whole battleground. Higher = closer, following you around.", 1, 6, 0.5, M, "zoom", MapLayout, Zoom)
  Sld(p, "Zoom outside", "Zones are big: 3x shows about as far as you can see enemies.", 1, 6, 0.5, M, "zoomWorld", MapLayout, Zoom)
end

BUILD.flags = function(p)
  W.Heading(p, "Flag carriers", {
    on = On(F, "enabled", function() if B.Flags then B.Flags:Refresh() end end, "Show the flag carrier panel in Warsong Gulch."),
    text = "Warsong Gulch: who carries each flag, their health, how long they have had it and where they are.",
    about = "Two rows, one per flag: the carrier's name in class colour, their health, how long they have held it, how "
      .. "far away they are, an arrow pointing at them and where they are in plain words (\"Horde base - lower level\").\n\n"
      .. "Left-click a row: target the carrier. Right-click: target them and cast your flag spell. Ctrl-click: post their "
      .. "health and location to battleground chat.\n\nKey bindings (under OctoBG): target the enemy carrier, cast your "
      .. "flag spell on them, target our carrier." })
  W.Card(p, "Warnings", { text = "What you are told about the flags." })
  Chk(p, "Flag warnings", "A message on screen when the enemy takes our flag, when it is dropped, and when their carrier is low on health.", F, "alerts")
  Chk(p, "Carrier's cooldowns", "Small icons on each row for the big spells the carrier has used: trinket, Ice Block, Vanish...", F, "cds")
  Sld(p, "Low health warning", "Warn when the enemy carrier's health drops below this.", 10, 60, 5, F, "lowHp", nil, Pct100)
  W.Card(p, "Calling the carrier", { text = "Tell your team where the enemy carrier is and how many are with them: \"EFC Name 64% - Horde base - with 4\"." })
  W.Check(p, "Call it in chat by itself", "Posts the call to battleground chat when the carrier reaches a new part of the map or their escort changes (at most every 10 s, and every 30 s otherwise). Asks you first.",
    function() return B.db.flags.autoCall end,
    function(v)
      B.db.flags.autoCall = false
      if v then StaticPopup_Show("OCTOBG_EFC_CALL") end
    end, true)
  W.Buttons(p, { { "Call it now", function() B.Flags:Announce(B.Flags:Enemy()) end, 120,
    "Posts the enemy carrier's call once (same as Ctrl-clicking their row)." } })
  W.Note(p, "\"With 4\" counts enemies within 30 yards of the carrier that you or teammates with OctoBG can see.")
  W.Card(p, "Clicks and keys", { text = "What happens when you click a carrier." })
  W.Edit(p, "Right-click spell", "The spell cast on the carrier when you right-click their row. Priests: Mind Vision lets you watch them from anywhere. Leave empty to only target.",
    function() return B.Flags:Spell() end, function(v) B.db.flags.spell = v end)
  W.Buttons(p, { { "Use my class default", function() B.db.flags.spell = nil end, 160,
    "Priest: Mind Vision, Hunter: Hunter's Mark, everyone else: just target." } })
  W.KeyBind(p, "Interact key", "Press it standing on a dropped flag to return ours or pick theirs up. See the Interact key page.", "OCTOBG_INTERACT")
end

BUILD.timers = function(p)
  W.Heading(p, "Timers", {
    on = On(T, "enabled", nil, "Show the timers panel."),
    text = "Countdown bars for resurrections, base captures, the battle start and who wins Arathi Basin. Click a bar to say it in chat.",
    about = "Resurrection: the dead come back every 30 seconds at each graveyard - the bar shows when the next wave is.\n"
      .. "Arathi Basin: a base is taken 60 seconds after it is attacked. Alterac Valley: towers and graveyards take 5 "
      .. "minutes.\n\nClick a bar to post it in battleground chat, e.g. \"Stables: Horde takes it in 0:37\". Hover a bar "
      .. "to see what it will say." })
  W.Card(p, "What it shows", { text = "Pick which timers appear in the panel." })
  Chk(p, "Resurrection waves", "A bar per graveyard showing when the dead come back. The colour tells whose graveyard it is.", T, "spirit")
  Chk(p, "Who wins Arathi Basin", "Works out which side reaches 2000 first and when.", T, "predict")
  Chk(p, "Big countdown when dead", "While you are dead in a battleground: \"Resurrection in 12\" in the middle of the screen.", T, "big")
end

BUILD.inc = function(p)
  W.Heading(p, "INC calls", {
    on = On(I, "enabled", nil, "Show the INC bar (only in battlegrounds)."),
    text = "Buttons for battleground calls like \"3 INC STABLES\", \"SAFE\" and \"HELP\". The base you stand at is picked for you.",
    about = "Top row: the bases. AUTO (green) = the base nearest you is picked by itself. PICKED (gold) = you clicked "
      .. "one; click it again to go back to AUTO.\n\nBottom row: 1 2 3 4 5+, Safe, Help, and Auto, which posts what "
      .. "OctoBG counts: enemies at the base plus those running towards it, e.g. \"3 AT STABLES + 2 INC\". The automatic caller posts INC calls only: \"2 INC STABLES\" when enemies run at your base. "
      .. "Ctrl-click a base to post its count straight away.\n\nTop right of the bar: auto-post on / off (click it).\n\n"
      .. "On the enemy map: hover a base to see its counting circle and numbers, click it to post its call, right-click "
      .. "it to pick it here." })
  W.Card(p, "Guard warning", { text = "Warns you when enemies run at the base you are standing at." })
  Chk(p, "Guard warning", "A flashing warning on your screen when enemies arrive at your base. Only you see it.", I, "alert")
  W.Check(p, "Post it to chat as well", "Posts the warning to battleground chat by itself (2+ enemies, at most every 20 seconds). Asks you first.",
    function() return B.db.inc.autoPost end,
    function(v)
      B.db.inc.autoPost = false
      if v then StaticPopup_Show("OCTOBG_AUTOPOST") end
    end)
  Sld(p, "Base size", "How close to a base an enemy has to be to count as being at it. Enemies up to three times "
    .. "this far out (at most 150 yd) who are running towards it count as on the way.", 20, 100, 5, I, "radius", nil, Yd)
end

BUILD.sync = function(p)
  local SY = B.Sync
  W.Heading(p, "Team sync", {
    on = On(function() return B.db.sync end, "enabled", nil, "Show what teammates running OctoBG see."),
    text = "Everyone in your battleground with OctoBG shares the enemies they can see, so your map and list show far more.",
    about = "The game only tells you about enemies near you. With team sync you also get, from teammates using OctoBG:\n"
      .. "- enemies they see, with health (on the map, radar edge and enemy list - distance in blue)\n"
      .. "- the enemy flag carrier's health when you are far away\n"
      .. "- enemy counts at bases you are not at\n"
      .. "- enemy cooldowns they saw\n"
      .. "- stealth marks and resurrection timers\n\n"
      .. "Nothing appears in chat. /obg sync prints who is sharing." })
  W.Card(p, "Right now", { text = "Who else is sharing in this battleground." })
  local function Status()
    local names = SY:Status()
    local ch = SY:Channel()
    local s = "Channel: " .. (ch and ("|cff55ff55" .. ch .. "|r") or "|cff888888none - join a battleground|r")
    s = s .. "\nOther OctoBG users here: " .. (table.getn(names) > 0 and ("|cffffffff" .. table.concat(names, ", ") .. "|r") or "|cff888888none yet|r")
    s = s .. "\nEnemies only teammates see right now: " .. SY:TeamOnly() .. "    sent " .. SY.sent .. " / received " .. SY.recv
    return s
  end
  local fs = W.Live(p, Status, 3)
  -- live while the page is open
  local tick = CreateFrame("Frame", nil, p.body)
  tick.t = 0
  tick:SetScript("OnUpdate", function()
    this.t = this.t + (arg1 or 0)
    if this.t >= 1 then
      this.t = 0
      fs:SetText(Status())
    end
  end)
  Chk(p, "Share what I see", "Send the enemies you see to your team. Off: you only receive.", function() return B.db.sync end, "share")
end

-- ---------------------------------------------------------------- spy / enemies

local SORTS = { { key = "range", label = "Nearest first" }, { key = "time", label = "Newest first" },
                { key = "name", label = "By name" }, { key = "class", label = "By class" } }
local ANCHORS_TIP = { { key = "ANCHOR_LEFT", label = "Left of the list" }, { key = "ANCHOR_RIGHT", label = "Right of the list" },
                      { key = "ANCHOR_TOP", label = "Above the row" }, { key = "ANCHOR_BOTTOM", label = "Below the row" },
                      { key = "ANCHOR_CURSOR", label = "At the mouse" } }

BUILD.list = function(p)
  W.Heading(p, "Enemy list", {
    on = On(L, "enabled", nil, "Show the enemy list."),
    text = "Spy's list of enemies near you - or the whole enemy team in a battleground - with health, distance and what they cast.",
    about = "The arrows in its title bar (or Alt + mouse wheel) switch between Nearby, Last hour, Ignore and Kill On "
      .. "Sight.\n\nEach row: level, name over a health bar, a skull for Kill On Sight, the spell they are casting (or "
      .. "their last big cooldowns), x2 = two of your group target them, a dot (green = you can see them) and the "
      .. "distance.\n\nClick: target. Shift-click: Kill On Sight. Ctrl-click: ignore. Alt-click: focus. Right-click: "
      .. "menu. Click the number in the title bar to post how many enemies are near.",
    extra = { { "Outside battlegrounds too", function() return B.db.list.world end, function(v) B.db.list.world = v end,
                "Show the list in the open world too (needs Spy detection on)." } } })
  W.Buttons(p, {
    { "Open the list", function() B.Roster:Open() end, 120, "Shows the list now." },
    { "Statistics", function() B.Stats:Show() end, 110, "Every enemy you have met: wins, losses and why they are on Kill On Sight." },
  })
  W.Card(p, "What each row shows", { text = "Pick what you see next to each enemy's name." })
  Chk(p, "Whole team in battlegrounds", "Lists every enemy on the scoreboard, even far away or dead. Off: only the ones around you.", L, "roster")
  Chk(p, "What they are casting", "While an enemy casts, their row shows the spell and a progress bar.", L, "casts")
  Chk(p, "How many target them", "x2 = two people in your group have this enemy targeted.", L, "targeted")
  Chk(p, "Distance and sight", "How far away they are, and a green dot if you can see them.", L, "distance")
  Chk(p, "Damage on the rows", "The damage and healing an enemy takes flashes on their row.", L, "feedback")
  Sld(p, "Updates per second", "How often the list redraws. Lower is lighter on your computer with 40 enemies.", 1, 5, 1, L, "rate")
  W.Card(p, "Order", { text = "Who is at the top of the list." })
  Chk(p, "Kill On Sight at the top", "Players on your Kill On Sight list always come first.", SP, "PrioritiseKoS")
  W.Space(p, 2)
  Drop(p, "Outside battlegrounds", "How the list is sorted in the open world.", SORTS, L, "sortWorld")
  Drop(p, "In battlegrounds", "How the list is sorted in battlegrounds.", SORTS, L, "sortBG")
  W.Card(p, "Look", { folded = true, text = "Size, letters and how see-through it is." })
  Sld(p, "Rows", "How many enemies show before the list stops growing. Alterac Valley has 40 players, Warsong Gulch 10.", 1, 40, 1, L, "rows")
  Sld(p, "Width", "How wide the list is. You can also drag its corner.", 190, 420, 2, L, "width", ListStyle, Px)
  Sld(p, "Row height", "How tall each enemy's row is.", 12, 24, 1, L, "rowHeight", ListStyle, Px)
  Sld(p, "Opacity", "How solid the list is outside battlegrounds. 100% = not see-through.", 0.2, 1, 0.05, L, "alpha", nil, Pct)
  Sld(p, "Opacity in battlegrounds", "How solid the list is in battlegrounds and arenas.", 0.2, 1, 0.05, L, "alphaBG", nil, Pct)
  Drop(p, "Font", "The letters used in the list.", B.SpyData.Fonts(), L, "font", ListStyle)
  Drop(p, "Health bar", "The look of the health bars.", B.SpyData.BARS, L, "bar", ListStyle)
  Chk(p, "Grow upwards", "The title bar sits at the bottom and new rows appear above it.", L, "growUp", ListStyle)
  Chk(p, "Lock the list", "Stops the list being dragged or resized by accident (Move frames still moves it).", L, "locked")
  Chk(p, "Hide when nobody is near", "Open world: the list only appears when an enemy does.", L, "hideEmpty")
  W.Card(p, "When you hover an enemy", { folded = true, text = "What the tooltip shows and where it appears." })
  Chk(p, "Next to the list", "Off: the tooltip appears where the game shows tooltips (bottom right).", L, "tipNear")
  Drop(p, "Where", "Which side of the list the tooltip appears on.", ANCHORS_TIP, L, "tipAnchor")
  Chk(p, "Wins and losses", "How often you have beaten them, and they you.", SP, "DisplayWinLossStatistics")
  Chk(p, "Kill On Sight reasons", "Why you put them on Kill On Sight.", SP, "DisplayKOSReason")
  Chk(p, "Last seen and where", "When and where you saw them last.", SP, "DisplayLastSeen")
end

BUILD.hud = function(p)
  W.Heading(p, "Radar HUD", {
    on = On(H, "enabled", Active, "Show the radar."),
    text = "A see-through radar around your character: enemies are coloured triangles, your group small dots.",
    about = "A triangle turns into an arrow while the enemy runs. Rings: white = your target, red = Kill On Sight, "
      .. "gold = can't be hurt right now. A flag marks the enemy flag carrier. Enemies you no longer see fade out; "
      .. "enemies further away than the radar reaches sit on its edge.",
    extra = { { "Outside battlegrounds too", function() return B.db.hud.world end, function(v) B.db.hud.world = v Active() end,
                "Show the radar in the open world too." } } })
  W.Card(p, "What it shows", { text = "Pick what the radar draws." })
  Chk(p, "Turn with me", "On: up is the way you are facing. Off: north is always up, like the map.", H, "rotate")
  Chk(p, "Arrows for runners", "A running enemy's triangle points the way they are going.", H, "heading")
  Chk(p, "Far enemies on the edge", "Enemies further away than the radar reaches show as small marks on its rim.", H, "edge")
  Chk(p, "My group", "Your teammates as small dots.", H, "friends")
  Chk(p, "Can't-be-hurt rings", "A gold ring while an enemy is in Ice Block, Divine Shield or a similar shield (radar and map).", H, "immune")
  Sld(p, "Names shown", "How many of the nearest enemies get their name written under them.", 0, 10, 1, H, "names")
  W.Card(p, "Size", { text = "How far it reaches and how big it is on screen." })
  Sld(p, "Range", "How far the radar sees around you.", 20, 100, 5, H, "range", HudLayout, Yd)
  Sld(p, "Size", "How big the radar is on screen.", 140, 420, 10, H, "size", HudLayout, Px)
  Sld(p, "Opacity", "How solid the radar is. Lower = more see-through.", 0.2, 1, 0.05, H, "alpha", HudLayout, Pct)
end

BUILD.stealth = function(p)
  W.Heading(p, "Stealth", {
    on = On(S, "alert", nil, "Warn me when an enemy near me goes into stealth."),
    text = "A warning when an enemy near you goes into Stealth, Prowl, Vanish or Shadowmeld, and a mark where they vanished.",
    about = "You only get the warning if your game could see them at that moment (or they come close while already "
      .. "stealthed). A purple circle stays on the radar and map where they disappeared and grows at stealth speed for "
      .. "20 seconds - they can be anywhere inside it.\n\nNothing can show a stealthed enemy after that: the game stops "
      .. "telling your client where they are." })
  W.Buttons(p, { { "Test the warning", function() B.Nearby:Test() end, 130, "Shows a pretend stealth warning." } })
  W.Card(p, "Warning", { text = "When the warning goes off." })
  Sld(p, "Only closer than", "Ignore stealthers further away than this. 0 = warn at any distance.", 0, 150, 5, S, "range", nil,
    function(v) return (v == 0) and "any distance" or (v .. " yd") end)
  Chk(p, "Even with Spy detection off", "Keep the stealth warning in the open world when Spy detection is switched off.",
    SP, "WarnOnStealthEvenIfDisabled", Zone)
  W.Card(p, "Marks", { text = "The purple circle where they vanished." })
  Chk(p, "Marks on the radar and map", "Show the purple circle on the radar and the enemy map.", S, "enabled")
end

BUILD.focus = function(p)
  local FO = B.Focus
  local function RT() return B.db.retarget end
  W.Heading(p, "Focus and keep target", {
    text = "Keep an eye on a second enemy and cast on them without losing your target. And get hunters and rogues back when they drop your target.",
    about = "Focus: with pfUI on, OctoBG uses pfUI's focus (its /focus and focus frame), so there is only one. OctoBG "
      .. "adds casting on your focus with a key (/fcast) and a strip under the focus frame with their cooldowns, range "
      .. "and whether they can be hurt.\n\nKeep target never takes your target away: it only targets someone when you "
      .. "have no target. Auto-attack stops when your target drops (the game does that) - press attack again." })
  W.Live(p, function()
    local _, name = FO:Get()
    local pf = pfUI and pfUI.uf and pfUI.uf.focus
    return "Focus: " .. (name and ("|cffffffff" .. name .. "|r") or "|cff888888none|r")
      .. "    pfUI focus frame: " .. Mark(pf)
      .. "    cast without swapping target: " .. Mark(B.env.superwow)
  end, 1)
  W.Buttons(p, {
    { "Focus my target", function() FO:SetFromTarget() end, 130, "Makes your current target your focus." },
    { "Clear focus", function() FO:Clear() end, 100, "Forgets your focus." },
  })
  W.Card(p, "Focus keys", { text = "The quick way, also in combat: set a key once, then press it any time. Click a box, press the key you want." })
  W.KeyBind(p, "Focus my target", "Your current target becomes your focus. With no target it clears your focus.", "OCTOBG_FOCUS_SET")
  W.KeyBind(p, "Focus under the mouse", "Hover an enemy (in the world or on a unit frame) and press it: they become your focus and your target stays the same.", "OCTOBG_FOCUS_MOUSE")
  W.KeyBind(p, "Target my focus", "Makes your focus your target.", "OCTOBG_FOCUS_TARGET")
  W.KeyBind(p, "Swap target and focus", "Your focus becomes your target and your target becomes your focus - handy for switching between two enemies.", "OCTOBG_FOCUS_SWAP")
  W.Note(p, "Other ways: Alt-click an enemy in the enemy list, or right-click an enemy in the list or on the map and pick Focus. pfUI's /focus works in macros.")
  W.Card(p, "Focus strip", { text = "A small bar under your focus frame: the big spells they used, their range, whether they can be hurt.",
    on = On(function() return B.db.focus end, "strip", nil, "Show the strip under the focus frame.") })
  Chk(p, "Stick it under pfUI's focus", "Off: it stays where you put it with Move frames.", function() return B.db.focus end, "attach")
  W.Card(p, "Focus spells", { text = "Up to three spells for this class that a key casts on your focus - your target stays the same." })
  for i = 1, 3 do
    local n = i
    W.Edit(p, "Spell " .. n, "The spell the key below casts on your focus. Press Enter to save. /fcast Spell Name works in macros too.",
      function() return FO:Spells()[n] end, function(v) FO:Spells()[n] = v end)
    W.KeyBind(p, "Key for spell " .. n, "Press it to cast spell " .. n .. " on your focus - your target stays the same.", "OCTOBG_FOCUS_" .. n)
  end
  W.Buttons(p, { { "Use my class defaults", function()
    local _, class = UnitClass("player")
    if class then B.db.focus.spells[class] = nil end
    O:Refresh()
  end, 160, "Mage: Polymorph, Counterspell, Fire Blast. Priest: Dispel Magic, Silence, Mana Burn. And so on." } })
  W.Card(p, "Keep target", { text = "Hunters and rogues make you lose your target on purpose. These put them back on it." })
  Chk(p, "After Feign Death", "When a hunter feigns death and your target drops, they become your target again.", RT, "enabled")
  Chk(p, "After Vanish / Stealth", "When your target vanishes or stealths, OctoBG targets them again the moment they show up.", RT, "rogue")
  Chk(p, "Marked rogues and druids", "An enemy rogue or druid with Hunter's Mark on them is picked up whenever they show.", RT, "mark")
  Chk(p, "Tell me when it happens", "\"Target: Name (back from Vanish)\" at the top of the screen.", RT, "notify")
  Sld(p, "Wait for them", "How long after they vanished OctoBG still grabs them when they show.", 5, 60, 1, RT,
    "rogueTime", nil, function(v) return v .. " s" end)
  Drop(p, "When a rogue shows again", "Target: only when you have no target. Focus: makes them your focus and leaves your target alone.", B.Retarget.DO, RT, "rogueDo")
end

-- ---------------------------------------------------------------- world PvP (Spy)

local function WorldStatus()
  local NB, spy = B.Nearby, B.db.spy
  if NB:Standing() then return "|cffffd100Waiting:|r the old Spy addon is still switched on (see Overview)." end
  if not spy.Enabled then
    return "|cffff5555Off.|r" .. (NB:StealthOnly() and " Stealth warnings still work." or "")
  end
  if NB.enabledInZone then
    return "|cff55ff55Working here.|r " .. NB:ActiveCount() .. " enemies seen now, " .. NB.n .. " in the Nearby list."
  end
  local pvpType = GetZonePVPInfo()
  local why = "this zone"
  if pvpType == "sanctuary" then why = "this is a sanctuary"
  elseif spy.FilteredZones[GetSubZoneText() or ""] then why = GetSubZoneText() .. " is switched off (below)"
  elseif NB.inInstance or B.zone then why = "you are in a dungeon or battleground (see Where it works)"
  elseif spy.DisableWhenPVPUnflagged then why = "you are not PvP flagged" end
  return "|cffffd100Paused:|r " .. why .. "."
end

local WARN_AS = { { key = "Default", label = "Box at the top" }, { key = "Moveable", label = "Box I place myself" },
                  { key = "ErrorFrame", label = "Red text line (top)" } }
local ANNOUNCE = { { key = "None", label = "Nobody" }, { key = "Self", label = "Only me (chat window)" },
                   { key = "Party", label = "Party" }, { key = "Raid", label = "Raid" },
                   { key = "Guild", label = "Guild" }, { key = "LocalDefense", label = "LocalDefense channel" } }

local function Races()
  local list = { { key = "None", label = "None" } }
  local r = B.SpyData.RACES[B.enemy or "Horde"] or {}
  for i = 1, table.getn(r) do table.insert(list, { key = r[i], label = r[i] }) end
  return list
end

BUILD.world = function(p)
  W.Heading(p, "Detection", {
    on = { function() return B.db.spy.Enabled end, function(v) B.Nearby:SetEnabled(v) end,
           "Spy detection. Off: no Nearby list, sounds or warnings in the open world." },
    text = "Spy, built in: a sound when an enemy player shows up near you, and a big warning for the ones you care about.",
    about = "OctoBG notices enemies when they cast, attack, buff, come close or show a nameplate. Each one goes on the "
      .. "enemy list (Nearby) with a sound. Players on your Kill On Sight list, their guild, a race you pick, and "
      .. "stealthers get a big warning with their name. It also keeps your wins and losses against each player "
      .. "(Statistics). Stealth warnings are on the Stealth page." })
  W.Live(p, WorldStatus, 2)
  W.Card(p, "Where it works", { text = "Places where detection is switched on or off." })
  Chk(p, "In battlegrounds too", "Sounds and warnings inside battlegrounds as well. The battleground enemy list works either way.",
    SP, "EnabledInBattlegrounds", Zone)
  Chk(p, "Pause when not PvP flagged", "No warnings while you cannot be attacked.", SP, "DisableWhenPVPUnflagged", Zone)
  Chk(p, "List unflagged enemies", "Also list enemies who are not PvP flagged (they can't attack you).", SP, "unflagged")
  Chk(p, "Quiet on a flight path", "Flight paths fly past lots of enemies - no new ones while you are on one.", SP, "StopAlertsOnTaxi")
  W.Card(p, "The Nearby list", { text = "The enemies around you, on the enemy list's Nearby tab." })
  Chk(p, "Open the list on detection", "Opens the enemy list again when an enemy shows up, even if you closed it.", SP, "ShowOnDetection")
  Chk(p, "Jump to the Nearby tab", "Switches the enemy list to Nearby when an enemy shows up.", SP, "ShowNearbyList")
  Sld(p, "Keep them listed for", "How long an enemy stays (greyed) after you lose sight of them. 0 = remove at once.",
    0, 120, 1, SP, "RemoveUndetectedTime", nil, function(v) return (v == 0) and "at once" or (v .. " min") end)
  W.Buttons(p, {
    { "Clear the Nearby list", function() B.Nearby:Clear() end, 150, "Empties the Nearby list now." },
    { "Show the list", function() B.Roster:Open() B.Roster:SetMode(1) end, 110, "Opens the enemy list on Nearby." },
  })
  W.Card(p, "Sounds and warnings", { text = "How you are told that an enemy showed up." })
  Chk(p, "Sounds", "A sound for every new enemy. Shift-click the list's clear button switches them too.", SP, "EnableSound")
  Chk(p, "Sounds only for Kill On Sight", "Stay quiet unless the enemy is on your Kill On Sight list.", SP, "OnlySoundKoS")
  Chk(p, "Quiet in battlegrounds", "No detection sounds in battlegrounds and arenas.", SP, "MuteSoundInBattlegrounds")
  W.Space(p, 2)
  Drop(p, "Show warnings as", "Where the big warning appears.", WARN_AS, SP, "DisplayWarnings", function() B.Nearby:PlaceBox() end)
  W.Buttons(p, {
    { "Place the warning box", function()
      B.db.spy.DisplayWarnings = "Moveable"
      B.Nearby:MoveBox(true)
    end, 160, "Shows the box so you can drag it. Click Done when it is where you want it." },
    { "Done", function() B.Nearby:MoveBox(false) end, 70, "Puts the box away." },
    { "Test", function() B.Nearby:Test() end, 70, "Shows a pretend warning." },
  })
  W.Card(p, "Who gets a big warning", { text = "These enemies get a warning with their name, not just a sound." })
  Chk(p, "Kill On Sight players", "Players on your Kill On Sight list.", SP, "WarnOnKOS")
  Chk(p, "Their guild", "Anyone in the same guild as a Kill On Sight player.", SP, "WarnOnKOSGuild")
  Chk(p, "One race", "Every enemy of the race you pick below.", SP, "WarnOnRace")
  W.Dropdown(p, "Race", "The race to warn about.", Races(), function() return B.db.spy.SelectWarnRace end,
    function(v) B.db.spy.SelectWarnRace = v end)
  W.Card(p, "Tell others", { folded = true, text = "Post new enemies to your group or guild. You can always do it by hand: right-click an enemy, Announce." })
  W.Dropdown(p, "Post new enemies to", "Posts \"[Spy] Player detected: Name - Level 60 Night Elf Rogue - Duskwood\". Asks first for chat channels.",
    ANNOUNCE, function() return B.db.spy.Announce end,
    function(v)
      if v == "None" or v == "Self" then
        B.db.spy.Announce = v
      else
        O.pendingAnnounce = v
        StaticPopup_Show("OCTOBG_SPY_ANNOUNCE", string.lower(v))
      end
    end)
  Chk(p, "Only Kill On Sight players", "Only post players on your Kill On Sight list.", SP, "OnlyAnnounceKoS")
  W.Card(p, "Quiet towns", { folded = true, text = "Neutral towns full of enemies who can't fight - ticked ones get no detection. Sanctuaries are always quiet." })
  local D = B.SpyData
  for i = 1, table.getn(D.SANCTUARIES) do
    local z = D.SANCTUARIES[i]
    W.Check(p, z, "No detection in " .. z .. ".", function() return B.db.spy.FilteredZones[z] end, function(v)
      B.db.spy.FilteredZones[z] = v or nil
      Zone()
    end)
  end
end

BUILD.kos = function(p)
  local P = B.People
  W.Heading(p, "Kill On Sight", {
    text = "Your list of players to watch for: they go to the top of the enemy list, get a skull and a red ring, and a big warning. Ignored players are never shown.",
    about = "Add someone: Shift-click them in the enemy list (Ctrl-click to ignore), right-click them for the menu, use "
      .. "the key bindings on your target, or type the name below.\n\nReasons: right-click a Kill On Sight player and "
      .. "pick a reason (or type your own). It shows in their tooltip, the warning and the statistics." })
  W.Live(p, function()
    local k, i = 0, 0
    for _ in pairs(P:KOSList()) do k = k + 1 end
    for _ in pairs(P:IgnoreList()) do i = i + 1 end
    return "|cffff5555" .. k .. " on Kill On Sight|r, " .. i .. " ignored (" .. P:Realm() .. ", " .. (UnitFactionGroup("player") or "?") .. ")"
  end)
  W.Buttons(p, {
    { "Kill On Sight list", function() B.Roster:Open() B.Roster:SetMode(4) end, 140, "Opens the enemy list on its Kill On Sight tab." },
    { "Ignore list", function() B.Roster:Open() B.Roster:SetMode(3) end, 110, "Opens the enemy list on its Ignore tab." },
    { "Statistics", function() B.Stats:Show() end, 100, "Every enemy you have met." },
  })
  W.Card(p, "Add a name", { text = "Type a name and press Enter. Type it again to take it off." })
  W.Edit(p, "Kill On Sight", "Adds the player to Kill On Sight (or takes them off).",
    function() return "" end, function(v)
      v = string.gsub(v or "", "%s", "")
      if v ~= "" then P:ToggleKOS(v) end
    end)
  W.Edit(p, "Ignore", "Adds the player to the ignore list (or takes them off).",
    function() return "" end, function(v)
      v = string.gsub(v or "", "%s", "")
      if v ~= "" then P:ToggleIgnore(v) end
    end)
  W.Card(p, "My characters", { text = "Whether your other characters use the same list." })
  Chk(p, "Share between my characters", "All your characters on this realm and faction use one list. Off: each character keeps its own.",
    SP, "ShareKOSBetweenCharacters")
end

BUILD.data = function(p)
  local P = B.People
  W.Heading(p, "Statistics", {
    text = "Every enemy player OctoBG has seen is remembered: level, class, guild, where and when - and your wins and losses against them.",
    about = "Killing them (\"You have slain X\") counts as a win. Dying counts as a loss to whoever hit you last." })
  W.Live(p, function()
    local n, w, l = 0, 0, 0
    for _, r in pairs(P:Store().players) do
      n = n + 1
      w = w + (tonumber(r.wins) or 0)
      l = l + (tonumber(r.loses) or 0)
    end
    return n .. " players remembered - |cff40ff00" .. w .. " wins|r, |cff0070dd" .. l .. " losses|r"
  end)
  W.Buttons(p, {
    { "Open statistics", function() B.Stats:Show() end, 130, "The statistics window: every player, sortable." },
    { "Forget old now", function() P:Purge() end, 120, "Forgets old players now, using the setting below (it also runs every login)." },
  })
  W.Card(p, "Forget old players", { text = "Keeps the list small by forgetting people you have not seen in a while." })
  Drop(p, "Not seen for", "Players not seen for this long are forgotten.", P.PURGE, SP, "PurgeData")
  W.Space(p, 2)
  Chk(p, "Kill On Sight players too", "Off: Kill On Sight players are never forgotten.", SP, "PurgeKoS")
  Chk(p, "People I fought too", "Off: anyone you won or lost against is never forgotten.", SP, "PurgeWinLossData")
  W.Card(p, "Share with Spy users", { text = "Swap sightings with your group and guild - friends still using Spy see yours, and you see theirs." })
  Chk(p, "Share what I see", "Each new enemy you see is sent to your group and guild (hidden, nothing in chat).", SP, "ShareData")
  Chk(p, "Use what others share", "Enemies others report join your Nearby list (greyed). Kill On Sight ones still warn you.", SP, "UseData")
  Chk(p, "Show it in chat", "Prints what arrives, to check sharing works.", SP, "CommDebug")
  W.Card(p, "Minimap", { folded = true, text = "For druids' Track Humanoids and similar tracking on the minimap." })
  Chk(p, "Class and level on the minimap", "Known enemies under the minimap get [60 Rogue] in the tooltip.", SP, "MinimapDetails")
  Chk(p, "Count minimap names", "An enemy name in a minimap tooltip counts as seeing them.", SP, "MinimapDetection")
end

-- ---------------------------------------------------------------- cooldowns

local ANCHORS = { { key = "TOP", label = "Above the plate" }, { key = "BOTTOM", label = "Below the plate" },
                  { key = "LEFT", label = "Left of the plate" }, { key = "RIGHT", label = "Right of the plate" } }
local GROWS = { { key = "CENTER", label = "Centred row" }, { key = "RIGHT", label = "Row, rightwards" },
                { key = "LEFT", label = "Row, leftwards" }, { key = "DOWN", label = "Column, downwards" },
                { key = "UP", label = "Column, upwards" } }
local TIMERPOS = { { key = "BOTTOM", label = "Under the icon" }, { key = "CENTER", label = "On the icon" },
                   { key = "TOP", label = "Over the icon" } }

BUILD.cdbars = function(p)
  W.Heading(p, "Bars and icons", {
    text = "See which big spells an enemy has used and when they will have them again: bars for your target, icons over every enemy's nameplate.",
    about = "Bars: a green strip under a bar means that enemy can't be hurt right now (Ice Block, Divine Shield). An "
      .. "orange end means their talents might already have it back. Along the bottom: diminishing returns. Right-click "
      .. "a bar to stop showing that spell.\n\nNameplate icons: every enemy nameplate gets a row of the spells that "
      .. "enemy has used, with countdowns, so you can watch the whole fight. Works with pfUI's nameplates." })
  W.Card(p, "Bars for your target", { text = "A bar per big spell your target has used, counting down until they can use it again.",
    on = On(C, "bars", nil, "Show the cooldown bars. They work everywhere: battlegrounds, world PvP, duels.") })
  Chk(p, "Show whose bars they are", "A line on top with the enemy's name.", C, "showWho")
  Chk(p, "Keep the last enemy", "When you lose your target, their bars stay (dimmed) until you target someone else.", C, "stickyTarget",
    function() B.CD:OnTargetChanged() end)
  Chk(p, "Follow the enemy carrier", "Warsong Gulch: with nobody targeted, the bars show the enemy flag carrier's.", C, "efcFallback")
  Chk(p, "Right-click hides a spell", "Right-click a bar to stop showing that spell. Off: the bars ignore the mouse.", C, "interactiveBars")
  W.Buttons(p, {
    { "Show example bars", function()
      B.CD:LoadSamples()
      B.CD.target, B.CD.lastTarget, B.CD.stale = B.CD.SAMPLE, B.CD.SAMPLE, false
    end, 140, "Fills the bars with a pretend enemy until you target something." },
    { "Clear", function()
      B.CD:Clear()
      B.CD:OnTargetChanged()
    end, 80, "Forgets every cooldown seen so far." },
  })
  W.Card(p, "Bar look", { folded = true, text = "Size, colours and which way the bars stack." })
  Chk(p, "Spell icons", "An icon at the start of each bar.", C, "showIcon")
  Chk(p, "Icons only", "A small row of icons with timers instead of bars.", C, "iconOnly")
  Chk(p, "Grow upwards", "New bars stack upwards instead of downwards.", C, "growUp",
    function(v) if B.CDBars then B.CDBars:SetGrowUp(v) end end)
  Chk(p, "Bars empty out", "Bars start full and empty as the cooldown ends. Off: they fill up.", C, "invertFill")
  Chk(p, "Class colours", "Bars in the enemy's class colour. Off: blue, then yellow, then red as time runs out.", C, "classColors")
  W.Space(p, 2)
  Sld(p, "Width", "How wide the bars are.", 120, 400, 2, C, "barWidth", nil, Px)
  Sld(p, "Bar height", "How tall each bar is.", 12, 40, 1, C, "barHeight", nil, Px)
  Sld(p, "Most bars", "The most spells shown at once.", 1, 20, 1, C, "maxBars")
  Sld(p, "Text size", "Size of the spell names and timers.", 7, 20, 1, C, "fontSize")
  Sld(p, "Opacity", "How solid the bars are. Lower = more see-through.", 0.1, 1, 0.05, C, "alpha", nil, Pct)
  W.Card(p, "Icons on nameplates", { text = "Small icons above every enemy's nameplate for the spells they have used. Press V to show nameplates.",
    on = On(C, "nameplates", nil, "Show cooldown icons on nameplates.") })
  B.CDPlates:AttachPreview(W.Box(p, 110))
  W.Buttons(p, {
    { "Test on real nameplates", function() B.CDPlates:Test(60) end, 180,
      "Puts pretend cooldowns on every nameplate you can see for a minute. Press V (enemies) or Shift-V (friends) to show nameplates, e.g. in a city." },
    { "Stop test", function() B.CDPlates:Test(0) end, 90, "Removes the pretend cooldowns." },
  })
  Chk(p, "Only the big ones", "Only trinkets, can't-be-hurt spells, escapes and big damage cooldowns.", C, "nameplateImportantOnly")
  W.Card(p, "Icon position", { folded = true, text = "Where the icons sit around the nameplate and how big they are." })
  Drop(p, "Attach", "Which side of the nameplate the icons go.", ANCHORS, C, "nameplateAnchor")
  Drop(p, "Grow", "Which way new icons are added.", GROWS, C, "nameplateGrow")
  Sld(p, "Move sideways", "Shift the icons left (minus) or right.", -150, 150, 1, C, "nameplateXOffset", nil, Px)
  Sld(p, "Move up / down", "Shift the icons down (minus) or up.", -80, 120, 1, C, "nameplateYOffset", nil, Px)
  Sld(p, "Icon size", "How big each icon is.", 8, 40, 1, C, "nameplateIconSize", nil, Px)
  Sld(p, "Gap between icons", "Space between the icons.", 0, 12, 1, C, "nameplateSpacing", nil, Px)
  Sld(p, "Most icons", "The most icons over one enemy.", 1, 10, 1, C, "nameplateMaxIcons")
  Sld(p, "Opacity", "How solid the icons are.", 0.1, 1, 0.05, C, "nameplateAlpha", nil, Pct)
  W.Card(p, "Icon border and timer", { folded = true, text = "Background, border and countdown text of the icons." })
  Chk(p, "Background", "A dark box behind the row of icons.", C, "nameplateBackdrop")
  W.Color(p, "Background colour", "Colour of the box behind the icons.", function() return B.CD.GetColor("nameplateBg") end,
    function(r, g, b, a) B.CD.SetColor("nameplateBg", r, g, b, a) end)
  Chk(p, "Border", "A border around each icon.", C, "nameplateBorder")
  W.Color(p, "Border colour", "Colour of the icon borders.", function() return B.CD.GetColor("nameplateBorder") end,
    function(r, g, b, a) B.CD.SetColor("nameplateBorder", r, g, b, a) end)
  Chk(p, "Border in class colour", "The border takes the class colour of the spell instead.", C, "nameplateBorderClass")
  Chk(p, "Countdown", "Seconds left written on each icon.", C, "nameplateShowTimer")
  Sld(p, "Border thickness", "How thick the borders are.", 0, 4, 1, C, "nameplateBorderSize", nil, Px)
  Sld(p, "Countdown size", "How big the countdown text is.", 6, 20, 1, C, "nameplateTimerSize")
  Drop(p, "Countdown position", "Where the countdown sits on the icon.", TIMERPOS, C, "nameplateTimerPos")
end

BUILD.cdtrack = function(p)
  W.Heading(p, "Tracking and profile", {
    text = "How OctoBG works out cooldown lengths, the can't-be-hurt timers, and saving or sharing your cooldown settings.",
    about = "OctoBG sees every spell an enemy casts. How long its cooldown is comes from the server, a built-in list, or "
      .. "what it has seen before. Talents that shorten cooldowns can't be seen, so OctoBG learns them: when an enemy "
      .. "uses a spell again early, that is their real cooldown, remembered for that player." })
  W.Card(p, "Tracking", { text = "How cooldowns are counted." })
  Chk(p, "Learn real cooldowns", "Remember each enemy's real cooldowns when they use a spell again sooner than expected.", C, "learnCooldowns")
  Chk(p, "Show the maybe-ready part", "The end of a bar turns orange (and the timer gets a ~) when talents might already have the spell back.", C, "showUncertainty")
  Sld(p, "Ignore shorter than", "Spells with a cooldown shorter than this are not shown at all.", 0, 30, 0.5, C, "minDuration", nil, Sec)
  W.Card(p, "Can't be hurt", { text = "A green strip while an enemy is in Ice Block, Divine Shield or a similar shield." })
  Chk(p, "Show the green strip", "Under the cooldown bar while the shield is up.", C, "showImmuneBars")
  Chk(p, "Always show its timer", "Off: the timer only appears for the last half.", C, "immuneAlwaysShowTimer")
  Sld(p, "Strip height", "How thick the green strip is.", 4, 20, 1, C, "immuneBarHeight", nil, Px)
  W.Card(p, "Learned cooldowns", { folded = true, text = "Cooldowns OctoBG has learned from watching enemies." })
  W.Live(p, function()
    local n, c = 0, 0
    for _ in pairs(B.db.cdLearned) do n = n + 1 end
    for _ in pairs(B.db.cdCollected) do c = c + 1 end
    return n .. " players with learned cooldowns, " .. c .. " spell lengths known."
  end)
  W.Buttons(p, {
    { "List in chat", function() B.CD:PrintLearned() end, 110, "Prints what has been learned." },
    { "Forget learned", function() B.CD:ForgetLearned() B:Print("learned cooldowns forgotten") end, 120,
      "Throws away every learned cooldown (they will be learned again)." },
    { "Print spell IDs", function()
      B.db.cd.debugSpellID = not B.db.cd.debugSpellID
      B:Print("printing enemy spell ids " .. (B.db.cd.debugSpellID and "on" or "off"))
    end, 120, "Prints each enemy cooldown as it is seen - for reporting a wrong one." },
  })
  W.Card(p, "Profile", { folded = true, text = "Copy all your cooldown settings to share with a friend or keep as a backup. Old EnemyCooldowns profiles (ECD1...) work too." })
  local function Box()
    local row = W.Row(p, 24, 0, 6)
    local eb = W.EditBox(row, W.CW - 4)
    eb:SetPoint("LEFT", row, "LEFT", 2, 0)
    return eb
  end
  W.Note(p, "Your settings (copy this):")
  local out = Box()
  table.insert(p.items, { Refresh = function()
    out:SetText(B.CD:Export())
    out:SetCursorPosition(0)
  end })
  W.Buttons(p, {
    { CopyToClipboard and "Copy to clipboard" or "Select all", function()
      local text = B.CD:Export()
      if CopyToClipboard and pcall(CopyToClipboard, text) then
        B:Print("profile copied - paste it with Ctrl+V")
      else
        out:SetFocus()
        out:HighlightText()
        B:Print("now press Ctrl+C")
      end
    end, 150, "Copies the text so you can paste it anywhere." },
  })
  W.Note(p, "Paste a profile here, then Import:")
  local inp = Box()
  W.Buttons(p, {
    { "Import", function()
      local ok, msg = B.CD:Import(inp:GetText())
      B:Print(msg)
      if ok then
        inp:SetText("")
        inp:ClearFocus()
      end
    end, 100, "Replaces your cooldown settings with the pasted ones." },
    { "Restore cooldown defaults", function()
      B.CD:ResetDefaults()
      B:Print("enemy cooldown settings back to defaults")
    end, 190, "Only the cooldown settings go back to how they started; the rest of OctoBG stays." },
  })
end

BUILD.dr = function(p)
  W.Heading(p, "Diminishing returns", {
    on = On(C, "showDR", nil, "Show diminishing returns under the cooldown bars and in the enemy list tooltip."),
    text = "Stuns, fears and roots get shorter each time on the same enemy. This shows what the next one will do (\"Stun 50%\", \"Fear IMMUNE\").",
    about = "Crowd control on the same enemy works full, then half as long, then a quarter, then not at all - until 15 "
      .. "seconds pass without any. OctoBG counts each one it sees land, so you know when yours will be wasted." })
  W.Card(p, "Look", { text = "Size of the small boxes under the cooldown bars." })
  Sld(p, "Box width", "How wide each box is.", 24, 80, 1, C, "drWidth", nil, Px)
  Sld(p, "Box height", "How tall each box is.", 8, 24, 1, C, "drHeight", nil, Px)
end

BUILD.alerts = function(p)
  W.Heading(p, "Cooldown alerts", {
    text = "A warning when an enemy uses something big: Ice Block, Divine Shield, Vanish, Blink, a trinket, Recklessness...",
    about = "Warns about shields (Ice Block, Divine Shield), escapes (Vanish, Blink, trinket) and big damage cooldowns "
      .. "(Recklessness, Arcane Power, Bestial Wrath...). The same spell from the same enemy only warns once per 1.5 seconds." })
  W.Buttons(p, { { "Test the alerts", function() B.CD:TestAlert() end, 140, "Shows a pretend alert." } })
  W.Card(p, "On screen", { text = "How the warning looks and sounds." })
  Chk(p, "Enemy flag carrier", "Always tell me when the enemy flag carrier uses something (\"EFC Name: Ice Block!\"), whatever else is off.", C, "alertEFC")
  Chk(p, "Text on screen", "\"Name: Ice Block\" in their class colour.", C, "alertText")
  Chk(p, "Flash the screen", "The edges of the screen flash.", C, "alertFlash")
  Chk(p, "Play a sound", "Plays the sound picked below.", C, "alertSound")
  W.Dropdown(p, "Sound", "The alert sound. Picking one plays it.", B.CD.SOUNDS,
    function() return B.db.cd.alertSoundFile end,
    function(v)
      B.db.cd.alertSoundFile = v
      PlaySoundFile(B.CD.SoundFile(v))
    end)
  W.Card(p, "Chat", { folded = true, text = "Tell your group in chat when an enemy uses something big." })
  W.Check(p, "Post in chat", "Posts \"Name used Ice Block (5:00 cooldown)\" to your group. Asks you first.",
    function() return B.db.cd.alertAnnounce end,
    function(v)
      B.db.cd.alertAnnounce = false
      if v then StaticPopup_Show("OCTOBG_CD_ANNOUNCE") end
    end)
  Drop(p, "Post to", "Auto: battleground chat in a battleground, else raid, else party.",
    { { key = "PARTY", label = "Auto" }, { key = "BATTLEGROUND", label = "Battleground (/bg)" },
      { key = "RAID", label = "Raid" }, { key = "SAY", label = "Say" }, { key = "YELL", label = "Yell" } }, C, "alertChannel")
end

-- ---------------------------------------------------------------- setup

BUILD.general = function(p)
  W.Heading(p, "General", { text = "Size of the panels, the minimap button, how far you can see, and help when something looks wrong." })
  W.Card(p, "Panels and button", { text = "Settings for all of OctoBG's panels at once." })
  Sld(p, "Panel size", "Makes every OctoBG panel bigger or smaller.", 0.6, 1.6, 0.05, DB, "scale", function() U.ApplyScale() end, Pct)
  W.Check(p, "Minimap button", "Left-click it to open these options, right-click for quick switches, drag it around the minimap.",
    function() return not B.db.minimap.hide end,
    function(v) B.db.minimap.hide = not v if B.Minimap then B.Minimap:Update() end end)
  W.Card(p, "View distance", { text = "See players and nameplates from further away. It can't make the game send you enemies from further away." })
  W.Buttons(p, {
    { "Max view distance", function() O:MaxView(false) end, 150, "Raises the game's draw distance and nameplate range. Saved when you log out." },
    { "Put it back", function() O:MaxView(true) end, 110, "Back to your old settings." },
  })
  W.Live(p, function()
    local max, drop = B.Tracker:ReachSummary()
    local here = (B.Tracker.reachZone and max > 0)
      and ("Furthest enemy seen here: " .. math.floor(max) .. " yd" .. (drop and (", they disappear at about " .. math.floor(drop) .. " yd") or ""))
      or "Furthest enemy seen here: nothing measured yet."
    local n = 0
    for _ in pairs(B.db.reach) do n = n + 1 end
    return here .. "  |cff999999(" .. n .. " zones saved)|r"
  end)
  W.Buttons(p, { { "List zones in chat", function() O:PrintReach() end, 140,
    "How far away enemies were seen in each zone, and where they disappear (the server's limit)." } })
  W.Card(p, "Facing", { text = "The radar and arrows need to know which way you face. OctoBG learns it the first time you run in a straight line." })
  W.Live(p, function()
    return B.Map:CalibrationDone() and "|cff55ff55Learned.|r" or "|cffffd100Still learning - run forward for a few seconds.|r"
  end)
  W.Buttons(p, { { "Learn again", function() B.Map:ResetCalibration() B:Print("run forward in a straight line for a few seconds") end, 110,
    "If the radar turns the wrong way, click this and run forward for a few seconds." } })
  W.Card(p, "Something wrong?", { text = "Use these when reporting a problem." })
  W.Buttons(p, {
    { "Errors", function() SlashCmdList["OCTOBG"]("errors") end, 80, "Lists any errors OctoBG caught this session." },
    { "Probe", function() SlashCmdList["OCTOBG"]("probe") end, 80, "Prints what the game reports for positions and the map - paste it in a bug report." },
    { "Reset folded cards", function() O:ResetCards() end, 140,
      "Every card in these options goes back to open or shut as it started." },
  })
end

BUILD.interact = function(p)
  local IN = B.Interact
  W.Heading(p, "Interact key", {
    text = "One key that right-clicks the nearest NPC or object within 5 yards - no aiming with the mouse.",
    about = "Warsong Gulch: return your dropped flag the moment you reach it, or grab theirs.\nArathi Basin / Alterac "
      .. "Valley: click a banner or flag to attack it.\nAnywhere: talk to an NPC, open a chest or door, loot a body.\n\n"
      .. "/obg interact does the same as the key (for a macro)." })
  W.Live(p, function()
    if IN:Available() then return "|cff55ff55Ready|r - set a key below." end
    return "|cffff7a3aNeeds one small file|r - the game can't do this by itself. See \"Installing it\" below."
  end)
  W.Card(p, "Key", { text = "Pick the key you want to use." })
  W.KeyBind(p, "Key", "The key that interacts with the nearest thing.", "OCTOBG_INTERACT")
  W.Buttons(p, { { "Try it", function() IN:Use() end, 80, "Right-clicks the nearest NPC or object now." } })
  W.Card(p, "Installing it (once)", { folded = IN:Available(), text = "The game and your other DLLs can't click objects for an addon. One free file adds it." })
  W.Note(p, "1. Download |cffffd100interact.dll|r from " .. IN.URL .. " (Releases).\n"
    .. "2. Put it in your game folder, next to WoW.exe.\n"
    .. "3. Open |cffffd100dlls.txt|r in that folder and add a line: interact.dll\n"
    .. "4. Restart the game. The line above turns green.", 0, true)
end
BUILD.tidy = function(p)
  local BT = B.BGTidy
  local function TD() return B.db.tidy end
  local function AV() return B.db.avmode end
  W.Heading(p, "Clean screen", {
    text = "Less clutter in battlegrounds: hide what OctoBG already shows, and a mode with nameplates for enemy players only.",
    about = "Everything here goes back the moment you untick it." })
  W.Card(p, "The game's score frame", { text = "The bases / flags / resources frame at the top of the screen in battlegrounds." })
  Chk(p, "Hide it in battlegrounds", "OctoBG's flag and timer panels show the same (and more).", TD, "scoreFrame",
    function() BT:ScoreFrame() end)
  W.Card(p, "BigWigs' battleground timers", { text = "BigWigs draws its own Arathi Basin and Alterac Valley bars." })
  Chk(p, "Hide BigWigs' timers while OctoBG's run", "In Arathi Basin and Alterac Valley, with the Timers panel on: "
    .. "BigWigs' base / tower / start bars are left out (BigWigs itself is not changed).", TD, "bigwigs")
  W.Live(p, function()
    if not BigWigs then return "|cff888888BigWigs isn't loaded - nothing to hide.|r" end
    return BT.bwDone and "|cff55ff55BigWigs found|r - its battleground bars follow this switch." or "BigWigs found; its battleground modules load when you enter one."
  end)
  W.Card(p, "AV mode", { text = "Nameplates for enemy PLAYERS only: no NPCs (guards, the hundreds of Alterac Valley mobs), no friendly plates." })
  W.Check(p, "AV mode", "On: enemy player plates are switched on and everything else is hidden. Off: your nameplate "
    .. "settings come back as they were (pfUI's too).", function() return B.db.avmode.on end, function(v) BT:SetAV(v) end)
  Chk(p, "AV mode button on screen", "A small button to switch it - place it with Move frames at the top.", AV, "button",
    function() BT:PaintButton() end)
  W.KeyBind(p, "AV mode key", "A key that switches AV mode on and off.", "OCTOBG_AVMODE")
  W.Note(p, "/obg avmode switches it too (/obg avmode on, /obg avmode off).")
end

-- ---------------------------------------------------------------- spell filter page

local CLASSES ={ "WARRIOR", "MAGE", "ROGUE", "PRIEST", "WARLOCK", "PALADIN", "SHAMAN", "DRUID", "HUNTER", "OTHERS" }

local function FilterPage(content)
  local D = B.CDData
  local CD = B.CD
  local K = W.C
  local p = { frame = CreateFrame("Frame", nil, content), items = {}, rows = {}, cls = {} }
  local f = p.frame
  f:SetAllPoints(content)
  f:Hide()
  local sel, search = "WARRIOR", ""

  local head = W.Font(f:CreateFontString(nil, "OVERLAY"), 17, K.text[1], K.text[2], K.text[3])
  head:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -14)
  head:SetText("Spell filter")
  local line = W.Fill(f, K.line, 1, "ARTWORK")
  line:SetHeight(1)
  line:SetPoint("TOPLEFT", head, "BOTTOMLEFT", -2, -8)
  line:SetPoint("RIGHT", f, "RIGHT", -16, 0)
  local note = W.Font(f:CreateFontString(nil, "OVERLAY"), 11, K.dim[1], K.dim[2], K.dim[3])
  note:SetPoint("TOPLEFT", line, "BOTTOMLEFT", 2, -8)
  note:SetWidth(W.WIDTH + 10)
  note:SetJustifyH("LEFT")
  note:SetSpacing(3)
  note:SetText("Ticked spells are tracked; untick one to hide it everywhere (bars, nameplates, list). "
    .. "Hiding is by name, so every rank goes at once. Right-clicking a cooldown bar does the same.")

  local lab = W.Font(f:CreateFontString(nil, "OVERLAY"), 12, K.text[1], K.text[2], K.text[3])
  lab:SetPoint("TOPLEFT", note, "BOTTOMLEFT", 0, -14)
  lab:SetText("Search")
  local box = W.EditBox(f, 180)
  box:SetPoint("LEFT", lab, "RIGHT", 12, 0)
  box:SetScript("OnEscapePressed", function()
    this:SetText("")
    this:ClearFocus()
  end)

  -- the spells, in a flat box
  local frame = CreateFrame("Frame", nil, f)
  frame:SetPoint("TOPLEFT", lab, "BOTTOMLEFT", 136, -12)
  frame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 44)
  W.Flat(frame, K.field, 0.9, K.line)
  local list = CreateFrame("ScrollFrame", "OctoBGFilterScroll", frame, "UIPanelScrollFrameTemplate")
  list:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -6)
  list:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -26, 6)
  local child = CreateFrame("Frame", nil, list)
  child:SetWidth(320)
  child:SetHeight(10)
  list:SetScrollChild(child)
  W.FlatScroll(list)
  p.listTop = lab

  local function Entries()
    local out = {}
    if search ~= "" then
      local seen = {}
      for class, spells in pairs(D.CLASS_SPELLS) do
        for i = 1, table.getn(spells) do
          local n = spells[i]
          if not seen[n] and string.find(string.lower(n), string.lower(search), 1, true) then
            seen[n] = true
            table.insert(out, { name = n, class = class })
          end
        end
      end
      table.sort(out, function(a, b) return a.name < b.name end)
    else
      local spells = D.CLASS_SPELLS[sel] or {}
      for i = 1, table.getn(spells) do table.insert(out, { name = spells[i], class = sel }) end
    end
    return out
  end

  local function Row(i)
    if p.rows[i] then return p.rows[i] end
    local r = CreateFrame("Frame", nil, child)
    r:SetWidth(310)
    r:SetHeight(24)
    r.cb = W.CheckBox(r, 16)
    r.cb:SetPoint("LEFT", r, "LEFT", 2, 0)
    r.cb:SetScript("OnClick", function()
      CD:SetBlocked(this.spell, not this:GetChecked(), this.class)
    end)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetWidth(18)
    r.icon:SetHeight(18)
    r.icon:SetPoint("LEFT", r.cb, "RIGHT", 8, 0)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.text = W.Font(r:CreateFontString(nil, "OVERLAY"), 11, K.text[1], K.text[2], K.text[3])
    r.text:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
    p.rows[i] = r
    return r
  end

  function p.Fill()
    for i = 1, table.getn(p.cls) do
      local b = p.cls[i]
      local on = (search == "" and b.class == sel)
      if on then b.hl:Show() b.bar:Show() else b.hl:Hide() b.bar:Hide() end
      if on then b.text:SetTextColor(1, 1, 1) else b.text:SetTextColor(K.dim[1], K.dim[2], K.dim[3]) end
    end
    local e = Entries()
    for i = 1, table.getn(e) do
      local r = Row(i)
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", child, "TOPLEFT", 4, -4 - (i - 1) * 24)
      r.cb.spell, r.cb.class = e[i].name, e[i].class
      r.cb:SetChecked(not CD:IsBlocked(e[i].name) and 1 or nil)
      local cur, got = D.SPELLS[e[i].name], B.db.cdCollected[e[i].name]
      r.icon:SetTexture((cur and cur.texture) or (got and got.texture) or "Interface\\Icons\\INV_Misc_QuestionMark")
      if search ~= "" then
        r.text:SetText(e[i].name .. "  |cff888888" .. string.lower(e[i].class) .. "|r")
      else
        r.text:SetText(e[i].name)
      end
      r:Show()
    end
    for i = table.getn(e) + 1, table.getn(p.rows) do p.rows[i]:Hide() end
    child:SetHeight(math.max(10, table.getn(e) * 24 + 8))
    list:UpdateScrollChildRect()
  end

  for i = 1, table.getn(CLASSES) do
    local class = CLASSES[i]
    local b = CreateFrame("Button", nil, f)
    b:SetWidth(126)
    b:SetHeight(22)
    b:SetPoint("TOPLEFT", p.listTop, "BOTTOMLEFT", 0, -12 - (i - 1) * 24)
    W.Flat(b, K.btn, 1, K.line)
    b.hl = W.Fill(b, K.accent, 0.18, "BORDER")
    b.hl:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
    b.hl:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
    b.hl:Hide()
    b.bar = W.Fill(b, K.accent, 1, "ARTWORK")
    b.bar:SetWidth(2)
    b.bar:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
    b.bar:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 1, 1)
    b.bar:Hide()
    local hov = W.Fill(b, { 1, 1, 1 }, 0.06, "HIGHLIGHT")
    hov:SetAllPoints(b.hl)
    local ic = b:CreateTexture(nil, "ARTWORK")
    ic:SetWidth(16)
    ic:SetHeight(16)
    ic:SetPoint("LEFT", b, "LEFT", 6, 0)
    ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    ic:SetTexture(D.CLASS_ICONS[class] or "Interface\\Icons\\INV_Misc_QuestionMark")
    b.text = W.Font(b:CreateFontString(nil, "OVERLAY"), 11, K.text[1], K.text[2], K.text[3])
    b.text:SetPoint("LEFT", ic, "RIGHT", 6, 0)
    b.text:SetText(class == "OTHERS" and "Items / other" or (string.sub(class, 1, 1) .. string.lower(string.sub(class, 2))))
    b.class = class
    b:SetScript("OnClick", function()
      sel = this.class
      search = ""
      box:SetText("")
      p.Fill()
    end)
    p.cls[i] = b
  end

  box:SetScript("OnTextChanged", function()
    search = string.gsub(this:GetText() or "", "^%s*(.-)%s*$", "%1")
    p.Fill()
  end)

  local function All(blocked)
    local e = Entries()
    for i = 1, table.getn(e) do CD:SetBlocked(e[i].name, blocked, e[i].class) end
    p.Fill()
  end
  local show = W.Button(f, "Track all", 110, 22)
  show:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 148, 12)
  show:SetScript("OnClick", function() All(false) end)
  local hide = W.Button(f, "Hide all", 110, 22)
  hide:SetPoint("LEFT", show, "RIGHT", 6, 0)
  hide:SetScript("OnClick", function() All(true) end)
  local hint = W.Font(f:CreateFontString(nil, "OVERLAY"), 10, K.dim[1], K.dim[2], K.dim[3])
  hint:SetPoint("LEFT", hide, "RIGHT", 8, 0)
  hint:SetText("(the class or search shown)")

  table.insert(p.items, { Refresh = p.Fill })
  return p
end

-- ---------------------------------------------------------------- window

-- The topic list. Combat text and threat moved to pfUI Octo.
O.SECTIONS = {
  { "start", "Overview" },
  { nil, "Battlegrounds" },
  { "map", "Enemy map" },
  { "flags", "Flag carriers" },
  { "timers", "Timers" },
  { "inc", "INC calls" },
  { "sync", "Team sync" },
  { nil, "Spy / Enemies" },
  { "list", "Enemy list" },
  { "hud", "Radar HUD" },
  { "stealth", "Stealth" },
  { "focus", "Focus and keep target" },
  { nil, "World PvP" },
  { "world", "Detection" },
  { "kos", "Kill On Sight" },
  { "data", "Statistics" },
  { nil, "Cooldowns" },
  { "cdbars", "Bars and icons" },
  { "cdtrack", "Tracking and profile" },
  { "dr", "Diminishing returns" },
  { "alerts", "Alerts" },
  { "filter", "Spell filter" },
  { nil, "Setup" },
  { "general", "General" },
  { "interact", "Interact key" },
  { "tidy", "Clean screen, AV mode" },
}

-- Pages that were merged into others (O:Open of an old key still works).
O.ALIAS = { detect = "world", retarget = "focus", plates = "cdbars", profile = "cdtrack" }

-- One topic: a flat row; the picked one gets a blue wash and a blue edge.
local function NavButton(nav, label, indent)
  local K = W.C
  local b = CreateFrame("Button", nil, nav)
  b:SetWidth(NAV_W - 12 - indent)
  b:SetHeight(NAV_ROW)
  b.sel = W.Fill(b, K.accent, 0.16, "BACKGROUND")
  b.sel:SetAllPoints(b)
  b.sel:Hide()
  b.bar = W.Fill(b, K.accent, 1, "BORDER")
  b.bar:SetWidth(2)
  b.bar:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
  b.bar:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
  b.bar:Hide()
  local hl = W.Fill(b, { 1, 1, 1 }, 0.05, "HIGHLIGHT")
  hl:SetAllPoints(b)
  b.text = W.Font(b:CreateFontString(nil, "OVERLAY"), 12, K.dim[1], K.dim[2], K.dim[3])
  b.text:SetPoint("LEFT", b, "LEFT", 10, 0)
  b.text:SetPoint("RIGHT", b, "RIGHT", -4, 0)
  b.text:SetJustifyH("LEFT")
  b.text:SetText(label)
  b.indent = indent
  return b
end

local function NavMark(b, on)
  local K = W.C
  if on then
    b.sel:Show()
    b.bar:Show()
    b.text:SetTextColor(1, 1, 1)
  else
    b.sel:Hide()
    b.bar:Hide()
    b.text:SetTextColor(K.dim[1], K.dim[2], K.dim[3])
  end
end

-- A section header that folds its topics open or shut (one open at a time).
local function NavHeader(nav, label)
  local K = W.C
  local h = CreateFrame("Button", nil, nav)
  h:SetWidth(NAV_W - 12)
  h:SetHeight(22)
  h.icon = W.Arrow(h, 9, "right")
  h.icon:SetPoint("LEFT", h, "LEFT", 4, 0)
  local hl = W.Fill(h, { 1, 1, 1 }, 0.04, "HIGHLIGHT")
  hl:SetAllPoints(h)
  h.text = W.Font(h:CreateFontString(nil, "OVERLAY"), 11, K.text[1], K.text[2], K.text[3])
  h.text:SetPoint("LEFT", h.icon, "RIGHT", 7, 0)
  h.text:SetText(string.upper(label))
  return h
end

function O:Build()
  local K = W.C
  local f = CreateFrame("Frame", "OctoBGOptions", UIParent)
  f:SetWidth(WIDTH)
  f:SetHeight(HEIGHT)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
  f:SetFrameStrata("DIALOG")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:SetClampedToScreen(true)
  W.Flat(f, K.bg, 1, K.lineHi)
  f:Hide()
  table.insert(UISpecialFrames, "OctoBGOptions")   -- Escape closes it
  f:SetScript("OnHide", function() W.CloseMenus() end)
  self.frame = f

  -- title row: drag it to move the window
  local bar = CreateFrame("Frame", nil, f)
  bar:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
  bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -36, 0)
  bar:SetHeight(34)
  bar:EnableMouse(true)
  bar:SetScript("OnMouseDown", function() f:StartMoving() end)
  bar:SetScript("OnMouseUp", function() f:StopMovingOrSizing() end)
  local title = W.Font(f:CreateFontString(nil, "OVERLAY"), 15, K.text[1], K.text[2], K.text[3])
  title:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -10)
  title:SetText("|cff33ccffOcto|rBG")
  local sub = W.Font(f:CreateFontString(nil, "OVERLAY"), 11, K.dim[1], K.dim[2], K.dim[3])
  sub:SetPoint("LEFT", title, "RIGHT", 10, -1)
  sub:SetText("v" .. B.VERSION .. "  -  battlegrounds, world PvP, enemies, their cooldowns and combat text")
  local close = W.Button(f, "X", 22, 22)
  close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -6)
  close:SetScript("OnClick", function() f:Hide() end)
  W.Tip(close, "Close", "Escape closes it too.")

  self:BuildQuickBar(f)

  local nav = CreateFrame("Frame", nil, f)
  nav:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -74)
  nav:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 12)
  nav:SetWidth(NAV_W)
  W.Flat(nav, K.panel, 1, K.line)
  self.navFrame = nav
  local content = CreateFrame("Frame", nil, f)
  content:SetPoint("TOPLEFT", f, "TOPLEFT", NAV_W + 18, -74)
  content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 12)
  W.Flat(content, K.panel, 1, K.line)
  self.content = content
  self:ApplyAlpha()

  -- topics: the ones before the first header stand alone, the rest fold
  self.groups, self.top, self.groupOf = {}, {}, {}
  local g
  for i = 1, table.getn(O.SECTIONS) do
    local s = O.SECTIONS[i]
    if not s[1] then
      g = { header = NavHeader(nav, s[2]), buttons = {} }
      g.header.group = g
      g.header:SetScript("OnClick", function()
        O.openGroup = (O.openGroup ~= this.group) and this.group or nil
        O:LayoutNav()
      end)
      table.insert(self.groups, g)
    else
      local b = NavButton(nav, s[2], g and 10 or 0)
      b.key = s[1]
      b:SetScript("OnClick", function() O:Select(this.key) end)
      self.nav[s[1]] = b
      if g then
        table.insert(g.buttons, b)
        self.groupOf[s[1]] = g
      else
        table.insert(self.top, b)
      end
    end
  end
end

-- A tooltip for a top bar control.
local function QuickTip(frame, title, text)
  frame:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_BOTTOMRIGHT")
    GameTooltip:AddLine(title)
    GameTooltip:AddLine(text, 1, 1, 1, 1)
    GameTooltip:Show()
  end)
  frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- The strip under the title, on every page: placing panels, testing, the
-- window's background and finding a setting.
function O:BuildQuickBar(f)
  local K = W.C
  local bar = CreateFrame("Frame", nil, f)
  bar:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -36)
  bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -36)
  bar:SetHeight(32)
  W.Flat(bar, K.panel, 1, K.line)
  self.quick = bar
  -- move frames
  local cb = W.CheckBox(bar, 16)
  cb:SetPoint("LEFT", bar, "LEFT", 10, 0)
  cb:SetScript("OnClick", function() U.SetLocked(not this:GetChecked()) end)
  QuickTip(cb, "Move frames", "Every panel shows sample data and a blue box: drag it, hover it for size, opacity and on / off. Untick when done.")
  local cl = W.Font(bar:CreateFontString(nil, "OVERLAY"), 12, K.text[1], K.text[2], K.text[3])
  cl:SetPoint("LEFT", cb, "RIGHT", 8, 0)
  cl:SetText("Move frames")
  self.quickMove = cb
  -- (combat text's test lives on the combat text pages, user 17 Oct 2026)
  local reset = W.Button(bar, "Reset positions", 108, 22, "OctoBGQuickReset")
  reset:SetPoint("LEFT", cl, "RIGHT", 14, 0)
  reset:SetScript("OnClick", function() U.ResetPositions() end)
  QuickTip(reset, "Reset positions", "Moves every panel back to where it started.")
  -- background opacity of this window
  local bl = W.Font(bar:CreateFontString(nil, "OVERLAY"), 12, K.text[1], K.text[2], K.text[3])
  bl:SetPoint("LEFT", reset, "RIGHT", 16, 0)
  bl:SetText("Background")
  local s = W.SliderBar(bar, 90, "OctoBGQuickAlpha")
  s:SetPoint("LEFT", bl, "RIGHT", 10, 0)
  s:SetMinMaxValues(0.3, 1)
  s:SetValueStep(0.05)
  local sv = W.Font(bar:CreateFontString(nil, "OVERLAY"), 11, K.accent[1], K.accent[2], K.accent[3])
  sv:SetPoint("LEFT", s, "RIGHT", 8, 0)
  s:SetScript("OnValueChanged", function()
    if this.loading then return end
    B.db.optAlpha = math.floor(this:GetValue() * 20 + 0.5) / 20
    sv:SetText(math.floor(B.db.optAlpha * 100 + 0.5) .. "%")
    W.SliderPaint(this)
    O:ApplyAlpha()
  end)
  QuickTip(s, "Background", "How solid this window's background is: lower to see the game through it.")
  self.quickAlpha, self.quickAlphaText = s, sv
  -- find a setting
  local find = W.EditBox(bar, 170, "OctoBGQuickFind")
  find:SetPoint("RIGHT", bar, "RIGHT", -8, 0)
  local hint = W.Font(find:CreateFontString(nil, "OVERLAY"), 11, K.dim[1], K.dim[2], K.dim[3])
  hint:SetPoint("LEFT", find, "LEFT", 7, 0)
  hint:SetText("Find a setting")
  local function Hint() if find.typing or (find:GetText() or "") ~= "" then hint:Hide() else hint:Show() end end
  find.OnFocus = Hint
  find:SetScript("OnEscapePressed", function()
    this:SetText("")
    this:ClearFocus()
  end)
  find:SetScript("OnEnterPressed", function()
    this:ClearFocus()
    local r = O.results
    if r and r[1] then O:Reveal(r[1]) end
  end)
  find:SetScript("OnTextChanged", function()
    Hint()
    O:Search(this:GetText())
  end)
  QuickTip(find, "Find a setting", "Type a word (\"zoom\", \"sound\", \"crit\"): every setting that mentions it is "
    .. "listed. Click one to go straight to it. Enter goes to the first.")
  self.quickFind = find
end

function O:RefreshQuick()
  if not self.quick then return end
  self.quickMove:SetChecked((not B.db.locked) and 1 or nil)
  self.quickAlpha.loading = true
  self.quickAlpha:SetValue(B.db.optAlpha or 0.95)
  self.quickAlpha.loading = nil
  W.SliderPaint(self.quickAlpha)
  self.quickAlphaText:SetText(math.floor((B.db.optAlpha or 0.95) * 100 + 0.5) .. "%")
end

-- The window's and its panels' backgrounds follow the Background slider.
function O:ApplyAlpha()
  if not self.frame then return end
  local K = W.C
  local a = B.db.optAlpha or 0.95
  self.frame:SetBackdropColor(K.bg[1], K.bg[2], K.bg[3], a)
  local panels = { self.quick, self.navFrame, self.content }
  for i = 1, 3 do
    if panels[i] then panels[i]:SetBackdropColor(K.panel[1], K.panel[2], K.panel[3], a) end
  end
end

B:On("OBG_LAYOUT", function() O:RefreshQuick() end)

-- Stacks the topic list: lone topics, then each header with its topics when open.
function O:LayoutNav()
  local nav = self.navFrame
  local y = -6
  local function Put(b, indent, h)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", nav, "TOPLEFT", 6 + indent, y)
    b:Show()
    y = y - h
  end
  for i = 1, table.getn(self.top) do Put(self.top[i], 0, NAV_ROW + 2) end
  for i = 1, table.getn(self.groups) do
    local grp = self.groups[i]
    y = y - 4
    Put(grp.header, 0, 23)
    local open = (self.openGroup == grp)
    W.Turn(grp.header.icon, open and "down" or "right")
    for j = 1, table.getn(grp.buttons) do
      local b = grp.buttons[j]
      if open then Put(b, b.indent, NAV_ROW + 1) else b:Hide() end
    end
  end
end

function O:Page(key)
  local p = self.pages[key]
  if p then return p end
  if key == "filter" then
    p = FilterPage(self.content)
    p.key, p.title = key, "Spell filter"
  else
    p = W.Page(self.content)
    p.key = key
    BUILD[key](p)
    W.Done(p)
  end
  self.pages[key] = p
  return p
end

-- Shows one page (or the search results), hides the rest.
function O:Show(p)
  W.CloseMenus()
  for _, q in pairs(self.pages) do
    if q ~= p then q.frame:Hide() end
  end
  if self.searchPage and self.searchPage ~= p then self.searchPage.frame:Hide() end
  p.frame:Show()
  W.Refresh(p)
end

function O:Select(key)
  key = O.ALIAS[key] or key
  if not BUILD[key] and key ~= "filter" then key = "start" end
  self.current = key
  self.searching = nil
  for k, b in pairs(self.nav) do NavMark(b, k == key) end
  -- the topic's section folds open
  if self.groupOf[key] then self.openGroup = self.groupOf[key] end
  self:LayoutNav()
  self:Show(self:Page(key))
end

-- ---------------------------------------------------------------- find a setting

local RESULT_ROWS = 22

-- Every page, built (hidden) once, so the search knows every setting.
function O:BuildAll()
  if self.allBuilt then return end
  for i = 1, table.getn(O.SECTIONS) do
    local key = O.SECTIONS[i][1]
    if key then
      local p = self:Page(key)
      if key ~= self.current then p.frame:Hide() end
    end
  end
  self.allBuilt = true
end

function O:SearchPage()
  if self.searchPage then return self.searchPage end
  local p = W.Page(self.content)
  W.Heading(p, "Find a setting")
  p.count = W.Live(p, function() return O.searchText or "" end)
  p.rows = {}
  for i = 1, RESULT_ROWS do
    local row = W.Row(p, 22, 0, 2)
    local b = CreateFrame("Button", nil, row)
    b:SetAllPoints(row)
    W.Flat(b, W.C.card, 1, W.C.line)
    local hl = W.Fill(b, W.C.accent, 0.2, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
    hl:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
    b.text = W.Font(b:CreateFontString(nil, "OVERLAY"), 12, 1, 1, 1)
    b.text:SetPoint("LEFT", b, "LEFT", 10, 0)
    b.text:SetPoint("RIGHT", b, "RIGHT", -8, 0)
    b.text:SetJustifyH("LEFT")
    b:SetScript("OnClick", function() if this.entry then O:Reveal(this.entry) end end)
    row.b = b
    p.rows[i] = row
  end
  W.Done(p)
  self.searchPage = p
  return p
end

function O:Search(text)
  if not self.frame then return end
  text = string.gsub(text or "", "^%s*(.-)%s*$", "%1")
  if string.len(text) < 2 then
    self.results = nil
    if self.searching then
      self.searching = nil
      self:Select(self.current or "start")
    end
    return
  end
  self:BuildAll()
  local res = W.Find(text)
  self.results = res
  local p = self:SearchPage()
  local n = table.getn(res)
  if n == 0 then
    O.searchText = "Nothing matches \"" .. text .. "\"."
  else
    O.searchText = n .. " setting" .. ((n == 1) and "" or "s") .. " mention \"" .. text .. "\" - click one to go to it."
      .. ((n > RESULT_ROWS) and ("  |cff999999(first " .. RESULT_ROWS .. " shown - type more)|r") or "")
  end
  for i = 1, RESULT_ROWS do
    local row, e = p.rows[i], res[i]
    if e then
      row.b.entry = e
      local where = e.page.title or e.page.key
      if e.card then where = where .. " > " .. e.card.title end
      row.b.text:SetText(e.label .. "   |cff999999" .. where .. "|r")
      row:Show()
    else
      row.b.entry = nil
      row:Hide()
    end
  end
  for _, b in pairs(self.nav) do NavMark(b, false) end
  self.searching = true
  self:Show(p)
end

-- Opens a search result's page and card, scrolls to it and makes it glow.
function O:Reveal(e)
  local p = e.page
  self.searching = nil
  self:Select(p.key)
  if e.card and not W.IsOpen(e.card) then W.SetOpen(e.card, true) end
  p.after = function()
    local top, at = p.body:GetTop(), e.region:GetTop()
    if top and at then
      local off = math.max(0, top - at - 40)
      local sb = getglobal(p.frame:GetName() .. "ScrollBar")
      if sb then sb:SetValue(off) else p.frame:SetVerticalScroll(off) end
    end
    W.Flash(e.region)
  end
  W.Measure(p)
end

-- Every card back to how it started (General: Problems).
function O:ResetCards()
  B.db.optCards = {}
  for _, p in pairs(self.pages) do
    if p.cards then
      for i = 1, table.getn(p.cards) do W.ApplyCard(p.cards[i]) end
    end
  end
  if self.current and self.pages[self.current] then W.Measure(self.pages[self.current]) end
end

-- Re-read the open page (after a setting changed somewhere).
function O:Refresh()
  if not self.frame or not self.frame:IsShown() then return end
  self:RefreshQuick()
  local p = self.searching and self.searchPage or (self.current and self.pages[self.current])
  if p then W.Refresh(p) end
end

function O:Open(key)
  if not self.frame then self:Build() end
  self.frame:Show()
  self:RefreshQuick()
  if key then self.searching = nil end
  if self.searching and not key then
    self:Show(self.searchPage)
  else
    self:Select(key or self.current or "start")
  end
end

function O:Toggle()
  if self.frame and self.frame:IsShown() then
    self.frame:Hide()
  else
    self:Open()
  end
end

-- ---------------------------------------------------------------- view distance

-- What /obg maxview raises (only ever up). None of these change what the
-- server sends: enemies further than its visibility range do not exist for
-- the client. They make what it does send visible on screen.
--   unitDrawDist         players/NPC models drawn this far (client, default 300)
--   horizonfarclip       horizon distance (client, default 2112)
--   farclip              terrain distance; the slider stops at 777
--   NP_NameplateDistance nameplate range, nampower (NampowerSettings allows 200)
--   NameplateRange       nameplate range, SuperWoW (SuperAPI allows 80)
-- Nameplates are also one of the ways OctoBG finds enemies who do nothing.
local VIEW = {
  { "farclip", 777 },
  { "horizonfarclip", 6226 },
  { "unitDrawDist", 1000 },
  { "NP_NameplateDistance", 200 },
  { "NameplateRange", 80 },
}

local function CVar(name)
  local ok, v = pcall(GetCVar, name)
  if ok then return v end
  return nil
end

function O:MaxView(off)
  if off then
    local bk = B.db.viewBackup
    if not bk then
      B:Print("nothing to restore - /obg maxview has not changed anything")
      return
    end
    for name, v in pairs(bk) do pcall(SetCVar, name, v) end
    B.db.viewBackup = nil
    B:Print("view settings put back as they were")
    return
  end
  local bk = B.db.viewBackup or {}
  for i = 1, table.getn(VIEW) do
    local name, want = VIEW[i][1], VIEW[i][2]
    local cur = CVar(name)
    if cur == nil then
      B:Print(name .. ": not on this client")
    elseif tonumber(cur) and tonumber(cur) >= want then
      B:Print(name .. " " .. cur .. " - already at least " .. want)
    else
      if bk[name] == nil then bk[name] = cur end
      pcall(SetCVar, name, tostring(want))
      B:Print(name .. " " .. cur .. " -> " .. tostring(CVar(name)))
    end
  end
  B.db.viewBackup = bk
  B:Print("saved to Config.wtf when you log out; /obg maxview off puts them back")
end

function O:PrintReach()
  local Tr = B.Tracker
  local max, drop, n = Tr:ReachSummary()
  if Tr.reachZone and max > 0 then
    B:Print("here (" .. Tr.reachZone .. "): enemies picked up as far as " .. math.floor(max) .. " yd"
      .. (drop and (", they drop out at about " .. math.floor(drop) .. " yd (" .. n .. " seen leaving)") or ""))
  end
  for zone, r in pairs(B.db.reach) do
    B:Print(zone .. ": up to " .. math.floor(r.max) .. " yd"
      .. (r.drop and (", drop out at ~" .. math.floor(r.drop) .. " yd") or "") .. " (" .. (r.day or "?") .. ")")
  end
end

-- ---------------------------------------------------------------- slash commands

B:Command("config", "open the options", function() O:Toggle() end)
B:Command("unlock", "arrange the panels: sample data and drag handles on every panel", function()
  U.SetLocked(false)
  B:Print("arranging - drag the blue panels, /obg lock when done")
end)
B:Command("lock", "stop arranging the panels", function()
  U.SetLocked(true)
  B:Print("panels locked")
end)
B:Command("hud", "toggle the HUD", function() OctoBG_ToggleHUD() end)
B:Command("map", "show / hide the enemy map", function() OctoBG_ToggleMap() end)
B:Command("list", "show / hide the enemy list (Spy's Nearby window)", function() B.Roster:Toggle() end)
B:Command("world", "world PvP detection on / off (on | off)", function(rest)
  rest = string.lower(rest or "")
  local on = not B.db.spy.Enabled
  if rest == "on" then on = true elseif rest == "off" then on = false end
  B.Nearby:SetEnabled(on)
end)
B:Command("stats", "enemy statistics window", function() B.Stats:Toggle() end)
B:Command("kos", "<name> add / remove Kill On Sight (no name: your target)", function(rest)
  local name = (rest and rest ~= "") and rest or (UnitIsPlayer("target") and UnitName("target"))
  if name then B.People:ToggleKOS(name) else B:Print("/obg kos <name>, or target the player") end
end)
B:Command("ignore", "<name> add / remove from the ignore list (no name: your target)", function(rest)
  local name = (rest and rest ~= "") and rest or (UnitIsPlayer("target") and UnitName("target"))
  if name then B.People:ToggleIgnore(name) else B:Print("/obg ignore <name>, or target the player") end
end)
B:Command("clear", "empty the Nearby list", function() B.Nearby:Clear() end)
B:Command("nearby", "post the nearby enemy count to your group", function() B.Roster:PostCount() end)
B:Command("spytest", "show a sample stealth alert", function() B.Nearby:Test() end)
B:Command("reset", "move every panel back to its default place", function() U.ResetPositions() end)
B:Command("maxview", "raise draw distance, horizon and nameplate range (/obg maxview off: put back)", function(rest)
  O:MaxView(string.lower(rest or "") == "off")
end)
B:Command("reach", "how far away enemies were picked up, per zone", function() O:PrintReach() end)
B:Command("dim", "<0-90> darken the tactical map so the markers stand out", function(rest)
  local v = tonumber(rest)
  if not v then
    B:Print("map darkness " .. math.floor(B.db.map.dim * 100 + 0.5) .. "% - /obg dim 0..90")
    return
  end
  B.db.map.dim = math.max(0, math.min(90, v)) / 100
  B.TacMap:Layout()
  O:Refresh()
end)
B:Command("calib", "forget the learned facing/axes and learn them again", function()
  B.Map:ResetCalibration()
  B:Print("calibration reset - run forward in a straight line for a few seconds")
end)
B:Command("status", "show detected DLLs and tracker state", function()
  B:Print(O:StatusLine())
  B:Print("zone " .. tostring(B.zone) .. " (" .. tostring(B.zoneName) .. "), active " .. tostring(B.active)
    .. ", enemies tracked " .. B.Tracker.count)
end)
B:Command("probe", "print what the client returns for positions and the map (for bug reports)", function()
  local Mp = B.Map
  local px, py, pz = U.Position("player")
  B:Print("UnitPosition player: " .. tostring(px) .. ", " .. tostring(py) .. ", " .. tostring(pz)
    .. "  raw facing: " .. tostring(Mp:RawFacing()) .. "  sign " .. tostring(B.db.facingSign)
    .. "  swapXY " .. tostring(B.db.swapXY))
  local mx, my = Mp:UnitMap("player")
  B:Print("map file: " .. tostring(GetMapInfo()) .. "  map pos: " .. tostring(mx) .. ", " .. tostring(my))
  if mx then
    local wx, wy = Mp:ToWorld(mx, my)
    B:Print("map -> world: " .. tostring(wx) .. ", " .. tostring(wy))
  end
  if UnitExists("target") then
    local g = U.GuidOf("target")
    local tx, ty, tz = U.Position("target")
    B:Print("target " .. tostring(UnitName("target")) .. " guid " .. tostring(g)
      .. " pos " .. tostring(tx) .. ", " .. tostring(ty) .. ", " .. tostring(tz)
      .. " dist " .. tostring(U.Distance("target")) .. " sight " .. tostring(U.InSight("target")))
  end
  if GetNumBattlefieldFlagPositions then
    for i = 1, GetNumBattlefieldFlagPositions() do
      local fx, fy, tok = GetBattlefieldFlagPosition(i)
      B:Print("flag " .. i .. ": " .. tostring(fx) .. ", " .. tostring(fy) .. " " .. tostring(tok))
    end
  end
end)
B:Command("debug", "toggle debug output", function()
  B.debug = not B.debug
  B:Print("debug " .. (B.debug and "on" or "off"))
end)
B:Command("errors", "list errors caught this session", function()
  local n = 0
  for err in pairs(B.errors) do
    n = n + 1
    B:Print(err)
  end
  if n == 0 then B:Print("no errors") end
  B:ClearErrors()
end)

-- Spy's slash command keeps working once the old addon is switched off:
-- /spy show | hide | reset | clear | config | kos <name> | ignore <name> | stats | test
local function SpyCommand(msg)
  local _, _, cmd, rest = string.find(msg or "", "^%s*(%S*)%s*(.-)%s*$")
  cmd = string.lower(cmd or "")
  if cmd == "show" then
    B.Nearby:SetEnabled(true)
    B.Roster:Open()
  elseif cmd == "hide" then
    B.Nearby:SetEnabled(false)
  elseif cmd == "reset" then
    B.db.pos.list = nil
    if B.Roster.frame then U.RestorePos(B.Roster.frame) end
  elseif cmd == "clear" then
    B.Nearby:Clear()
  elseif cmd == "kos" or cmd == "ignore" or cmd == "stats" then
    B.commands[cmd].fn(rest)
  elseif cmd == "test" then
    B.Nearby:Test()
  else
    O:Open("world")
  end
end

B:On("OBG_INIT", function()
  B:Print("v" .. B.VERSION .. " loaded - /obg for options (start with \"Overview\"), /obg unlock to arrange the panels")
  if not B.People:SpyLoaded() then
    SLASH_OCTOBGSPY1 = "/spy"
    SLASH_OCTOBGSPY2 = "/spygui"
    SlashCmdList["OCTOBGSPY"] = SpyCommand
  end
end)
