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
ok(table.getn(files) == 32, "32 files in the toc (got " .. table.getn(files) .. ")")
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
ok(table.getn(mp.cards) == 3, "enemy map page has three cards")
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
Mock.Fire("CHAT_MSG_BG_SYSTEM_ALLIANCE", "The Horde flag was picked up by Bueno!")
ok(B.Flags:Enemy() and B.Flags:Enemy().name == "Rogueone", "EFC = the one carrying our flag (" .. tostring(B.Flags:Enemy() and B.Flags:Enemy().name) .. ")")
ok(B.Flags:Friend() and B.Flags:Friend().name == "Bueno" and not B.Flags:Friend().enemy, "our carrier is not the EFC")
-- the side turning mid-game re-judges the carriers
for i = 1, table.getn(Mock.scores) do
  if Mock.scores[i][1] == "Tester" then Mock.scores[i][2] = 0 end
end
Mock.Fire("UPDATE_BATTLEFIELD_SCORE")
ok(B.Flags:Enemy() and B.Flags:Enemy().name == "Bueno" and B.Flags:Enemy().enemy, "side back to Horde: carriers judged again")
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
ok(fo.lvl.bars[1].bg.point[1] == "BOTTOM" and fo.lvl.bars[1].bg.point[2] == fo.tri, "higher: bars above the marker")
B.TacMap:SetLevel(fo.lvl, -1)
ok(fo.lvl.bars[1].bg.point[1] == "TOP" and not fo.lvl.bars[2].bg:IsShown(), "lower: one bar below the marker")
B.TacMap:SetLevel(fo.lvl, 0)
ok(not fo.lvl.bars[1].bg:IsShown(), "level with you: nothing")
B.db.map.height = "off"
ok(B.TacMap:FloorOf(0, 0, 400) == nil, "height bars off")
B.db.map.height = "on"

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
  B.db.map.bases = false
  TMap:DrawBases()
  ok(not mark.badge:IsShown() and not mark.ring:IsShown(), "base circles can be switched off")
  B.db.map.bases = true
  TMap.hover = nil
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
