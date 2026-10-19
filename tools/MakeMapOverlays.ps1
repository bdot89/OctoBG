param([string]$Overlay, [string]$Area, [string]$Out)
# Builds OctoBG's data\MapOverlays.lua from the client's WorldMapOverlay.dbc and
# WorldMapArea.dbc (newest copies, patch-4.mpq): every explored-area picture of
# every zone, so the enemy map can draw the whole zone uncovered.
function Load([string]$p) {
  $b = [IO.File]::ReadAllBytes($p)
  $o = @{ b = $b; n = [BitConverter]::ToUInt32($b, 4); f = [BitConverter]::ToUInt32($b, 8);
          rs = [BitConverter]::ToUInt32($b, 12) }
  $o.sb = 20 + $o.n * $o.rs
  return $o
}
function U($d, [int]$r, [int]$i) { return [BitConverter]::ToUInt32($d.b, 20 + $r * $d.rs + $i * 4) }
function S($d, [int]$off) {
  $s = $d.sb + $off; $e = $s
  while ($d.b[$e] -ne 0) { $e++ }
  return [Text.Encoding]::ASCII.GetString($d.b, $s, $e - $s)
}
$wma = Load $Area
$files = @{}
for ($r = 0; $r -lt $wma.n; $r++) { $files[[int](U $wma $r 0)] = S $wma (U $wma $r 3) }
$ov = Load $Overlay
$byZone = [ordered]@{}
$count = 0
for ($r = 0; $r -lt $ov.n; $r++) {
  $zone = $files[[int](U $ov $r 1)]
  $name = S $ov (U $ov $r 8)
  $w = U $ov $r 9; $h = U $ov $r 10; $x = U $ov $r 11; $y = U $ov $r 12
  if (-not $zone -or $name -eq "" -or $w -eq 0 -or $h -eq 0) { continue }
  if (-not $byZone.Contains($zone)) { $byZone[$zone] = New-Object System.Collections.ArrayList }
  [void]$byZone[$zone].Add("`"$name`", $w, $h, $x, $y")
  $count++
}
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("-- OctoBG :: every explored-area picture of every zone map")
[void]$sb.AppendLine("-- Generated from the client's DBFilesClient\WorldMapOverlay.dbc and WorldMapArea.dbc")
[void]$sb.AppendLine("-- (patch-4.mpq, the newest copies) - not edited by hand. The game draws an overlay only")
[void]$sb.AppendLine("-- for areas you have explored; the enemy map draws them all, so every zone is uncovered.")
[void]$sb.AppendLine("-- Per map file (GetMapInfo): name, width, height, x, y repeated; the textures are")
[void]$sb.AppendLine("-- Interface\WorldMap\<file>\<name><n>, cut into 256 px tiles as WorldMapFrame.lua does.")
[void]$sb.AppendLine("-- $count overlays in $($byZone.Count) zones.")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("OctoBG.MapOverlays = {")
foreach ($z in $byZone.Keys) {
  [void]$sb.AppendLine("  [`"$z`"] = {")
  foreach ($e in $byZone[$z]) { [void]$sb.AppendLine("    $e,") }
  [void]$sb.AppendLine("  },")
}
[void]$sb.AppendLine("}")
[IO.File]::WriteAllText($Out, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))
"$count overlays in $($byZone.Count) zones -> $Out"
