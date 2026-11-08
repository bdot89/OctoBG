-- Offline run of OctoBG through the mock client: every file loads, the
-- player logs in with the old Spy addon's data present, enemies appear in
-- the open world and a battleground, every options page, menu and window is
-- built and driven. Any error OctoBG's event bus catches fails the run.
--   powershell -File tests\run.ps1

local DIR = "."
dofile(DIR .. "/tests/mock.lua")

local fails, checks = 0, 0
local function ok(cond, what)
  checks = checks + 1
  if not cond then
    fails = fails + 1
    print("FAIL: " .. what)
  end
end

-- the old Spy addon's saved data, as this install has it
Mock.loaded = { Spy = true }
SpyDB = {
  profileKeys = { ["Tester - Y'Shaarj"] = "Tester - Y'Shaarj" },
  profiles = { ["Tester - Y'Shaarj"] = { MinimapDetection = true, PurgeData = "SixtyDays", InvertSpy = true,
    ResizeSpyLimit = 12, MainWindow = { RowHeight = 14, Position = { w = 260 } }, Font = "Express Way",
    WarnOnStealth = false, Announce = "Party" } },
  kosData = { ["Y'Shaarj"] = { Horde = { Tester = { Gankster = { class = "ROGUE", level = 60, time = 1690000000,
    added = 1690000100, reason = { ["Camped me"] = true }, wins = 2 } } } } },
  removeKOSData = { ["Y'Shaarj"] = { Horde = {} } },
  FriendsData = { Buddy = true },
}
SpyPerCharDB = {
  PlayerData = {
    Kosplayer = { guild = "Kos Guild", guid = "0x0000000000003BA7", class = "PALADIN", isEnemy = true, name = "Kosplayer",
              race = "High Elf", zone = "Duskwood", subZone = "Twilight Grove", mapX = 0.46, mapY = 0.36, level = 60,
              time = 1699999000, isGuess = false, wins = 3, loses = 1 },
    Oldguy = { class = "MAGE", isEnemy = true, name = "Oldguy", level = 40, time = 1000 },
  },
  KOSData = { Kosplayer = 1699990000 },
  IgnoreData = { Annoying = true },
}

local files = Mock.Load(DIR, "OctoBG.toc")
ok(table.getn(files) == 34, "34 files in the toc (got " .. table.getn(files) .. ")")
local B = OctoBG

Mock.Fire("ADDON_LOADED", "OctoBG")
Mock.Fire("PLAYER_LOGIN")
Mock.Fire("PLAYER_ENTERING_WORLD")
Mock.Tick(1)

local P, NB, R = B.People, B.Nearby, B.Roster
-- import
ok(B.db.spyImported, "Spy settings imported")
ok(B.db.spy.MinimapDetection == true, "MinimapDetection copied")
ok(B.db.spy.MuteSoundInBattlegrounds == false, "missing profile key takes Spy's default")
ok(B.db.list.growUp == true and B.db.list.rows == 12, "InvertSpy / ResizeSpyLimit copied")
ok(B.db.list.font == "Interface\\AddOns\\OctoBG\\media\\fonts\\Expressway.ttf", "font copied")
ok(B.db.stealth.alert == false, "WarnOnStealth copied")
ok(P:IsKOS("Kosplayer"), "per-character KoS imported")
ok(P:IsKOS("Gankster"), "central KoS imported")
ok(P:IsIgnored("Annoying"), "ignore imported")
ok(P:IsFriend("Buddy"), "friends imported")
ok(P:Get("Kosplayer").wins == 3, "wins imported")
ok(P:Get("Gankster").reason and P:Get("Gankster").reason["Camped me"], "KoS reason imported")
ok(P:Get("Oldguy") == nil, "purge removed a 60+ day old record")
ok(Mock.popup == "OCTOBG_OLD_SPY", "offers to switch Spy off")
ok(NB.standDown, "stands down while Spy runs")
ok(not NB:LayerOn(), "no world layer while Spy runs")
B.Options:Open("start")

-- Spy switched off (as after the popup + reload)
Mock.loaded = {}
NB.standDown = false
B.db.stealth.alert = true
B.db.spy.Announce = "None"
NB:ZoneCheck()
ok(NB.enabledInZone, "Duskwood (contested) enables detection")
ok(B.active, "world detection makes OctoBG active")
ok(B.Tracker and B.db.spy.Enabled, "detection on")
ok(Mock.cvars.NP_EnableSpellGoEvents == "1" and Mock.cvars.NP_EnableAuraCastEvents == "1", "nampower events switched on")

-- an enemy shows up
Mock.sounds = {}
Mock.Enemy("0x00000000000000A1", "Rogueone", "ROGUE", 30, 10)
Mock.Fire("UNIT_HEALTH_GUID", "0x00000000000000A1", 1)
ok(B.Tracker.units["0x00000000000000A1"], "tracker picked the enemy up")
ok(NB.nearby.Rogueone and NB.active.Rogueone, "Nearby lists the enemy as active")
ok(Mock.sounds[1] and string.find(Mock.sounds[1], "detected%-nearby"), "nearby sound played")
ok(P:Get("Rogueone") and P:Get("Rogueone").zone == "Duskwood", "record made with the place")
Mock.Tick(1.5)
ok(R.frame:IsShown(), "enemy list shown in the open world")
ok(R.rows[1]:IsShown() and R.rows[1].entry.name == "Rogueone", "first row is the enemy")

-- a Kill On Sight enemy
Mock.sounds = {}
Mock.Enemy("0x0000000000003BA7", "Kosplayer", "PALADIN", -20, 40, { guild = "Kos Guild", race = "High Elf" })
Mock.Fire("SPELL_GO_OTHER", 0, 635, "0x0000000000003BA7", nil, 0, 1, 0)
ok(NB.nearby.Kosplayer, "KoS enemy listed")
ok(NB.box and NB.box:IsShown() and NB.boxKind == "kos", "KoS alert box")
ok(Mock.sounds[1] and string.find(Mock.sounds[1], "detected%-kos"), "KoS sound")
Mock.Tick(0.6)
ok(R.list[1].name == "Kosplayer", "Kill On Sight first in the list")

-- stealth
Mock.Tick(6)
Mock.sounds = {}
Mock.Enemy("0x00000000000000A2", "Sneaky", "ROGUE", 10, 5)
Mock.Fire("SPELL_GO_OTHER", 0, 1784, "0x00000000000000A2", nil, 0, 1, 0)
ok(NB.boxKind == "stealth", "stealth alert box")
ok(B.Tracker.stealth["0x00000000000000A2"], "stealth mark made")
Mock.Fire("BUFF_REMOVED_OTHER", "0x00000000000000A2", 0, 1784)

-- heading: the enemy runs north
for i = 1, 10 do
  Mock.units["0x00000000000000A1"].x = 30 + i * 2
  Mock.Tick(0.2)
end
local u1 = B.Tracker.units["0x00000000000000A1"]
ok(B.Tracker.Moving(u1, GetTime()) and math.abs(u1.head) < 0.2, "running north gives heading ~0")

-- menus
R:Menu("Rogueone", u1)
ok(Mock.menuItems and table.getn(Mock.menuItems) >= 6, "enemy menu built")
ToggleDropDownMenu(2, { key = "announce" })
ok(table.getn(Mock.menuItems) == 5, "announce submenu")
ToggleDropDownMenu(2, { key = "reasons" })
ok(table.getn(Mock.menuItems) >= 14, "reasons submenu")
ToggleDropDownMenu(3, { key = "reason", index = 4 })
ok(table.getn(Mock.menuItems) >= 5, "reason category")
P:SetReason("Kosplayer", "Camped me")
ok(P:ReasonText("Kosplayer") == "Camped me", "reason set")
P:SetReason("Kosplayer", B.SpyData.OTHER, "rude")
ok(string.find(P:ReasonText("Kosplayer"), "rude"), "own reason")
-- row clicks
this = R.rows[2]
Mock.shift = true
arg1 = "LeftButton"
R.rows[2].scripts.OnClick()
Mock.shift = nil
ok(P:IsKOS(R.rows[2].entry.name) or P:IsKOS("Rogueone"), "shift-click toggles Kill On Sight")
Mock.Run(R.rows[1], "OnEnter")
ok(GameTooltip.lines and table.getn(GameTooltip.lines) >= 3, "row tooltip")

-- list modes and look
for m = 1, 4 do
  R:SetMode(m)
  Mock.Tick(0.2)
end
R:SetMode(1)
B.db.list.growUp = false
R:Restyle()
Mock.Tick(0.3)

-- options: every page
local O = B.Options
O:Open("start")
for i = 1, table.getn(O.SECTIONS) do
  local key = O.SECTIONS[i][1]
  if key then
    O:Select(key)
    ok(O.pages[key], "options page " .. key)
  end
end
O:Refresh()
-- the quick bar: move frames, background, combat text test
O.quickMove:SetChecked(1)
Mock.Run(O.quickMove, "OnClick")
ok(not B.db.locked and B.test, "Move frames ticked: panels unlocked")
O.quickAlpha:SetValue(0.5)
Mock.Run(O.quickAlpha, "OnValueChanged")
ok(B.db.optAlpha == 0.5, "background slider sets the window opacity (" .. tostring(B.db.optAlpha) .. ")")
O:RefreshQuick()
ok(O.quickMove:GetChecked(), "quick bar shows move mode")
O.quickMove:SetChecked(nil)
Mock.Run(O.quickMove, "OnClick")
ok(B.db.locked, "Move frames unticked: locked again")
ok(O.quickTest == nil, "no test button in the top bar")
-- focus keys: the enemy under the mouse, swapping target and focus
local oldTarget = Mock.target
Mock.mouseover = "0x00000000000000A1"
OctoBG_FocusMouseover()
ok(B.Focus.guid == "0x00000000000000A1" and Mock.target == oldTarget, "focus under the mouse, target unchanged")
Mock.mouseover = nil
OctoBG_FocusMouseover()
ok(B.Focus.guid == "0x00000000000000A1", "nothing under the mouse keeps the focus")
Mock.target = "0x0000000000003BA7"
OctoBG_FocusSwap()
ok(Mock.target == "0x00000000000000A1" and B.Focus.guid == "0x0000000000003BA7", "swap target and focus")
B.Focus:Clear()
Mock.target = oldTarget
-- old page names open the page they were merged into
O:Open("detect")
ok(O.current == "world", "detect opens Detection")
-- folding cards: shut, open, remembered, reset
local mp = O:Page("map")
ok(table.getn(mp.cards) == 5, "enemy map page has five cards")
O:Select("map")
Mock.Tick(0.1)
local c1 = mp.cards[1]
ok(c1.h and c1.card:GetHeight() > 24, "open card measured to its content")
B.W.SetOpen(c1, false)
ok(not c1.parent:IsShown() and c1.card:GetHeight() == 24, "folded card shows only its bar")
ok(B.db.optCards[c1.key] == false, "fold remembered")
B.W.SetOpen(c1, true)
ok(c1.parent:IsShown(), "card opens again")
local lk = O:Page("list")
local look
for i = 1, table.getn(lk.cards) do if lk.cards[i].title == "Look" then look = lk.cards[i] end end
ok(look and not B.W.IsOpen(look), "Look starts folded")
-- two columns, help in tooltips
local arrows
for i = 1, table.getn(B.W.index) do
  local e = B.W.index[i]
  if e.page == mp and e.label == "Arrows for runners" then arrows = e end
end
ok(arrows and arrows.region.point[2] and arrows.region.point[4] == 260, "second tick box sits in the right-hand column")
Mock.Run(arrows.region.children[1], "OnEnter")
ok(GameTooltip.lines[1] == "Arrows for runners" and string.find(GameTooltip.lines[2] or "", "plain triangles"), "help is in the tooltip")
-- find a setting
O.quickFind:SetText("zoom")
ok(O.results and table.getn(O.results) >= 2 and O.searchPage.frame:IsShown(), "search lists the zoom settings")
ok(O.searchPage.rows[1]:IsShown() and string.find(O.searchPage.rows[1].b.text.text or "", "Enemy map"), "result names its page")
local hit = O.results[1]
B.W.SetOpen(hit.card or mp.cards[1], false)
Mock.Run(O.searchPage.rows[1].b, "OnClick")
ok(O.current == hit.page.key and not O.searchPage.frame:IsShown(), "clicking a result opens its page")
ok(not hit.card or B.W.IsOpen(hit.card), "and opens its card")
Mock.Tick(0.1)
ok(B.W.flash and B.W.flash:IsShown(), "and makes it glow")
O.quickFind:SetText("qqzzxx")
ok(O.results and table.getn(O.results) == 0, "no match")
O.quickFind:SetText("")
ok(not O.searching and O.pages[O.current].frame:IsShown(), "emptying the box goes back to the page")
O:ResetCards()
ok(next(B.db.optCards) == nil and B.W.IsOpen(c1), "Reset folded cards")
-- threat and combat text pages moved to pfUI Octo
O:Select("general")
O:Refresh()
ok(not O.pages.threat and not O.pages.ctareas, "no threat or combat text pages")

O.frame:Hide()

-- statistics
B.Stats:Show()
ok(B.Stats.frame:IsShown(), "statistics window")
Mock.Run(B.Stats.heads[6], "OnClick")
ok(B.Stats.sortBy == "wins", "sort by wins")
B.Stats.box:SetText("kosp")
ok(B.Stats.list[1] and B.Stats.list[1].name == "Kosplayer", "filter by name")
B.Stats.frame:Hide()

-- the enemy map in the open world, zoomed
B.db.map.world = true
B.db.map.zoom = 2
B:RefreshActive()
Mock.Tick(0.5)
ok(B.TacMap.frame:IsShown(), "enemy map in the open world")
ok(B.TacMap.nhits >= 1, "enemies drawn on the map")
-- the whole zone uncovered: every explored-area picture, tiled like WorldMapFrame.lua
do
  local TMo = B.TacMap
  ok(B.MapOverlays and B.MapOverlays.Durotar and B.MapOverlays.Gilneas, "overlay data for old and OctoWoW zones")
  TMo:BuildOverlays("Durotar")
  local org
  for i = 1, table.getn(TMo.ovList) do
    if string.find(TMo.ovList[i].tex, "ORGRIMMAR2$") then org = TMo.ovList[i] end
  end
  ok(org and org.x == 251 + 256 and org.w == 171 and org.h == 150 and org.u == 171 / 256 and org.v == 150 / 256,
    "Orgrimmar's second tile: 171 x 150 px of a 256 x 256 file")
  TMo:CropOverlays(0, 0, 1002, 668, 0.5)
  local shown = 0
  for i = 1, table.getn(TMo.ovList) do if TMo.ovTex[i]:IsShown() then shown = shown + 1 end end
  ok(shown == table.getn(TMo.ovList) and shown > 10, "every Durotar overlay drawn on the whole map (" .. shown .. ")")
  TMo:CropOverlays(0, 0, 100, 100, 5)
  ok(not TMo.ovTex[1]:IsShown() or TMo.ovList[1].x < 100, "zoomed in: overlays outside the view hidden")
  TMo.file = nil
  -- as the world map: M opens the game's map, OctoBG's big, or nothing
  local gameOpened = 0
  ToggleWorldMap = function() gameOpened = gameOpened + 1 end   -- pfUI's / the game's
  TMo.HookMapKey()
  B.db.map.worldKey = "game"
  ToggleWorldMap()
  ok(gameOpened == 1 and not TMo.big, "M: the game's world map")
  B.db.map.worldKey = "obg"
  ToggleWorldMap()
  ok(TMo.big and TMo.frame:IsShown() and TMo.frame:GetWidth() == B.db.map.bigWidth and gameOpened == 1, "M: OctoBG's map, big")
  ok(TMo.esc:IsShown(), "Escape can close it")
  ToggleWorldMap()
  ok(not TMo.big and TMo.frame:GetWidth() == B.db.map.width, "M again: back to the small map")
  TMo:SetBig(true)
  TMo.esc:Hide()
  ok(not TMo.big, "Escape closes the big map")
  B.db.map.worldKey = "off"
  ToggleWorldMap()
  ok(gameOpened == 1 and not TMo.big, "M: nothing when the world map is off")
  B.db.map.worldKey = "game"
  ToggleWorldMap = nil
  -- pfUI's addon buttons opened from the map's corner, kept beside the map
  local abp = CreateFrame("Frame", "pfMinimapButtons", UIParent)
  local moves = 0
  function abp:ProcessButtons()          -- pfUI puts it back at the minimap here
    moves = moves + 1
    self:ClearAllPoints()
    self:SetPoint("TOP", UIParent, "TOP", 0, 0)
  end
  abp:SetScript("OnShow", function() this:ProcessButtons() end)
  abp:Hide()
  pfUI = { addonbuttons = abp }
  TMo:Update()
  ok(TMo.abButton:IsShown(), "addon-buttons arrow in the map's corner when pfUI has the panel")
  Mock.Run(TMo.abButton, "OnClick")
  ok(abp:IsShown() and abp.point[2] == TMo.frame, "panel opens beside the map")
  abp:ProcessButtons()                   -- pfUI's 5 s update moves it away
  Mock.Run(TMo.frame, "OnUpdate", 0.02)
  ok(abp.point[2] == TMo.frame, "kept beside the map while open")
  Mock.Run(TMo.abButton, "OnClick")
  ok(not abp:IsShown() and not TMo.abOwned and abp.point[2] == UIParent, "closed: given back to pfUI")
  pfUI = nil
  TMo:Update()
  ok(not TMo.abButton:IsShown(), "no arrow without pfUI")
end
B.TacMap.hover = true
Mock.Tick(0.2)
B.TacMap:Click("LeftButton")
-- between the 0.2 s redraws every frame moves the markers (no ticker runs here)
local TMap = B.TacMap
ok(TMap.drawn and not TMap.fastBroken, "per-frame movement running on the real map")
local live
for i = 1, TMap.nfoes or 0 do
  if TMap.foes[i].live then live = TMap.foes[i] end
end
ok(live, "an enemy in sight is moved every frame")
if live then
  Mock.units[live.guid].x = Mock.units[live.guid].x + 3
  Mock.units[live.guid].y = Mock.units[live.guid].y - 2
  Mock.Run(TMap.frame, "OnUpdate", 0.016)
  local ex, ey = TMap:ToFrame(B.Map:ToMap(B.U.Position(live.guid)))
  local p = live.tri.point
  ok(p and math.abs(p[4] - ex) < 0.01 and math.abs(-p[5] - ey) < 0.01, "one frame later it sits on its new spot")
end
local vx0 = TMap.vx
Mock.pmx, Mock.pmy = 0.5, 0.45
Mock.Run(TMap.frame, "OnUpdate", 0.016)
ok(TMap.vx ~= vx0 and TMap.me.point, "zoomed: the view follows you every frame")
Mock.pmx, Mock.pmy = nil, nil
Mock.Tick(0.3)
ok(not TMap.fastBroken, "no errors in the per-frame pass")

-- wins and losses
Mock.target = "0x00000000000000A1"
Mock.Fire("CHAT_MSG_COMBAT_HOSTILE_DEATH", "You have slain Rogueone!")
ok(P:Get("Rogueone").wins == 1, "win counted")
Mock.Fire("SPELL_DAMAGE_EVENT_OTHER", "0x0000000000000001", "0x0000000000003BA7", 635, 300)
Mock.Fire("CHAT_MSG_COMBAT_FRIENDLY_DEATH", "You die.")
Mock.Tick(1.5)
ok(P:Get("Kosplayer").loses == 2, "loss counted to the last attacker (" .. tostring(P:Get("Kosplayer").loses) .. ")")

-- Spy's addon channel
B.db.spy.UseData = true
Mock.Fire("CHAT_MSG_ADDON", "[Spy]", "4.2.0,Farguy,MAGE,58,Gnome,Duskwood,Raven Hill,0.2,0.3,Far Guild,0x00000000000000B1", "PARTY", "Friend")
ok(NB.nearby.Farguy and not NB.active.Farguy, "reported enemy listed greyed")
ok(P:Get("Farguy") and P:Get("Farguy").class == "MAGE", "reported record")
B.db.spy.ShareData = true
Mock.party = 2
Mock.Enemy("0x00000000000000A3", "Newguy", "WARLOCK", 50, 50)
Mock.Fire("UNIT_AURA_GUID", "0x00000000000000A3", 1)
Mock.Tick(0.7)
local shared = false
for _, s in ipairs(Mock.sent) do
  if s[1] == "[Spy]" and string.find(s[2], "Newguy") then shared = true end
end
ok(shared, "new enemy shared on Spy's channel")

-- enemy leaves: active -> greyed -> gone
B.db.spy.RemoveUndetectedTime = 1
Mock.units["0x00000000000000A3"].near = false
Mock.Tick(4)
ok(NB.inactive.Newguy and not NB.active.Newguy, "out of sight: greyed")
Mock.Tick(62)
ok(not NB.nearby.Newguy, "forgotten after the timeout")

-- a battleground
Mock.zone, Mock.sub, Mock.pvp, Mock.instance = "Warsong Gulch", "", "combat", "pvp"
Mock.scores = { { "Rogueone", 1, "Rogue" }, { "Kosplayer", 1, "Paladin" }, { "Healbot", 1, "Priest" }, { "Tester", 0, "Warrior" } }
Mock.Fire("ZONE_CHANGED_NEW_AREA")
Mock.Tick(1)
ok(B.zone == "WSG", "in Warsong Gulch")
ok(R:Roster(), "roster mode")
ok(table.getn(R.list) >= 3, "scoreboard enemies listed (" .. table.getn(R.list) .. ")")
ok(B.TacMap.frame:IsShown(), "map shown in the battleground")

-- cross-faction battlegrounds: an Alliance character in our (Horde) raid is a teammate
local PAL = "0x00000000000000F7"
local pal = Mock.Enemy(PAL, "Holybro", "PALADIN", 6, 4)          -- faction Alliance, like every mock enemy
Mock.units.raid1, Mock.raid = pal, 1
table.insert(Mock.scores, { "Holybro", 0, "Paladin" })           -- the scoreboard: playing for the Horde
B.Tracker.units[PAL] = { guid = PAL, name = "Holybro", class = "PALADIN", seen = GetTime() }
B.Tracker.count = B.Tracker.count + 1
Mock.Fire("RAID_ROSTER_UPDATE")
Mock.Fire("UPDATE_BATTLEFIELD_SCORE")
ok(not B.Tracker.units[PAL], "cross-faction: an Alliance-race teammate leaves the enemy list")
ok(not B.Tracker:Consider(PAL), "cross-faction: and is never taken for an enemy")
ok(B.faction == "Horde", "our side from the scoreboard (Horde)")
-- we are put on the Alliance side: the EFC is whoever carries the ALLIANCE flag
for i = 1, table.getn(Mock.scores) do
  if Mock.scores[i][1] == "Tester" then Mock.scores[i][2] = 1 end
end
Mock.Fire("UPDATE_BATTLEFIELD_SCORE")
ok(B.faction == "Alliance" and B.enemy == "Horde", "cross-faction: playing for the Alliance")
Mock.Fire("CHAT_MSG_BG_SYSTEM_HORDE", "The Alliance flag was picked up by Rogueone!")
Mock.Fire("CHAT_MSG_BG_SYSTEM_ALLIANCE", "The Horde flag was picked up by Flagrunner!")
ok(B.Flags:Enemy() and B.Flags:Enemy().name == "Rogueone", "EFC = the one carrying our flag (" .. tostring(B.Flags:Enemy() and B.Flags:Enemy().name) .. ")")
ok(B.Flags:Friend() and B.Flags:Friend().name == "Flagrunner" and not B.Flags:Friend().enemy, "our carrier is not the EFC")
-- the side turning mid-game re-judges the carriers
for i = 1, table.getn(Mock.scores) do
  if Mock.scores[i][1] == "Tester" then Mock.scores[i][2] = 0 end
end
Mock.Fire("UPDATE_BATTLEFIELD_SCORE")
ok(B.Flags:Enemy() and B.Flags:Enemy().name == "Flagrunner" and B.Flags:Enemy().enemy, "side back to Horde: carriers judged again")
Mock.Fire("CHAT_MSG_BG_SYSTEM_NEUTRAL", "The flags are now placed at their bases.")
Mock.units.raid1, Mock.raid = nil, 0
table.remove(Mock.scores)
Mock.Fire("RAID_ROSTER_UPDATE")

-- height bars: steps above / below you, stacked on the marker
local HT = B.Map.HeightTier
ok(HT(305, 300, 10) == 0 and HT(309, 300, 10) == 0, "a few yards of slope: no bar")
ok(HT(312, 300, 10) == 1 and HT(325, 300, 10) == 2 and HT(345, 300, 10) == 3, "1 / 2 / 3 bars from 10 / 20 / 40 yd")
ok(HT(285, 300, 10) == -1 and HT(250, 300, 10) == -3, "below: negative steps")
ok(HT(nil, 300, 10) == nil, "no height: no bars")
local fo = B.TacMap:Foe(1)
B.TacMap:SetLevel(fo.lvl, 2)
ok(fo.lvl.bars[1].bg:IsShown() and fo.lvl.bars[2].bg:IsShown() and not fo.lvl.bars[3].bg:IsShown(), "two bars")
ok(fo.lvl.bars[1].bg.point[1] == "BOTTOMLEFT" and fo.lvl.bars[1].bg.point[3] == "RIGHT" and fo.lvl.bars[1].bg.point[2] == fo.tri,
  "higher: bars at the marker's right, going up")
B.TacMap:SetLevel(fo.lvl, -1)
ok(fo.lvl.bars[1].bg.point[1] == "TOPLEFT" and not fo.lvl.bars[2].bg:IsShown(), "lower: one bar at its right, going down")
B.db.map.heightPlace = "stack"
B.TacMap:SetLevel(fo.lvl, 1)
ok(fo.lvl.bars[1].bg.point[1] == "BOTTOM" and fo.lvl.bars[1].bg.point[3] == "TOP", "or stacked above the marker")
B.db.map.heightPlace, B.db.map.heightStyle = "side", "number"
B.TacMap:SetLevel(fo.lvl, 1, 14.6)
ok(fo.lvl.text:IsShown() and fo.lvl.text.text == "+15" and not fo.lvl.bars[1].bg:IsShown(), "yards look: +15")
B.db.map.heightStyle = "signs"
B.TacMap:SetLevel(fo.lvl, -2, -25)
ok(fo.lvl.text.text == "--", "signs look: --")
B.db.map.heightStyle = "bars"
B.TacMap:SetLevel(fo.lvl, 0)
ok(not fo.lvl.bars[1].bg:IsShown() and not fo.lvl.text:IsShown(), "level with you: nothing")
B.db.map.heightWho = "enemies"
ok(B.TacMap:HeightFor("enemy") and not B.TacMap:HeightFor("friend"), "on enemies only")
B.db.map.heightWho = "friends"
ok(B.TacMap:FloorOf(0, 0, 400, "enemy") == nil, "team only: no marks on enemies")
B.db.map.heightWho = "both"
B.db.map.height = "off"
ok(B.TacMap:FloorOf(0, 0, 400) == nil, "height marks off")
B.db.map.height = "on"
-- the above / below box on the map
B.TacMap.nUp, B.TacMap.nDown = 2, 7
B.TacMap:HeightBox()
local hb = B.TacMap.hbox
ok(hb:IsShown() and hb.upText.text == "2 above" and hb.downText.text == "7 below", "above / below box on the map")
ok(hb.point and hb.point[1] == "BOTTOMLEFT" and hb.point[2] == B.TacMap.frame, "box in its corner")
B.TacMap.nUp, B.TacMap.nDown = 0, 0
B.TacMap:HeightBox()
ok(not hb:IsShown(), "nobody above or below: no box")
-- names in a crowd move apart
local n1, n2 = B.TacMap:Foe(1), B.TacMap:Foe(2)
n1.hit, n2.hit = { x = 100, y = 50 }, { x = 104, y = 52 }
n1.name:SetText("Plateone-NZ") n2.name:SetText("Platetwo-NZ")
n1.name:Show() n2.name:Show()
B.TacMap:SpreadNames(2)
ok(n1.nameDy == 0 and n2.nameDy >= 10, "two names on one spot: the second moves a line down")
n1.name:Hide() n2.name:Hide()
n1.hit, n2.hit = nil, nil
-- map look: borders and the plaque
B.db.map.border, B.db.map.plaque = "gold", true
B.TacMap:Layout()
ok(B.TacMap.edge and B.TacMap.edge:IsShown() and B.TacMap.plaqueHolder:IsShown(), "gold frame and title plaque")
B.db.map.border, B.db.map.plaque = "thin", false
B.TacMap:Layout()
ok(not B.TacMap.edge:IsShown() and not B.TacMap.plaqueHolder:IsShown(), "back to the thin line")

-- the game's score frame, BigWigs' battleground bars, AV mode
local BT = B.BGTidy
B.db.tidy.scoreFrame = true
BT:ScoreFrame()
WorldStateAlwaysUpFrame:Show()
ok(not WorldStateAlwaysUpFrame:IsShown(), "score frame hidden in a battleground, and stays hidden")
B.db.tidy.scoreFrame = false
BT:ScoreFrame()
ok(WorldStateAlwaysUpFrame:IsShown(), "unticked: the score frame is back")
local bwBars = {}
local bwMod = { Bar = function(self, text) table.insert(bwBars, text) end }
BigWigs = { GetModule = function(self, name) if name == "Arathi Basin" then return bwMod end error("no module") end }
BT.bwDone = nil
BT:QuietBigWigs()
local zoneWas = B.zone
B.zone = "AB"
bwMod:Bar("Stables")
ok(table.getn(bwBars) == 0, "BigWigs' AB bar left out while our timers run")
B.db.tidy.bigwigs = false
bwMod:Bar("Farm")
ok(bwBars[1] == "Farm", "switch off: BigWigs' bars again")
B.db.tidy.bigwigs, B.zone, BigWigs = true, zoneWas, nil
-- AV mode with pfUI's nameplates: its hide settings while on, yours back after
pfUI = { nameplates = {} }
pfUI_config = { nameplates = { enemynpc = "0", neutralnpc = "0", friendlynpc = "1", friendlyplayer = "0", enemyplayer = "0" } }
SlashCmdList["OCTOBG"]("avmode on")
local pn = pfUI_config.nameplates
ok(B.db.avmode.on and pn.enemynpc == "1" and pn.neutralnpc == "1" and pn.friendlyplayer == "1" and pn.enemyplayer == "0",
  "AV mode: pfUI hides every plate but enemy players")
BT:ToggleAV()
ok(not B.db.avmode.on and pn.enemynpc == "0" and pn.friendlynpc == "1" and pn.friendlyplayer == "0", "AV mode off: pfUI's settings as they were")
pfUI, pfUI_config = nil, nil
-- game nameplates: NPC plates go invisible, enemy player plates stay
local border = Mock.New("Texture")
border:SetTexture("Interface\\Tooltips\\Nameplate-Border")
local npcPlate = Mock.Plate("0xF130001234000001")
Mock.Enemy("0xF130001234000001", "Frostwolf Guardian", "WARRIOR", 3, 3, { npc = true })
local foePlate = Mock.Plate("0x00000000000000A1")
npcPlate.GetRegions = function() return border end
foePlate.GetRegions = function() return border end
OctoBG_ToggleAVMode()
Mock.Tick(0.15)
ok(npcPlate.alpha == 0 and foePlate.alpha ~= 0, "AV mode: NPC plate hidden, enemy player plate kept")
OctoBG_ToggleAVMode()
ok(npcPlate.alpha == 1, "AV mode off: the NPC plate is back")
npcPlate.shown, foePlate.shown = false, false
-- the position axes are measured against the map, and a wrong saved value corrected
do
  local Mp = B.Map
  local savedSwap, pmx0, pmy0 = B.db.swapXY, Mock.pmx, Mock.pmy
  Mock.pmx, Mock.pmy = Mp:ToMap(Mock.px, Mock.py)        -- the map agrees with UnitPosition read straight
  B.db.swapXY = true
  local printed = table.getn(Mock.printed)
  ok(Mp:CheckAxes() == false and B.db.swapXY == false, "a wrong saved swap is corrected")
  ok(table.getn(Mock.printed) > printed, "and the correction is said in chat")
  Mock.pmx, Mock.pmy = Mp:ToMap(Mock.py, Mock.px)        -- ... read the other way round
  ok(Mp:CheckAxes() == true and B.db.swapXY == true, "swapped axes found")
  B.db.swapXY, Mock.pmx, Mock.pmy = savedSwap, pmx0, pmy0
end
-- without SuperWoW (no UnitPosition) the map says why it shows no enemies
do
  local hadPos = B.env.position
  B.env.position = false
  B.TacMap:Update()
  ok(string.find(B.TacMap.count.text or "", "SuperWoW", 1, true), "no SuperWoW: the map says so (" .. tostring(B.TacMap.count.text) .. ")")
  B.env.position = hadPos
  B.TacMap:Update()
  ok(not string.find(B.TacMap.count.text or "", "SuperWoW", 1, true), "with SuperWoW: the normal count")
end

-- enemy list: names never under the cooldown icons, at any width
local wasW = B.db.list.width
for _, w in ipairs({ 190, 240, 420 }) do
  B.db.list.width = w
  R:Layout()
  local row = R.rows[1]
  local nameEnd = row.name.point[4] + row.name.w
  ok(nameEnd <= row.cd[1].icon.point[4] and row.name.w >= 56,
    "width " .. w .. ": name ends at " .. nameEnd .. ", icons start at " .. row.cd[1].icon.point[4])
  local lastIcon = row.cd[R.nIcons > 0 and R.nIcons or 1].icon
  ok(lastIcon.point[4] + lastIcon.w <= row.w - 52, "width " .. w .. ": " .. R.nIcons .. " icons fit before the distance")
end
B.db.list.width = 190
R:Layout()
ok(R.nIcons == 2, "190 px: two cooldown icons")
B.db.list.width = wasW
R:Layout()
ok(R.nIcons == 3, "default width: three cooldown icons")

-- timers: readable labels, a click says the row in /bg
Mock.Fire("CHAT_MSG_BG_SYSTEM_NEUTRAL", "The battle for Warsong Gulch begins in 1 minute.")
Mock.Tick(0.2)
local trow = B.Timers.rows[1]
ok(trow:IsShown() and trow.say and string.find(trow.say, "Battle begins in", 1, true), "start timer row (" .. tostring(trow.say) .. ")")
ok(trow.label.color and trow.label.color[1] == 1 and trow.label.color[3] == 1, "label on a bar is white")
local chatBefore = table.getn(Mock.chat)
Mock.Run(trow, "OnClick")
local said = Mock.chat[chatBefore + 1]
ok(said and said[2] == "BATTLEGROUND" and string.find(said[1], "Battle begins in", 1, true), "click says it in /bg")
Mock.Run(trow, "OnClick")
ok(table.getn(Mock.chat) == chatBefore + 1, "a second click straight away is held back")
Mock.Run(trow, "OnEnter")
ok(GameTooltip.lines and table.getn(GameTooltip.lines) >= 2, "row tooltip says what a click sends")

-- INC counting: enemies at a base and running to it
local TR = B.Tracker
local now = GetTime()
local savedUnits = TR.units
TR.units = {
  a = { x = 100, y = 100, posAt = now, name = "At1" },
  b = { x = 130, y = 100, posAt = now, name = "At2" },
  c = { x = 200, y = 100, posAt = now, name = "Runner", head = math.atan2(0, -1), headAt = now },
  d = { x = 100, y = 220, posAt = now, name = "Leaving", head = math.atan2(1, 0), headAt = now },
  e = { x = 100, y = 105, posAt = now, name = "Dead", dead = true },
  f = { x = 100, y = 110, posAt = now - 10, name = "Stale" },
}
local at, coming = TR:CountIncoming(100, 100, 50, 3)
ok(at == 2 and coming == 1, "2 at the base, 1 running to it (got " .. at .. ", " .. coming .. ")")
local stables = { name = "Stables", x = 100, y = 100 }
local call = B.Incoming:AtText(stables)
ok(call == "2 AT STABLES + 1 INC", "click / Auto: what is AT the base (" .. call .. ")")
call = B.Incoming:IncText(stables)
ok(call == "1 INC STABLES (2 already there)", "automatic caller: INC (" .. call .. ")")
-- the enemy flag carrier: escort, call text, automatic calls
local FL = B.Flags
local efc = { name = "Runner", enemy = true, flag = B.faction, x = 100, y = 100, where = "Horde base", class = "ROGUE",
              hp = 64, hpmax = 100, since = now }
ok(FL:Escort(efc) == 2, "two enemies with the carrier")
ok(FL:CallText(efc) == "EFC Runner (Rogue) 64% - Horde base - with 2", "EFC call (" .. FL:CallText(efc) .. ")")
FL.carriers[B.faction] = efc
B.db.flags.autoCall = true
local chatN = table.getn(Mock.chat)
FL:AutoCall(GetTime())
ok(table.getn(Mock.chat) == chatN, "auto call waits for the place to hold 2 s")
Mock.now = Mock.now + 2.5
FL:AutoCall(GetTime())
ok(Mock.chat[chatN + 1] and Mock.chat[chatN + 1][2] == "BATTLEGROUND" and string.find(Mock.chat[chatN + 1][1], "EFC Runner", 1, true),
  "auto call posted to /bg")
FL:AutoCall(GetTime())
ok(table.getn(Mock.chat) == chatN + 1, "not again straight away")
efc.where = "midfield"
Mock.now = Mock.now + 3
FL:AutoCall(GetTime())
Mock.now = Mock.now + 2.5
FL:AutoCall(GetTime())
ok(table.getn(Mock.chat) == chatN + 1, "a new place waits for 10 s since the last call")
Mock.now = Mock.now + 5
FL:AutoCall(GetTime())
ok(Mock.chat[chatN + 2] and string.find(Mock.chat[chatN + 2][1], "midfield", 1, true), "new place called")
B.db.flags.autoCall = false
FL.carriers = {}
TR.units = savedUnits
-- the map: drag the zoomed view, back to me, click a base to call it
local TMap = B.TacMap
B.db.map.zoom = 3
TMap.vx = nil
Mock.Tick(0.3)
ok(TMap.vz == 3, "map zoomed in")
local vx0 = TMap.vx
local maxVx = 1002 - TMap.w / TMap.k
local dir = (vx0 > maxVx / 2) and 60 or -60     -- drag towards the open side
Mock.cx, Mock.cy = 200, 600
Mock.Run(TMap.frame, "OnMouseDown", "LeftButton")
Mock.cx = 200 + dir
TMap:DragTick()
ok(TMap.pan and math.abs(TMap.vx - vx0) > 1, "dragging moves the view (" .. vx0 .. " -> " .. tostring(TMap.vx) .. ")")
local chatM = table.getn(Mock.chat)
Mock.Run(TMap.frame, "OnMouseUp", "LeftButton")
ok(not TMap.dragFrom and table.getn(Mock.chat) == chatM, "a drag is not a click")
Mock.Tick(0.3)
ok(TMap.pan and TMap.back:IsShown(), "dragged view stays, Back to me shows")
Mock.Run(TMap.back, "OnClick")
ok(TMap.pan == nil, "Back to me follows you again")
B.db.map.zoom = 1
TMap.vx = nil
Mock.Tick(0.3)
local base1 = B.Incoming.bases[1]
local bmx, bmy
if base1 and base1.x then bmx, bmy = B.Map:ToMap(base1.x, base1.y) end
ok(bmx, "first base has a map spot")
if bmx then
  local bx, by = TMap:ToFrame(bmx, bmy)
  Mock.cx, Mock.cy = 100 + bx, 700 - by
  TMap.hover, TMap.tipFor = true, nil
  TMap:HoverTick()
  ok(GameTooltip.lines[1] == base1.name, "hovering a base's spot shows its counts")
  -- every base: a circle and a clickable label above the enemy markers
  local mark = TMap.baseMarks[1]
  ok(mark and mark.ring:IsShown() and mark.badge:IsShown() and mark.badge.base, "base circle and label always shown")
  ok(mark.badge:GetFrameLevel() > TMap.foeLayer:GetFrameLevel(), "label sits above the enemy markers")
  ok(string.find(mark.badge.text.text or "", mark.badge.base.short, 1, true), "label names the base (" .. tostring(mark.badge.text.text) .. ")")
  Mock.Run(mark.badge, "OnEnter")
  ok(GameTooltip.lines[1] == mark.badge.base.name, "hovering the label: its counts")
  chatM = table.getn(Mock.chat)
  Mock.now = Mock.now + 5
  Mock.Run(mark.badge, "OnClick", "LeftButton")
  local m = Mock.chat[chatM + 1]
  ok(m and m[2] == "BATTLEGROUND" and (string.find(m[1], " AT " .. string.upper(mark.badge.base.name), 1, true)
    or string.find(m[1], string.upper(mark.badge.base.name) .. " - no enemies seen", 1, true)), "clicking a label posts what is AT it (" .. tostring(m and m[1]) .. ")")
  Mock.Run(mark.badge, "OnClick", "RightButton")
  ok(B.Incoming.pinned == mark.badge.base.name, "right-click picks it on the INC bar")
  B.Incoming.pinned = nil
  -- circles are cut off at the map's edge, never drawn over the screen around it
  TMap:PinRound(mark.ring, 0, 0.5, 100)
  ok(mark.ring:IsShown() and math.abs(mark.ring:GetWidth() - 50) < 0.01 and math.abs(mark.ring:GetHeight() - 100) < 0.01,
    "a circle on the map's left edge shows only its right half (" .. tostring(mark.ring:GetWidth()) .. ")")
  TMap:PinRound(mark.ring, 0.5, 0.5, TMap.w * 3)
  ok(mark.ring:GetWidth() <= TMap.w + 0.01 and mark.ring:GetHeight() <= TMap.h + 0.01, "a huge circle stays inside the map")
  TMap:PinRound(mark.ring, -1, 0.5, 40)
  ok(not mark.ring:IsShown(), "a circle wholly off the map is hidden")
  TMap:DrawBases()
  B.db.map.bases = false
  TMap:DrawBases()
  ok(not mark.badge:IsShown() and not mark.ring:IsShown(), "base circles can be switched off")
  B.db.map.bases = true
  TMap.hover = nil
end

-- ---------------------------------------------------------------- score panel, prediction, scoreboard
do
  local SP, TM = B.BGScore, B.Timers
  -- Warsong Gulch: big flag scores and the carrier
  Mock.states = { { "1/3", "Interface\\WorldStateFrame\\AllianceFlag" }, { "2/3", "Interface\\WorldStateFrame\\HordeFlag" } }
  Mock.Fire("UPDATE_WORLD_STATES")
  ok(TM.score.Alliance.cur == 1 and TM.score.Horde.cur == 2 and TM.score.Horde.max == 3, "WSG score read at once")
  Mock.Tick(0.3)
  ok(SP.frame:IsShown() and SP.mode == "flags", "score panel in Warsong Gulch: flag score")
  ok(SP.big.Alliance.num.text == 1 or SP.big.Alliance.num.text == "1", "Alliance's score shown")
  ok(SP.title.text == "Warsong Gulch", "the panel names the battleground")
  Mock.Fire("CHAT_MSG_BG_SYSTEM_HORDE", "The Alliance flag was picked up by Rogueone!")
  Mock.Tick(0.1)
  -- the carriers live inside the score panel: one window
  local FLG = B.Flags
  Mock.Tick(0.3)
  ok(FLG.docked and FLG:Merged() and not FLG.frame:IsShown(), "flag carriers are inside the score panel, no second window")
  ok(FLG.rows[1]:IsShown() and FLG.rows[2]:IsShown(), "both rows show there")
  local carried = (FLG.rows[1].name.text or "") .. (FLG.rows[2].name.text or "")
  ok(string.find(carried, "Rogueone", 1, true), "who carries it (" .. carried .. ")")
  -- Focused Assault: one stack a minute, +10 % each, from the pickup alone
  local cr = FLG:Enemy() or FLG:Friend()
  local crRow = (FLG:Enemy() == cr) and FLG.rows[1] or FLG.rows[2]
  local keepSince = cr.since
  cr.since = GetTime() - 135
  local st, nx = FLG:Stacks(cr, GetTime())
  ok(st == 2 and math.abs(nx - 45) < 0.1, "stacks from time held: 2 after 2:15, next in 45 s (" .. st .. ", " .. tostring(nx) .. ")")
  FLG:Refresh()
  ok(crRow.stack.text == "x2 +20%", "the row shows them: " .. tostring(crRow.stack.text))
  -- seen live: the aura's real count wins
  cr.guid = cr.guid or "0xF00000000000CC01"
  Mock.Fire("DEBUFF_ADDED_OTHER", cr.guid, 1, 44094, 5, 60, 32, 2)
  ok((FLG:Stacks(cr, GetTime())) == 5, "the aura's own count overrules the clock")
  Mock.Fire("DEBUFF_ADDED_OTHER", cr.guid, 1, 12345, 9, 60, 33, 2)
  ok((FLG:Stacks(cr, GetTime())) == 5, "other debuffs are ignored")
  cr.since, cr.liveN, cr.liveAt = GetTime() - 30000, nil, nil
  ok((FLG:Stacks(cr, GetTime())) == 99, "99 at most")
  cr.since = keepSince
  cr.liveN, cr.liveAt = nil, nil
  FLG:Refresh()
  -- the score panel switched off: they get their own window back
  B.db.bgscore.enabled = false
  Mock.Tick(0.5)
  ok(not FLG.docked and FLG.frame:IsShown() and FLG.rows[1]:IsShown(), "score panel off: their own window")
  B.db.bgscore.enabled = true
  Mock.Tick(0.5)
  ok(FLG.docked and not FLG.frame:IsShown(), "and back inside when it returns")
  Mock.Fire("CHAT_MSG_BG_SYSTEM_NEUTRAL", "The flags are now placed at their bases.")
  -- Arathi Basin: exact prediction, instantly
  Mock.zone = "Arathi Basin"
  Mock.Fire("ZONE_CHANGED_NEW_AREA")
  Mock.states = { { "Bases: 2  Resources: 690/2000", "Interface\\x\\Alliance" }, { "Bases: 3  Resources: 1100/2000", "Interface\\x\\Horde" } }
  Mock.Fire("UPDATE_WORLD_STATES")
  local pr = TM.pred
  ok(pr and pr.winner == "Horde", "Horde is ahead with more bases")
  ok(pr and math.abs((pr.at - GetTime()) - 540) < 0.01, "90 ticks of 6 s: wins in 9:00 (" .. tostring(pr and (pr.at - GetTime())) .. ")")
  -- both sides tick at exactly 540 s here, so the last tick can fall either side of the win
  ok(pr and (pr.score == 1290 or pr.score == 1280), "the loser's points then: 690 + 59-60 ticks of 10 (" .. tostring(pr and pr.score) .. ")")
  Mock.Tick(0.3)
  ok(SP.mode == "bars" and string.find(SP.pred.text.text or "", "Horde wins in", 1, true), "prediction on the panel: " .. tostring(SP.pred.text.text))
  ok(SP.bars.Horde.text.text == "1100/2000" and SP.bars.Horde.bases.text == "3 bases", "resources and bases on the bars")
  local before, beforeScore = pr.at, pr.score
  Mock.Tick(1)
  ok(math.abs(TM.pred.at - before) < 0.01, "time passing keeps the same moment: it counts down smoothly")
  -- a base flips: the answer changes at once, before any score arrives
  TM.obj:Contest("Farm", "Alliance", 60)
  ok(TM.pred.score > beforeScore, "a base being captured changes the prediction instantly (" .. TM.pred.score .. ")")
  Mock.states = { { "Bases: 5  Resources: 690/2000", "Interface\\x\\Alliance" }, { "Bases: 0  Resources: 1100/2000", "Interface\\x\\Horde" } }
  Mock.Fire("UPDATE_WORLD_STATES")
  ok(TM.pred.winner == "Alliance", "five bases to none: the winner turns at once")
  -- a server that ticks differently is learned from two equal ticks
  Mock.states = { { "Bases: 5  Resources: 715/2000", "Interface\\x\\Alliance" }, { "Bases: 0  Resources: 1100/2000", "Interface\\x\\Horde" } }
  Mock.Tick(2)
  Mock.Fire("UPDATE_WORLD_STATES")
  Mock.states[1][1] = "Bases: 5  Resources: 740/2000"
  Mock.Tick(2)
  Mock.Fire("UPDATE_WORLD_STATES")
  ok(B.db.abTicks and B.db.abTicks[5] and B.db.abTicks[5][1] == 25, "two equal ticks unlike the table: learned")
  B.db.abTicks = nil
  ok(SP:Shows("nodes") and SP.nodes[1]:IsShown(), "the five bases on the panel")
  -- the graveyard row
  ok(string.find(SP.nodes[5].text.text or "", ":", 1, true), "the Farm's capture timer")
  local WV = B.Timers.spirit
  WV.guides, WV.n, WV.areaWave, WV.waveAt, WV.waveSrc, WV.waveGuide, WV.conflicts, WV.perGuide, WV.clockErr = {}, 0
  Mock.runtime = 0
  Mock.Tick(0.1)
  ok(SP.gy:IsShown() and SP.gy.time.text == "" and not SP.gy.say, "graveyard row: blank until the game's clock runs")
  -- no graveyard seen at all: the wave comes from the battleground's clock
  Mock.runtime = 70000
  ok(math.abs(WV:MyWave(GetTime()) - 20.12) < 0.01, "the wave is known from the game's clock alone (" .. tostring(WV:MyWave(GetTime())) .. ")")
  Mock.Tick(0.1)
  ok(string.find(SP.gy.time.text or "", "0:2", 1, true) and SP.gy.name.text == "Next res wave" and not SP.gy.confirmed,
    "graveyard row: a time with no guide seen, not yet confirmed (" .. tostring(SP.gy.time.text) .. ")")
  ok(SP.gy.sweep:IsShown() and SP.gy.say and string.find(SP.gy.say, "res wave", 1, true), "its bar, and a click says it")
  ok(WV:NextWave("Horde", GetTime()) and WV:NextWave("Alliance", GetTime()), "the same wave for either side, for the enemy list")
  -- a real heal locks it on: 5 s off the clock's guess, measured and followed
  Mock.Tick(15)
  Mock.runtime = nil
  Mock.Fire("SPELL_GO_OTHER", 0, 22012, "0xF13000333D000AAA", "0xF13000333D000AAA")
  Mock.Enemy("0xF13000333D000AAA", "Spirit Guide", "WARRIOR", 5, 5, { npc = true })
  ok(WV.waveSrc == "seen" and WV.waveAt == GetTime(), "a heal seen locks the wave on")
  Mock.Tick(10)
  ok(math.abs(WV:MyWave(GetTime()) - 20.04) < 0.5 and SP.gy.confirmed, "and counts from it (" .. tostring(WV:MyWave(GetTime())) .. ")")
  -- the next waves come 30.04 s apart, not drifting from a 30 s count
  Mock.Tick(300)
  ok(math.abs(WV:Global(GetTime()) - 20.4) < 0.6, "ten waves on it has not drifted (" .. tostring(WV:Global(GetTime())) .. ")")
  -- the check: another graveyard healing out of step goes back to per graveyard
  WV.conflicts = nil
  for i = 1, 3 do
    Mock.Fire("SPELL_GO_OTHER", 0, 22012, "0xF13000333D000BBB", "0xF13000333D000BBB")
    Mock.Tick(11)
    Mock.Fire("SPELL_GO_OTHER", 0, 22012, "0xF13000333D000AAA", "0xF13000333D000AAA")
    Mock.Tick(19)
  end
  ok(WV.perGuide, "graveyards healing out of step: back to timing each one")
  -- graveyards in step never trip it (one tick apart)
  WV.perGuide, WV.conflicts, WV.waveAt, WV.waveGuide = nil, nil, nil, nil
  for i = 1, 5 do
    Mock.Fire("SPELL_GO_OTHER", 0, 22012, "0xF13000333D000BBB", "0xF13000333D000BBB")
    Mock.Tick(0.2)
    Mock.Fire("SPELL_GO_OTHER", 0, 22012, "0xF13000333D000AAA", "0xF13000333D000AAA")
    Mock.Tick(29.8)
  end
  ok(not WV.perGuide and not WV.conflicts, "graveyards in step are one wave")
  Mock.units["0xF13000333D000AAA"] = nil
  Mock.Tick(0.1)
  TM:Paint(GetTime())
  -- back to Warsong Gulch: the counting
  Mock.zone, Mock.states = "Warsong Gulch", nil
  Mock.Fire("ZONE_CHANGED_NEW_AREA")
  local BS, BD = B.BGStats, B.Scoreboard
  local ME2 = "0x0000000000000001"
  local FOE1 = "0x00000000000000A1"
  local PET = "0xF140000000000009"
  Mock.Enemy(PET, "Wolf", "WARRIOR", 3, 3, { npc = true, summonedBy = FOE1 })
  Mock.Fire("AUTO_ATTACK_SELF", ME2, FOE1, 500, 0, 1, 1, 0, 0, 0)
  Mock.Fire("SPELL_DAMAGE_EVENT_SELF", FOE1, ME2, 133, 1000, "0,0,0", 0, 2, "0,0,0,0")
  Mock.Fire("SPELL_HEAL_BY_SELF", ME2, ME2, 2061, 700, 0, 0)
  Mock.Fire("SPELL_HEAL_ON_SELF", ME2, ME2, 2061, 700, 0, 0)
  local d, h = BS:Get("Tester")
  ok(d == 1500 and h == 700, "your damage and healing, a self heal once (" .. d .. ", " .. h .. ")")
  Mock.Fire("AUTO_ATTACK_OTHER", FOE1, ME2, 300, 0, 1, 1, 0, 0, 0)
  Mock.Fire("AUTO_ATTACK_OTHER", PET, ME2, 40, 0, 1, 1, 0, 0, 0)
  Mock.Fire("SPELL_DAMAGE_EVENT_OTHER", ME2, FOE1, 116, 60, "0,0,0", 0, 4, "0,0,0,3")
  Mock.Fire("DAMAGE_SHIELD_OTHER", FOE1, ME2, 5, 3)
  Mock.Fire("SPELL_HEAL_BY_OTHER", FOE1, FOE1, 2061, 90, 0, 1)
  d, h = BS:Get("Rogueone")
  ok(d == 405 and h == 90, "an enemy with their pet, DoT tick and shield (" .. d .. ", " .. h .. ")")
  local NPC = "0xF130000000000123"
  Mock.Enemy(NPC, "Guard", "WARRIOR", 2, 2, { npc = true })
  Mock.Fire("AUTO_ATTACK_OTHER", NPC, ME2, 999, 0, 1, 1, 0, 0, 0)
  ok(not BS.totals.Guard, "an NPC counts for nobody")
  local FAR = "0x00000000000000B9"
  Mock.Fire("SPELL_HEAL_BY_OTHER", FOE1, FAR, 2061, 50, 0, 0)
  local fare = Mock.Enemy(FAR, "Faraway", "PRIEST", 90, 90)
  Mock.Tick(4.1)
  local _, fh = BS:Get("Faraway")
  ok(fh == 50, "a healer not seen yet gets the heal once their name is known (" .. tostring(fh) .. ")")
  -- team sync: the highest count of each wins, nothing is added twice
  Mock.Fire("CHAT_MSG_ADDON", "OBG", "H2.3.3,1", "BATTLEGROUND", "Friend")
  Mock.Fire("CHAT_MSG_ADDON", "OBG", "DRogueone,9000,10;Tester,1,1", "BATTLEGROUND", "Friend")
  d, h = BS:Get("Rogueone")
  ok(d == 9000 and h == 90, "a teammate's higher count merges (" .. d .. ", " .. h .. ")")
  d = BS:Get("Tester")
  ok(d == 1500, "a lower one doesn't")
  -- the table
  Mock.scores = { { "Tester", 0, "Warrior", 3, 10, 2, 150, "Orc" }, { "Rogueone", 1, "Rogue", 7, 12, 1, 90, "Human" },
                  { "Holy", 1, "Priest", 0, 5, 4, 40, "Human" } }
  BD:Open()
  ok(BD.frame:IsShown(), "scoreboard opens")
  ok(BD.list[1].name == "Rogueone", "sorted by damage (" .. tostring(BD.list[1].name) .. ")")
  BD:SortBy("kb")
  ok(BD.list[1].name == "Rogueone" and BD.list[3].name == "Holy", "sort by killing blows")
  BD:SortBy("kb")
  ok(BD.list[1].name == "Holy", "again: the other way")
  BD:SortBy("name")
  ok(BD.list[1].name == "Holy" and BD.list[3].name == "Tester", "names from A")
  BD.tab = "Horde"
  BD:Refresh()
  ok(table.getn(BD.list) == 1 and BD.list[1].name == "Tester", "one side only")
  BD.tab = "all"
  BD:Refresh()
  -- clearly by team: each under a heading, with its totals; every row its team's flag
  Mock.Fire("UPDATE_BATTLEFIELD_SCORE")
  BD:Refresh()
  ok(BD.shown[1].header == "Alliance" and BD.shown[4].header == "Horde" and table.getn(BD.shown) == 5, "a heading for each team")
  ok(BD.shown[1].sums.kb == 7 and BD.shown[4].sums.kb == 3, "the headings add up their team")
  ok(BD.rows[1]:IsShown() and not BD.rows[1].entry and string.find(BD.rows[1].cells[1].text, "ALLIANCE - ENEMY", 1, true), "says whose team: " .. tostring(BD.rows[1].cells[1].text))
  ok(string.find(BD.rows[4].cells[1].text, "HORDE - YOUR TEAM", 1, true), "and yours")
  ok(BD.rows[2].entry.fac == "Alliance" and not BD.rows[2].flag and not BD.flagA and not BD.flagFootA, "no team flags on the board, the colours say it")
  -- the hover panel: instant, from what was counted
  local ROG, HOLY = "0xF00000000000AB01", "0xF00000000000AB02"
  Mock.Enemy(ROG, "Rogueone", "ROGUE", 5, 5)
  Mock.Enemy(HOLY, "Holy", "PRIEST", 6, 6)
  BS.kind[1766], BS.kind[408] = "int", "cc"
  Mock.Fire("UNIT_CASTEVENT", HOLY, "", "START", 585, 2500)
  local before = BS:Detail("Rogueone")
  Mock.Fire("SPELL_GO_OTHER", 0, 1766, ROG, HOLY, 0, 1, 0)
  Mock.Fire("SPELL_GO_OTHER", 0, 408, ROG, HOLY, 0, 1, 0)
  Mock.Fire("SPELL_GO_OTHER", 0, 408, ROG, HOLY, 0, 0, 1)
  Mock.Fire("UNIT_CASTEVENT", HOLY, "", "CAST", 585, 0)
  Mock.Fire("SPELL_GO_OTHER", 0, 1766, ROG, HOLY, 0, 1, 0)
  local after = BS:Detail("Rogueone")
  ok(after.int == before.int + 1, "an interrupt counts only on someone casting (" .. after.int .. ")")
  ok(after.cc == before.cc + 1, "crowd control counts when it lands, not when it misses (" .. after.cc .. ")")
  Mock.Fire("SPELL_DISPEL_BY_OTHER", ROG, ROG, 123)
  ok(BS:Detail("Rogueone").cleanse == after.cleanse + 1, "a dispel on your own side is a cleanse")
  B.scoreSide.Tester = "Horde"
  B.raidGuid = { [ROG] = true }
  Mock.Fire("SPELL_DISPEL_BY_OTHER", ROG, HOLY, 123)
  local d2 = BS:Detail("Rogueone")
  ok(d2.purge == after.purge + 1 or d2.cleanse == after.cleanse + 2, "a dispel across the sides is told apart by team")
  B.raidGuid = {}
  Mock.Fire("SPELL_DAMAGE_EVENT_OTHER", HOLY, ROG, 1766, 700, "0,0,0", 0, 0, "0,0,0,0")
  local d3 = BS:Detail("Rogueone")
  ok(d3.bigHit >= 700 and d3.topD[1] and BS:Detail("Holy").taken >= 700, "biggest hit, top spells, damage taken")
  BS:MergeX("Rogueone", 0, 0, 9, 0, 0, 0, 0)
  ok(BS:Detail("Rogueone").int == 9, "a teammate's higher count merges")
  Mock.Fire("CHAT_MSG_ADDON", "OBG", "XRogueone,1,2,10,4,5,6,7", "BATTLEGROUND", "Friend")
  ok(BS:Detail("Rogueone").int == 10, "over team sync too")
  BD:RowTip(BD.rows[2])
  ok(BD.tip:IsShown() and BD.tip.lines[1].l.text == BD.rows[2].entry.name, "hovering a player shows the panel at once")
  local tipText = ""
  for i = 1, table.getn(BD.tip.lines) do tipText = tipText .. (BD.tip.lines[i].l:IsShown() and (BD.tip.lines[i].l.text or "") or "") .. "|" end
  for _, want in ipairs({ "Interrupts", "Crowd control", "Cleanses", "Purges", "Killing blows", "Biggest hit", "Received" }) do
    ok(string.find(tipText, want, 1, true), "the panel lists " .. want)
  end
  BD:RowTip(BD.rows[1])
  ok(not BD.tip:IsShown(), "a heading has none")
  BD:RowTip(BD.rows[2])
  Mock.Run(BD.rows[2], "OnLeave")
  ok(not BD.tip:IsShown(), "leaving the row hides it")
  ok(not BD.rows[1].icon:IsShown() and BD.rows[2].icon:IsShown(), "a heading has no class icon, a player does")
  ok(BD.rows[5].meTop:IsShown() and not BD.rows[2].meTop:IsShown(), "you are lined in gold, the team's colour stays")
  B.db.board.group = false
  BD:Refresh()
  ok(table.getn(BD.shown) == 3 and not BD.shown[1].header, "the setting off: everyone sorted together")
  B.db.board.group = true
  BD:Refresh()
  -- the team, not the race: the raid overrules, and realm names are matched with care
  local keepScores, keepRaid = Mock.scores, B.raidName
  Mock.scores = { { "Tester", 0, "Warrior" }, { "Pala", 1, "Paladin" }, { "Archerone-NZ", 1, "Hunter" },
                  { "Same", 0, "Mage" }, { "Same-NZ", 1, "Mage" } }
  B.raidName = { Pala = true }
  Mock.Fire("UPDATE_BATTLEFIELD_SCORE")
  ok(B:TeamOf("Pala") == "Horde", "in our raid = our team, whatever the row says")
  ok(B:SideOf(nil, "Pala") == "friend", "so not an enemy")
  ok(B:TeamOf("Archerone") == "Alliance" and B:TeamOf("Archerone-NZ") == "Alliance", "Name and Name-NZ are one player")
  ok(B:TeamOf("Same") == "Horde" and B:TeamOf("Same-NZ") == "Alliance", "one name on two realms stays two players")
  ok(B:TeamOf("Same-XX") == nil, "and is never guessed")
  local rowsNow = BD:ReadGame()
  ok(rowsNow[2].fac == "Horde", "the board uses that team")
  B.scoreSide, B.scoreShort = {}, {}
  Mock.scores, B.raidName = keepScores, keepRaid
  Mock.Fire("UPDATE_BATTLEFIELD_SCORE")
  BD:Refresh()
  -- flag carriers: one line each, never wrapping or running into the next text
  local FR = B.Flags.rows[1]
  ok(B.Flags.frame.artEdge ~= nil or B.db.bgscore.border == "none", "the flag panel has the score panel's frame")
  B.Flags.Fit(FR.sub, "Horde base - lower level - 212 yd - with 3 and a very long tail", 120)
  ok(FR.sub:GetStringWidth() <= 120 and string.find(FR.sub.text, "..", 1, true), "a long line is cut to fit (" .. FR.sub.text .. ")")
  B.Flags.Fit(FR.sub, "short", 120)
  ok(FR.sub.text == "short", "a short one is left alone")
  ok(not FR.sub.width, "no wrap width set on it")
  local c2 = BD.cols[2].key
  BD:MoveColumn(c2, 1)
  ok(BD.cols[3].key == c2 and BD.cols[1].key == "name", "a column moved right; the name stays first")
  B.db.board.hide.honor = true
  BD:Refresh()
  local hasHonor = false
  for _, c in ipairs(BD.cols) do if c.key == "honor" then hasHonor = true end end
  ok(not hasHonor, "a column hidden")
  B.db.board.hide.honor = nil
  B.db.board.order, B.db.board.sort, B.db.board.desc = {}, "damage", true
  ok(string.find(BD.totalA.text or "", "Alliance: 2 players", 1, true), "team totals: " .. tostring(BD.totalA.text))
  BD.frame:Hide()
  -- the end: frozen numbers, opens by itself, the game's frame stays away, last game kept
  WorldStateScoreFrame = Mock.New("Frame", "WorldStateScoreFrame", UIParent)
  HideUIPanel = function(f) f:Hide() end
  LeaveBattlefield = function() Mock.left = true end
  Mock.winner = 0
  Mock.Tick(0.6)
  ok(BS.over, "the game ended: counting stops")
  Mock.Fire("AUTO_ATTACK_SELF", ME2, FOE1, 5000, 0, 1, 1, 0, 0, 0)
  ok(BS:Get("Tester") == 1500, "nothing added after the end")
  Mock.Tick(1.1)
  ok(BD.frame:IsShown() and B.db.lastGame and B.db.lastGame.winner == 0, "opens at the end, last game kept")
  ok(string.find(BD.result.text or "", "Horde wins", 1, true), "says who won")
  ok(BD.titleText.text == "Warsong Gulch Scoreboard", "the title names the battleground: " .. tostring(BD.titleText.text))
  ok(BD.pic.file == "WarsongGulch" and BD.pic.tiles[1].texture == "Interface\\WorldMap\\WarsongGulch\\WarsongGulch1", "its map behind the window")
  ok(B.db.lastGame.zoneKey == "WSG", "the last game remembers which battleground")
  WorldStateScoreFrame:Show()
  Mock.Tick(0.6)
  ok(not WorldStateScoreFrame:IsShown(), "the game's frame stays away")
  -- to the game's own and back again
  Mock.Run(BD.gameBtn, "OnClick")
  ok(BD.useGame and not BD.frame:IsShown() and WorldStateScoreFrame:IsShown(), "the game's own opens")
  Mock.Tick(0.6)
  ok(WorldStateScoreFrame:IsShown(), "and stays while chosen")
  ok(BD.backBtn and BD.backBtn.parent == WorldStateScoreFrame, "with a button back on it")
  Mock.Run(BD.backBtn, "OnClick")
  ok(not BD.useGame and BD.frame:IsShown() and not WorldStateScoreFrame:IsShown(), "the button returns to ours")
  -- each battleground's look, with sample players
  for _, k in ipairs({ "WSG", "AB", "AV", "TG" }) do
    BD:Preview(k)
    ok(BD.pic.file == B.Map.DATA[k].file and table.getn(BD.list) == 10, "preview of " .. k)
  end
  BD.frame:Hide()
  ok(not BD.preview, "closing ends the preview")
  BD:Open()
  Mock.Run(BD.leave, "OnClick")
  ok(Mock.left and not BD.frame:IsShown(), "Leave battleground works from our window")
  SlashCmdList["OCTOBG"]("score")
  ok(BD.frame:IsShown(), "/obg score")
  BD.frame:Hide()
  WorldStateScoreFrame, HideUIPanel, LeaveBattlefield = nil, nil, nil
  Mock.winner, Mock.units[PET], Mock.units[NPC], Mock.units[FAR] = nil, nil, nil, nil
  fare = nil
  B.db.lastGame = nil
  Mock.scores = { { "Rogueone", 1, "Rogue" }, { "Flagrunner", 1, "Paladin" }, { "Healbot", 1, "Priest" }, { "Tester", 0, "Warrior" } }
end

-- layout mode
B.U.SetLocked(false)
Mock.Tick(1)
B.U.SetLocked(true)
Mock.Tick(0.3)

-- leave
Mock.zone, Mock.sub, Mock.pvp, Mock.instance = "Orgrimmar", "", "friendly", nil
Mock.Fire("ZONE_CHANGED_NEW_AREA")
Mock.Tick(0.5)
Mock.pvp = "sanctuary"
NB:ZoneCheck()
ok(not NB.enabledInZone, "sanctuary pauses detection")

-- slash commands
SlashCmdList["OCTOBG"]("status")
SlashCmdList["OCTOBG"]("kos Somebody")
ok(P:IsKOS("Somebody"), "/obg kos")
SlashCmdList["OCTOBG"]("ignore Other")
ok(P:IsIgnored("Other"), "/obg ignore")
ok(SlashCmdList["OCTOBGSPY"] == nil, "/spy left to the old addon while it was loaded")
SlashCmdList["OCTOBG"]("world off")
ok(not B.db.spy.Enabled, "/obg world off")
SlashCmdList["OCTOBG"]("world on")
OctoBG_ToggleMap()
OctoBG_ToggleMap()
OctoBG_ToggleList()
OctoBG_ToggleList()
NB:MoveBox(true)
NB:MoveBox(false)

-- ---------------------------------------------------------------- combat text: moved to pfUI Octo
-- (19 Oct 2026, pfUI\modules\sct*.lua; its tests moved too, pfUI\tests\sct.lua).
-- OctoBG keeps the link: sounds, alerts sent on.
local ME = "0x0000000000000001"
local FOE = "0x00000000000000C1"
Mock.Enemy(FOE, "Punchbag", "WARRIOR", 15, 0)
ok(B.SCT and B.SCT.Notify and B.SCT.PlaySound and not B.SCT.Plate, "link to pfUI's combat text")
ok(B.SCT.Notify and pcall(B.SCT.Notify, B.SCT, "obgCd", "Blind ready"), "alerts without pfUI: no error")
local soundsBefore = table.getn(Mock.sounds)
B.SCT.PlaySound("RaidWarning")
ok(table.getn(Mock.sounds) == soundsBefore + 1, "sounds still play without pfUI")
ok(B.db.sct == nil or type(B.db.sct) == "table", "old combat text settings left in the saved file for pfUI to copy")
ok(not OctoBGCombatText, "OctoBG draws no combat text any more")
ok(not (B.Layout.INFO.sct_inc), "no combat text boxes in Move frames")
B.U.SetLocked(false)
-- the hover toolbar on a move box
local LY = B.Layout
local hud = B.U.panels[1]
for i = 1, table.getn(B.U.panels) do if B.U.panels[i].key == "map" then hud = B.U.panels[i] end end
Mock.Run(hud.handle, "OnEnter")
ok(LY.bar and LY.bar:IsShown() and LY.target == hud, "hovering a move box opens its toolbar")
ok(OctoBGMoveBar and LY.bar.size.text == "100%", "toolbar shows the size (" .. tostring(LY.bar.size.text) .. ")")
Mock.Run(hud.handle, "OnMouseWheel", 1)
ok(B.db.panels.map.scale == 1.05, "wheel: bigger (" .. tostring(B.db.panels.map.scale) .. ")")
Mock.shift = true
Mock.Run(hud.handle, "OnMouseWheel", -1)
Mock.shift = nil
ok(B.db.panels.map.alpha == 0.95, "shift + wheel: more see-through (" .. tostring(B.db.panels.map.alpha) .. ")")
LY:Size(hud, 40)
ok(B.db.panels.map.scale == 2, "size stops at 200%")
local wasOn = B.db.map.enabled
B.U.TogglePanel(hud)
ok(B.db.map.enabled ~= wasOn, "on / off from the toolbar")
ok(string.find(hud.handle.text.text or "", "(off)", 1, true) or wasOn == false, "a switched-off box says (off)")
B.U.TogglePanel(hud)
LY:Reset(hud)
ok(B.db.panels.map.scale == 1 and B.db.panels.map.alpha == 1 and not B.db.pos.map, "reset: size, opacity, place")
-- the toolbar hides once the mouse has left both
Mock.Run(hud.handle, "OnEnter")
Mock.over = nil
Mock.Tick(0.2)
Mock.Tick(0.3)
ok(not LY.bar:IsShown(), "toolbar hides when the mouse leaves")
-- the corner grip: drag right / down = bigger, saved on release
ok(hud.handle.grip, "move box has a resize grip")
B.db.panels.map.scale = 1
Mock.cx, Mock.cy = 300, 300
Mock.Run(hud.handle.grip, "OnMouseDown", "LeftButton")
Mock.cx, Mock.cy = 400, 200                    -- 100 px right, 100 px down
LY:GripTick()
local grown = B.db.panels.map.scale
Mock.Run(hud.handle.grip, "OnMouseUp", "LeftButton")
ok(grown > 1 and LY.grip == nil, "dragging the grip makes the panel bigger (" .. tostring(grown) .. ")")
Mock.cx, Mock.cy = 300, 300
Mock.Run(hud.handle.grip, "OnMouseDown", "LeftButton")
Mock.cx, Mock.cy = 100, 500                    -- back up and left: smaller, never under 50 %
LY:GripTick()
Mock.Run(hud.handle.grip, "OnMouseUp", "LeftButton")
ok(B.db.panels.map.scale >= 0.5 and B.db.panels.map.scale < grown, "and smaller again (" .. B.db.panels.map.scale .. ")")
B.db.panels.map.scale = 1
-- Warsong Gulch tunnels (measured on the world map image)
local zoneWas = B.zone
B.zone = "WSG"
local tun = B.Map.WSG.tunnels.Horde
local mx, my = (tun[1] + tun[3]) / 2, (tun[2] + tun[4]) / 2
ok(B.Map:DescribeWSG(mx, my) == "Horde tunnel", "middle of the Horde tunnel (" .. tostring(B.Map:DescribeWSG(mx, my)) .. ")")
ok(B.Map:DescribeWSG(mx, my, B.Map.WSG.Horde.flag[3] + 7) == "Horde base - upper hallway", "the hallway above it")
tun = B.Map.WSG.tunnels.Alliance
ok(B.Map:DescribeWSG((tun[1] + tun[3]) / 2, (tun[2] + tun[4]) / 2) == "Alliance tunnel", "Alliance tunnel")
B.zone = zoneWas
B.U.SetLocked(true)

-- ---------------------------------------------------------------- threat: moved to pfUI Octo
-- (23 Oct 2026, pfUI\modules\meters-threat.lua; its tests moved too, pfUI\tests\run.lua).
local sentBefore = table.getn(Mock.sent)
Mock.Tick(0.6)
local asked = false
for i = sentBefore + 1, table.getn(Mock.sent) do
  if Mock.sent[i][1] == "TWT_UDTSv4" then asked = true end
end
ok(not B.Threat and not asked, "OctoBG no longer asks for threat")
ok(not (B.Layout.INFO.threat), "no threat box in Move frames")
local printedBefore = table.getn(Mock.printed)
SlashCmdList["OCTOBG"]("threat")
local said = table.concat(Mock.printed, "\n", printedBefore + 1)
ok(string.find(said, "pfUI Octo", 1, true), "/obg threat points to pfUI Octo without pfUI")

-- ---------------------------------------------------------------- keep target: rogues, Hunter's Mark
local RT = B.Retarget
local function Said(match)
  for i = table.getn(Mock.printed), math.max(1, table.getn(Mock.printed) - 5), -1 do
    if string.find(Mock.printed[i], match, 1, true) then return true end
  end
  return false
end
local ROGUE = "0x00000000000000E1"
local rog = Mock.Enemy(ROGUE, "Sneaky", "ROGUE", 10, 0)
Mock.target = ROGUE
Mock.Fire("PLAYER_TARGET_CHANGED")
ok(RT.cur and RT.cur.guid == ROGUE and RT.cur.class == "ROGUE", "rogue target remembered")
-- Vanish: the target drops and the rogue leaves the object list
rog.near = false
Mock.target = nil
Mock.Fire("PLAYER_TARGET_CHANGED")
Mock.Fire("SPELL_GO_OTHER", 0, 1856, ROGUE, ROGUE)
Mock.Tick(0.2)
ok(RT.hunt and RT.hunt.guid == ROGUE and RT.hunt.kind == "Vanish", "waiting for the rogue after Vanish")
Mock.Tick(3)
ok(Mock.target == nil, "no target while he is gone")
rog.near = true
Mock.Tick(0.2)
ok(Mock.target == ROGUE, "rogue targeted again when he shows")
ok(Said("Target: Sneaky (back from Vanish)"), "says so")
Mock.Fire("PLAYER_TARGET_CHANGED")
-- Stealth, and you pick someone else meanwhile: left alone
Mock.Tick(2.5)
rog.near = false
Mock.target = nil
Mock.Fire("PLAYER_TARGET_CHANGED")
Mock.Fire("BUFF_ADDED_OTHER", ROGUE, 1, 1787)
Mock.Tick(0.2)
ok(RT.hunt and RT.hunt.kind == "Stealth", "waiting for the rogue after Stealth")
Mock.target = FOE
Mock.Fire("PLAYER_TARGET_CHANGED")
rog.near = true
Mock.Tick(0.2)
ok(Mock.target == FOE, "your own new target is kept")
ok(Said("Sneaky is back"), "tells you he is back")
-- a rogue whose stealth event never arrived: leaving the object list is enough
Mock.Tick(2.5)
Mock.target = ROGUE
Mock.Fire("PLAYER_TARGET_CHANGED")
rog.near = false
Mock.target = nil
Mock.Fire("PLAYER_TARGET_CHANGED")
Mock.Tick(0.2)
ok(RT.hunt and RT.hunt.guid == ROGUE, "rogue gone without a stealth event: still waited for")
Mock.Tick(25)
ok(not RT.hunt, "gives up after the wait")
rog.near = true
-- Escape on a rogue standing in view: nothing happens
Mock.target = ROGUE
Mock.Fire("PLAYER_TARGET_CHANGED")
Mock.target = nil
Mock.Fire("PLAYER_TARGET_CHANGED")
Mock.Tick(2)
ok(not RT.hunt and Mock.target == nil, "clearing your target yourself is left alone")
-- Feign Death still works
local HUNTER = "0x00000000000000E2"
Mock.Enemy(HUNTER, "Feigner", "HUNTER", 12, 0)
Mock.target = HUNTER
Mock.Fire("PLAYER_TARGET_CHANGED")
Mock.target = nil
Mock.Fire("PLAYER_TARGET_CHANGED")
Mock.Fire("SPELL_GO_OTHER", 0, 5384, HUNTER, HUNTER)
ok(Mock.target == HUNTER, "Feign Death: target kept")
Mock.Fire("PLAYER_TARGET_CHANGED")
Mock.Tick(2)
Mock.target = nil
Mock.Fire("PLAYER_TARGET_CHANGED")
Mock.Tick(2)
-- Hunter's Mark on a rogue while you have no target: targeted
local ROG2 = "0x00000000000000E3"
local r2 = Mock.Enemy(ROG2, "Marked", "ROGUE", 20, 0)
Mock.Fire("DEBUFF_ADDED_OTHER", HUNTER, 33, 14325)
ok(not RT.marked[HUNTER], "Hunter's Mark on a hunter is ignored")
Mock.Fire("DEBUFF_ADDED_OTHER", ROG2, 33, 14325)
ok(RT.marked[ROG2] and Mock.target == ROG2, "rogue with Hunter's Mark targeted")
Mock.Fire("PLAYER_TARGET_CHANGED")
-- he stealths away and comes back marked: focus this time
B.db.retarget.rogueDo = "focus"
Mock.target = nil
Mock.Fire("PLAYER_TARGET_CHANGED")
r2.near = false
Mock.Tick(0.3)
ok(RT.marked[ROG2] and RT.marked[ROG2].gone, "marked rogue out of sight")
Mock.Fire("DEBUFF_REMOVED_OTHER", ROG2, 33, 14325)
ok(RT.marked[ROG2], "mark kept while he is out of sight")
Mock.Tick(2.5)
r2.auras = { [33] = 14325 }
r2.near = true
Mock.Tick(0.3)
ok(B.Focus:Get() == ROG2, "marked rogue back: made your focus")
ok(Mock.target == nil, "focus only: your target untouched")
-- stealthed but still in view (the marking hunter sees him): picked up again
Mock.Tick(2.5)
B.db.retarget.rogueDo = "target"
Mock.Fire("BUFF_ADDED_OTHER", ROG2, 1, 1787)
Mock.Tick(0.3)
Mock.Tick(0.5)
ok(Mock.target == ROG2, "marked rogue stealthing in your sight: targeted")
Mock.Fire("PLAYER_TARGET_CHANGED")
-- back without the mark: forgotten
Mock.Tick(2.5)
Mock.target = nil
Mock.Fire("PLAYER_TARGET_CHANGED")
Mock.Tick(2)
r2.near = false
Mock.Tick(0.3)
r2.auras = {}
r2.near = true
Mock.Tick(0.3)
ok(not RT.marked[ROG2] and Mock.target == nil, "mark gone: no longer grabbed")
-- a rogue walking into view already marked
Mock.Tick(2)
local ROG3 = "0x00000000000000E4"
Mock.Enemy(ROG3, "Walkin", "ROGUE", 25, 0, { auras = { [34] = 1130 } })
B.Tracker:Consider(ROG3)
ok(RT.marked[ROG3] and Mock.target == ROG3, "rogue coming into view with Hunter's Mark")
Mock.Fire("UNIT_DIED", ROG3)
ok(not RT.marked[ROG3], "mark forgotten on death")
B.db.retarget.mark = false
Mock.Fire("DEBUFF_ADDED_OTHER", ROGUE, 33, 1130)
ok(not RT.marked[ROGUE], "Hunter's Mark switch off")

-- combat text lives in pfUI Octo: OctoBG's alerts go there
do
  local forwarded
  pfUI = { sct = { On = function() return true end,
                   CT = { Notify = function(self, key, text) forwarded = key .. ":" .. tostring(text) end } } }
  B.SCT:Notify("obgCd", "Blind ready")
  ok(forwarded == "obgCd:Blind ready", "OctoBG's alerts go to pfUI's combat text")
  forwarded = nil
  pfUI.sct.On = function() return false end
  B.SCT:Notify("obgCd", "Blind ready")
  ok(forwarded == nil, "pfUI's combat text off: no alert text")
  pfUI = nil
end

Mock.Fire("PLAYER_LEAVING_WORLD")
Mock.Fire("PLAYER_LOGOUT")

for err in pairs(B.errors) do
  fails = fails + 1
  print("ERROR caught by OctoBG: " .. err)
end
if os.getenv("OBG_DUMP") then for _, l in ipairs(Mock.printed) do print("  chat: " .. l) end end
print(checks .. " checks, " .. fails .. " failed")
if fails > 0 then os.exit(1) end
