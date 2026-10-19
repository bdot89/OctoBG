# OctoBG

All-in-one PvP addon for OctoWoW (1.12 client, 1.18.1 build) with SuperWoW, nampower, UnitXP_SP3 and
ClassicAPI. Two former addons are built in: **Spy** (world PvP enemy detection, Kill On Sight,
statistics) and **EnemyCooldowns** (enemy cooldown tracker by Nivhalla). Works in Warsong Gulch,
Arathi Basin, Alterac Valley, Thorn Gorge, the arenas and the open world.

## Install

1. Download **OctoBG-<version>.zip** (under Assets) from the [latest release](https://github.com/bdot89/OctoBG/releases/latest)
   (not the green "Code" button: that zip unpacks as `OctoBG-main`, which the game ignores).
2. Unzip it into `Interface\AddOns`, so you end up with `Interface\AddOns\OctoBG\OctoBG.toc`.
   If you did use the green button, rename the `OctoBG-main` folder to `OctoBG`.
3. Start the game **with SuperWoW** (see Requirements) and type `/obg status`: it lists which game
   add-ons (DLLs) are running. Without SuperWoW the enemy map and radar can't show enemies, and
   OctoBG says so in chat when you log in.

Updating: replace the `OctoBG` folder. Your settings are kept (they live in `WTF`, not in the folder).

## Using it

`/obg` (or the minimap button) opens the options. Start with **Overview**: every feature with its
own on / off tick box. The topic list on the left folds into Battlegrounds, Spy / Enemies, World PvP,
Cooldowns and Setup; each page has the feature's ON / OFF switch at the top, a one-line summary
("How it works" on hover tells the rest) and folding cards of settings, two to a row. Hover any
setting to see what it does. The bar at the top is on every page: **Move frames** shows every panel
with sample data so you can drag them into place (drag a box's corner grip to resize it), and
**Find a setting** lists every setting that mentions a word - click one to jump to it.

## Battleground

**Enemy map** - the battleground's (or zone's) map with every enemy as a class-coloured triangle;
a running enemy's triangle turns into an arrowhead pointing the way they run. White ring: your
target. Red ring: Kill On Sight. Gold ring: an immunity. Names under the target and Kill On Sight
enemies (or all, or none). Zoom with the wheel (separate zoom for battlegrounds and the open world);
zoomed in, the view follows you and enemies outside it wait on the edge. Hover an enemy for
everything known, click to target, right-click for the enemy menu. Also you, your raid, both flag
carriers, objectives and stealth marks; under it the enemy carrier's whereabouts and the enemy count.
Zoomed in, drag the map to look somewhere else ("Back to me" returns). In Arathi Basin and the
other battlegrounds each base has a circle with a label: click it to post "3 AT STABLES", right-click
to pin it on the INC bar. In Warsong Gulch the enemy carrier gets a red ring with "EFC +n" (enemies
with them). Every zone is shown fully uncovered, and the map can stand in for the game's world map
(the M key) - Battlegrounds > Enemy map > "As your world map".

**Flag carriers (WSG)** - one row for the enemy carrier, one for ours: class colour, health, time
held, distance, a direction arrow, where they are in plain words ("Horde flag room", "Horde base -
lower level", "midfield (west)") and the cooldowns they have used (trinket, Ice Block...), plus
"Ice Block 6s" while they are immune. Left-click: target. Right-click: target and cast your flag
spell (Mind Vision for priests). Ctrl-click: post their health and location to /bg.

**Timers** - resurrection waves per graveyard, a big "Resurrection in N" while dead, Arathi Basin
bases (60 s), Alterac Valley towers and graveyards (5 min), the battle start countdown and who
reaches 2000 first in Arathi Basin.

**INC calls** - buttons that post `3 INC STABLES`, `STABLES SAFE`, `HELP STABLES`, Auto (the enemies
counted at the base). Guard alert when enemies reach the base you stand at; posting those
automatically is off and asks first.

**Team sync** - every OctoBG in the battleground shares what its own game sees, over the hidden
addon channel (nothing in chat): teammates' sightings on the map, HUD edge and enemy list (distance
in blue), the enemy carrier's health from across the map, cooldowns, stealth marks, far resurrection
timers. In a world group it starts once another OctoBG user is there. `/obg sync` lists who shares.

## Enemies (everywhere)

**Enemy list** - Spy's Nearby window and the battleground roster in one list, four modes (arrows in
the title bar, or Alt + wheel): **Nearby** (open world: every enemy detected, bright while seen,
greyed until forgotten, Kill On Sight first; battlegrounds: the whole enemy team from the
scoreboard), **Last hour**, **Ignore**, **Kill On Sight**. Rows: level, name over a health bar, a
skull for Kill On Sight (flag on the enemy carrier), the cast or up to three used cooldowns, `x2` =
how many of your group target them, line of sight and distance; damage numbers flash on the row.
Click: target. Shift-click: Kill On Sight. Ctrl-click: ignore. Alt-click: focus. Right-click: menu
(announce, Kill On Sight reasons, lists, focus). The count in the title posts "Nearby enemy players:
N". Width (drag the corner), row height, font, bar texture, opacity, grow upwards, lock, sort orders.

**World PvP** (was Spy) - every enemy player your game can see is detected (casts, attacks, buffs,
nameplates, GUID events), with a sound, and an alert box for Kill On Sight players, their guild
mates, a race you pick and stealthers. Paused in sanctuaries, chosen neutral towns, dungeons and
raids; battlegrounds and PvP-unflagged zones by choice; nothing new on taxis. Announce new enemies to
yourself / party / raid / guild / LocalDefense (asks first). Shares and receives sightings on Spy's
own channel, so friends still running Spy and you see each other's reports.

**Kill On Sight and ignore** - skull in the list, red ring on map and HUD, alert and sound when
they show up; reasons from Spy's list or your own text; one list for all your characters of a
faction (or per character).

**Statistics** - every enemy you met: level, class, guild, wins, losses, reasons, where and when you
last saw them; filter, sort, right-click menu. Wins: "You have slain X". Losses: your death, to
whoever hit you last. Old records are purged after the days you choose.

**Radar HUD** - enemies as class-coloured triangles (arrowheads while running), your raid as dots,
your target ringed in white, Kill On Sight in red, the enemy carrier with a flag, immune enemies in
gold; turns with you or north-up.

**Focus** - uses pfUI's focus so there is one focus, not two, and adds `/fcast Spell` and three key
bindings that cast on your focus without changing target (SuperWoW), and a strip under the focus
frame with their used cooldowns, diminishing returns, distance, line of sight and immunity.

**Stealth** - an alert (Spy's) when an enemy stealths nearby or walks into range stealthed, and a
mark where they disappeared with a circle for how far they could be by now.

**Interact key** - one key that right-clicks the nearest NPC or object within 5 yards: return or grab
a dropped flag the moment you reach it, click a banner, talk to an NPC. Needs WeirdUtils' interact.dll
(the options page explains the one-time install).

**Keep target** - re-targets a hunter whose Feign Death dropped your target, a rogue (or druid) the
moment they show again after Vanish or Stealth, and any rogue or druid wearing a Hunter's Mark -
as your target (only while you have none), your focus, or both.

## Enemy cooldowns (was EnemyCooldowns)

- **Cooldown bars** - your target's cooldowns (or your last target's, or the enemy flag carrier's
  when you have no target in Warsong Gulch), with immunity strips and diminishing returns.
- **Learning** - enemies' real (talented) cooldowns are learned from early recasts, per player.
- **Diminishing returns**, **nameplate icons**, **spell filter**, **alerts** and a shareable
  **profile** string (old "ECD1" profiles import too). The enemy list shows the cooldowns too.

## Combat text and threat

Scrolling combat text (SCT and SCT - Damage) moved out of OctoBG in 2.2.0: it lives in
**pfUI Octo** now, where its pages sit with the rest of pfUI's settings. `/sct` and `/obg sct` open
them when pfUI Octo is installed. OctoBG's own alerts (enemy cooldowns, Kill On Sight, stealth)
also scroll in that combat text while it is on.

The **threat label** stays in OctoBG (Setup > Threat): your threat by your target's nameplate
in a party or raid, as words, a number or a bar, with a cap you set ("stay under 70 % of the tank" -
`/obg threat 70 2`). It needs a server that sends threat data (`/obg threat` says whether it does).

## Moving over from Spy and EnemyCooldowns

Log in with the old addon still switched on. OctoBG copies its data (only reading its saved
files) and offers to switch it off; until then OctoBG keeps its own copy of that feature quiet so
nothing shows twice. Spy kept statistics per character: log each character in once with Spy still
on (switching Spy off only affects the character you are on). Kill On Sight lists of all your
characters, the ignore list, reasons, wins and losses and Spy's settings come over. Afterwards the
old folders can be deleted. `/spy` (show, hide, reset, clear, config, kos, ignore, stats, test) and
`/ecd` keep working.

Left behind on purpose: Spy's profiles (OctoBG has one set of settings, the cooldown part can be
exported), its sound channel choice (1.12 plays every addon sound on one channel), and its debug
commands (`/obg status`, `/obg debug`, `/obg errors` instead).

## Requirements

These are game add-ons (DLLs loaded with the game), not addon folders: an OctoBG zip can't bring
them. `/obg status` shows which ones the game is running.

- **SuperWoW** (needed): enemy positions on the map and HUD, GUIDs, spell names, cast events
  (cooldowns need it). The game has to be started through SuperWoW's launcher / hook.
- nampower: finding enemies, nameplate GUIDs, real health values, spell cooldown lengths
- UnitXP_SP3: distance and line of sight
- pfUI (optional): one shared focus, the addon-button arrow on the map, combat text (pfUI Octo)
- ClassicAPI (optional): player facing, spell icons, profile straight to the clipboard, tells Feign
  Death from death, and `/reload` picks up new files

## Commands

`/obg` options, `/obg map`, `/obg list`, `/obg world` (`on` / `off`), `/obg stats`, `/obg kos <name>`,
`/obg ignore <name>`, `/obg clear`, `/obg nearby`, `/obg spytest`, `/obg unlock` / `lock`, `/obg hud`,
`/obg cd` (cooldowns: `test`, `reset`, `learned`, `forget`, `alerts`, `debug`, `ids`), `/obg dim 40`,
`/obg maxview` (`off`), `/obg reach`, `/obg reset`, `/obg calib`, `/obg status`, `/obg probe`,
`/obg errors`, `/fcast <spell>`. Key bindings (game key bindings, under OctoBG) include the enemy map,
enemy list, world PvP detection, statistics, Kill On Sight / ignore your target and posting the
nearby count.

The first time you run with the HUD or map up OctoBG learns which way your facing turns; the
General page shows when it is done.

## For developers

`tools\LuaCheck.ps1 -Globals -Files <all .lua>` (Lua 5.0 parse, limits, globals) and `tests\run.ps1`
(every file run through a mock 1.12 client on DmorphOcto's LuaHost) before handing over a change.
