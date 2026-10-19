-- OctoBG :: Spy data
-- Tables that came with the Spy addon (me0wg4ming's Nampower edition, 4.5.0),
-- now part of OctoBG: the Kill On Sight reasons offered in the right-click
-- menu, the sanctuary sub-zones Spy can be switched off in, and the races a
-- race warning can pick. The reasons are Spy's text, so imported ones keep
-- matching; races and classes this client does not have (Blood Elves,
-- Draenei, Death Knights) gave way to High Elves and Goblins.

local B = OctoBG
local D = {}
B.SpyData = D

-- The reason that opens a text box (Spy stores the typed text under this key).
D.OTHER = "Enter your own reason..."

D.KOS_REASONS = {
  { title = "Started combat", content = {
    "Ambushed me", "Always attacks me on sight", "Attacked me for no reason",
    "Attacked me while fighting mobs", "Attacked me while entering/leaving instances",
    "Attacked me while I was AFK", "Attacked me while I was mounted/flying",
    "Attacked me while I had low health/mana", "Steamrolled me with a group of enemies",
    "Doesn't attack without backup", "Dared to challenge me" } },
  { title = "Style of combat", content = {
    "Always calls for help", "Pushed me off a cliff", "Uses engineering tricks",
    "Uses too much crowd control", "Spams one ability all the time", "Forced me to take durability damage",
    "Killed me and escaped from my friends", "Ran away then ambushed me", "Always manages to escape",
    "Bubble hearths to escape", "Manages to stay in melee range", "Manages to stay at kiting range",
    "Absorbs too much damage", "Heals too much", "DPS's too much" } },
  { title = "General behaviour", content = {
    "Annoying", "Rudeness", "Cowardice", "Arrogance", "Overconfidence", "Untrustworthy",
    "Emotes too much", "Stalked me/friends", "Pretends to be good", "Emotes 'not going to happen'",
    "Waves goodbye at low health", "Tried to placate me with a wave", "Performed foul acts on my corpse",
    "Laughed at me", "Spat on me" } },
  { title = "Camping", content = {
    "Camped me", "Camped an alt", "Camped lowbies", "Camped from stealth", "Camped guild members",
    "Camped game NPCs/objectives", "Called in help to camp me", "Made levelling a nightmare",
    "Forced me to logout", "Won't fight my main" } },
  { title = "Questing", content = {
    "Attacked me while questing", "Attacked me after I helped with a quest", "Interfered with quest objectives",
    "Started a quest I wanted to do", "Killed my faction's NPCs", "Killed a quest NPC" } },
  { title = "Stole resources", content = {
    "Gathered herbs I wanted", "Gathered minerals I wanted", "Gathered resources I wanted",
    "Extracted gas from a cloud I wanted", "Killed me and stole my mob", "Skinned my kills",
    "Salvaged my kills", "Fished in my pool" } },
  { title = "Battlegrounds", content = {
    "Always loots corpses", "Very good flag runner", "Backcaps flags or bases", "Stealth caps flags or bases",
    "Killed me and took the flag", "Interferes with battleground objectives", "Took a power-up I wanted",
    "Forced tank to lose agro", "Caused a wipe", "Destroys siege engines", "Drops bombs", "Disarms bombs",
    "Fear bomber" } },
  { title = "Real life", content = {
    "Friend in real life", "Enemy in real life", "Spreads rumours about me", "Complains on the forums",
    "Spy for the other faction", "Traitor to my faction", "Reneged on a deal", "Pretentious nub",
    "Another know-it-all", "Another Johnny-come-lately", "Cross faction trash talker" } },
  { title = "Difficulty", content = {
    "Impossible to kill", "Wins most of the time", "Seems like a fair match", "Loses most of the time",
    "Fun to kill", "Easy honor" } },
  { title = "Race", content = {
    "Hate the player's race", "Dwarves are short hairy doorstops", "Gnomes belong in a garden",
    "Humans are righteous busybodies", "Night Elves hug too many trees", "High Elves are narcissistic",
    "Orcs are warmongering barbarians", "Tauren should be on my burger", "Trolls should stay on web forums",
    "Undead are unnatural abominations", "Goblins only care about gold" } },
  { title = "Class", content = {
    "Hate the player's class", "Druids are dirty animals", "Hunters are easy mode",
    "Mages are deluded intellects", "Paladins are sanctimonious fools", "Priests are pious preachers",
    "Rogues have no honor", "Shamans talk to imaginary animals", "Warlocks are necromantic sadists",
    "Warriors have anger issues" } },
  { title = "Name", content = {
    "Has a ridiculous name", "Pretentious name", "Variant of Legolas", "Name has weird characters",
    "Guild name is ridiculous", "Guild name uses only capital letters", "Guild name uses capital letters and spaces",
    "Guild name states they hate my faction" } },
  { title = "Other", content = {
    "Karma", "Red is dead", "Just because", "Fails at PvP", "Flagged for PvP", "Doesn't want to PvP",
    "Wastes both our time", "This player is a noob", "I really hate this player", "Doesn't level fast enough",
    "Exploits game mechanics", "Suspected hacker", "Farmer" } },
}

-- Sanctuary sub-zones Spy offered to switch detection off in (neutral towns).
D.SANCTUARIES = { "Booty Bay", "Everlook", "Gadgetzan", "Ratchet", "Nordanaar", "Tel Co. Basecamp" }

-- Races a race warning can pick, by the enemy faction (UnitRace display names).
D.RACES = {
  Alliance = { "Human", "Dwarf", "Night Elf", "Gnome", "High Elf" },
  Horde = { "Orc", "Tauren", "Troll", "Undead", "Goblin" },
}

-- Classes Spy accepted from other Spy users (anything else is dropped).
D.CLASSES = { DRUID = 1, HUNTER = 1, MAGE = 1, PALADIN = 1, PRIEST = 1, ROGUE = 1, SHAMAN = 1, WARLOCK = 1, WARRIOR = 1 }
D.RACE_OK = { Human = 1, Orc = 1, Dwarf = 1, Tauren = 1, Troll = 1, NightElf = 1, ["Night Elf"] = 1, Scourge = 1,
              Undead = 1, Gnome = 1, HighElf = 1, ["High Elf"] = 1, Goblin = 1 }

-- Fonts the enemy list and the combat text can use: the client's own (its
-- archives hold only these four Latin ones), the ones Spy shipped, open-licence
-- fonts copied from TWThreat / EPLTowers (OFL / Apache), and pfUI's freeware
-- fonts used from pfUI's own folder. D.Fonts() lists only those that load.
local OCTO = "Interface\\AddOns\\OctoBG\\media\\fonts\\"
local PFUI = "Interface\\AddOns\\pfUI\\fonts\\"
D.FONTS = {
  { key = "Fonts\\FRIZQT__.TTF", label = "Friz Quadrata (game)" },
  { key = "Fonts\\ARIALN.TTF", label = "Arial Narrow (game)" },
  { key = "Fonts\\skurri.ttf", label = "Skurri (game)" },
  { key = "Fonts\\MORPHEUS.ttf", label = "Morpheus (game)" },
  { key = OCTO .. "Expressway.ttf", label = "Expressway" },
  { key = OCTO .. "MyriadPro-Cond.ttf", label = "Myriad Condensed" },
  { key = OCTO .. "BigNoodleTitling.ttf", label = "Big Noodle Titling" },
  { key = OCTO .. "PT-Sans-Narrow-Regular.ttf", label = "PT Sans Narrow" },
  { key = OCTO .. "PT-Sans-Narrow-Bold.ttf", label = "PT Sans Narrow Bold" },
  { key = OCTO .. "FiraSansCondensed-Regular.ttf", label = "Fira Sans Condensed" },
  { key = OCTO .. "FiraSansCondensed-SemiBold.ttf", label = "Fira Sans Condensed Bold" },
  { key = OCTO .. "Roboto.ttf", label = "Roboto" },
  { key = OCTO .. "RobotoMono.ttf", label = "Roboto Mono" },
  { key = OCTO .. "Share.ttf", label = "Share" },
  { key = OCTO .. "ShareBold.ttf", label = "Share Bold" },
  { key = OCTO .. "SquadaOne.ttf", label = "Squada One" },
  { key = OCTO .. "LondrinaSolid.ttf", label = "Londrina Solid" },
  { key = OCTO .. "BalooBhaina.ttf", label = "Baloo Bhaina" },
  { key = OCTO .. "Sniglet.ttf", label = "Sniglet" },
  { key = PFUI .. "DieDieDie.ttf", label = "Die Die Die (pfUI)" },
  { key = PFUI .. "Continuum.ttf", label = "Continuum (pfUI)" },
  { key = PFUI .. "Hooge.ttf", label = "Hooge (pfUI)" },
  { key = PFUI .. "Homespun.ttf", label = "Homespun (pfUI)" },
}
for i = 1, table.getn(D.FONTS) do D.FONTS[i].font = D.FONTS[i].key end   -- menus show each in its own face

-- Does a font file load? Tried once on a hidden font string: after a failed
-- SetFont the string keeps the font it had. Unknown (no GetFont) counts as yes.
local probe, fontOK = nil, {}
function D.FontOK(path)
  if not path or path == "" then return false end
  local known = fontOK[path]
  if known ~= nil then return known end
  if not probe then
    local f = CreateFrame("Frame", nil, UIParent)
    probe = f:CreateFontString(nil, "OVERLAY")
  end
  probe:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
  local base = probe:GetFont()
  probe:SetFont(path, 12, "")
  local now = probe:GetFont()
  local ok = true
  if type(base) == "string" then
    local function N(s) return string.lower(string.gsub(s or "", "/", "\\")) end
    ok = (type(now) == "string") and N(now) == N(path)
  end
  fontOK[path] = ok
  return ok
end

-- The fonts that load on this install (for menus).
function D.Fonts()
  local out = {}
  for i = 1, table.getn(D.FONTS) do
    if D.FontOK(D.FONTS[i].key) then table.insert(out, D.FONTS[i]) end
  end
  return out
end

-- A font to draw with: path if it loads, else the fallback (or Friz Quadrata).
function D.Font(path, fallback)
  if path and path ~= "" and D.FontOK(path) then return path end
  if fallback and fallback ~= "" and D.FontOK(fallback) then return fallback end
  return "Fonts\\FRIZQT__.TTF"
end
-- Spy's font names (LibSharedMedia keys) -> files, for importing its setting.
D.FONT_BY_NAME = {
  ["Friz Quadrata TT"] = "Fonts\\FRIZQT__.TTF",
  ["Arial Narrow"] = "Fonts\\ARIALN.TTF",
  ["Skurri"] = "Fonts\\skurri.ttf",
  ["Morpheus"] = "Fonts\\MORPHEUS.ttf",
  ["Express Way"] = "Interface\\AddOns\\OctoBG\\media\\fonts\\Expressway.ttf",
  ["Myriad Cond"] = "Interface\\AddOns\\OctoBG\\media\\fonts\\MyriadPro-Cond.ttf",
  ["Big Noodle Titling"] = "Interface\\AddOns\\OctoBG\\media\\fonts\\BigNoodleTitling.ttf",
}

-- Health bar textures.
D.BARS = {
  { key = "flat", label = "Flat", file = "Interface\\ChatFrame\\ChatFrameBackground" },
  { key = "Minimalist", label = "Minimalist (Spy)", file = "Interface\\AddOns\\OctoBG\\media\\bar-minimalist" },
  { key = "blend", label = "Blend (Spy)", file = "Interface\\AddOns\\OctoBG\\media\\bar-blend" },
  { key = "game", label = "Game status bar", file = "Interface\\TargetingFrame\\UI-StatusBar" },
}
function D.BarFile(key)
  for i = 1, table.getn(D.BARS) do
    if D.BARS[i].key == key then return D.BARS[i].file end
  end
  return D.BARS[1].file
end
