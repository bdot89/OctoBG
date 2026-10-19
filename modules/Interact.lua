-- OctoBG :: interact key
-- One key that right-clicks the nearest NPC or object within 5 yards: return
-- your team's dropped flag (or pick up theirs) the moment you reach it, click
-- an Arathi Basin / Alterac Valley banner, talk to an NPC, open a chest or a
-- door, loot a corpse - no aiming with the mouse.
--
-- The game cannot do this from an addon, and neither can the DLLs installed
-- here (checked 17 Oct 2026: WoW.exe and its key bindings, SuperWoW, nampower,
-- ClassicAPI's API.md - it only loots corpses and finds objects -, UnitXP_SP3's
-- command list in its source). WeirdUtils' interact.dll (codeberg.org/
-- MarcelineVQ/WeirdUtils, public domain, build 5875) adds InteractNearest(1)
-- for exactly this, so the key calls that and, without it, says what to install.

local B = OctoBG
local IN = {}
B.Interact = IN

IN.URL = "codeberg.org/MarcelineVQ/WeirdUtils"

function IN:Available()
  return type(InteractNearest) == "function"
end

function IN:Use()
  if not self:Available() then
    UIErrorsFrame:AddMessage("Interact key: install WeirdUtils' interact.dll first (OctoBG options - Interact key)", 1, 0.4, 0.2)
    return false
  end
  local ok, err = pcall(InteractNearest, 1)
  if not ok then B:Error(err) end
  return ok
end

-- Key binding (Bindings.xml)
function OctoBG_Interact() IN:Use() end

B:Command("interact", "right-click the nearest NPC or object (needs WeirdUtils' interact.dll)", function() IN:Use() end)
