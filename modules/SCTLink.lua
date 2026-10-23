-- OctoBG :: link to pfUI Octo's combat text
-- Combat text moved out of OctoBG into pfUI Octo on 19 Oct 2026 (the user:
-- "the menu should be in PFUI totally moved over out of OBG"): the engine,
-- message types and options are pfUI\modules\sct*.lua now, settings copied
-- once from OctoBGDB.sct (left in the saved file for that). What OctoBG still
-- needs is here, as B.SCT so the callers did not change:
--   B.SCT:Notify(key, text, r, g, b)  OctoBG's alerts (enemy cooldowns, Kill
--                                     On Sight, stealth) as pfUI combat text
--   B.SCT.PlaySound(key), .SOUNDS     sounds (pfUI's list when pfUI runs)
--   /sct, /obg sct                    open pfUI's Combat Text options
-- Threat moved the same way on 23 Oct 2026 (pfUI\modules\meters-threat.lua,
-- settings copied once from OctoBGDB.threat): /obg threat opens its page.

local B = OctoBG
local CT = {}
B.SCT = CT

local function PfUI()
  return pfUI and pfUI.sct and pfUI.sct.CT
end

function CT:Notify(key, text, r, g, b)
  local P = PfUI()
  if P and pfUI.sct:On() then return P:Notify(key, text, r, g, b) end
end

function CT:Clear()
  local P = PfUI()
  if P then P:Clear() end
end

-- ---------------------------------------------------------------- sounds

-- pfUI's full list (game sounds, BigWigs' clips, Spy's, your own) when it
-- runs; the game's alert sounds otherwise
local GAME = {
  { key = "none", label = "No sound" },
  { key = "RaidWarning", label = "Raid warning" }, { key = "TellMessage", label = "Whisper" },
  { key = "igQuestListComplete", label = "Quest complete" },
  { key = "pvpwarn", label = "PvP warning", file = "Sound\\Spells\\PVPWarning.wav" },
  { key = "gong", label = "Troll gong", file = "Sound\\Doodad\\G_GongTroll01.wav" },
}
CT.SOUNDS = GAME
CT.OUTLINES = { { key = "", label = "None" }, { key = "OUTLINE", label = "Outline" }, { key = "THICKOUTLINE", label = "Thick outline" } }

function CT.PlaySound(key)
  local P = PfUI()
  if P and P.PlaySound then return P.PlaySound(key) end
  if not key or key == "none" then return end
  for i = 1, table.getn(GAME) do
    local s = GAME[i]
    if s.key == key then
      if s.file then PlaySoundFile(s.file) else PlaySound(key) end
      return
    end
  end
  PlaySound(key)
end

B:On("OBG_INIT", function()
  local P = PfUI()
  if P and P.SOUNDS then CT.SOUNDS = P.SOUNDS end
end)

-- ---------------------------------------------------------------- commands

local function OpenPfUI()
  local O = pfUI and pfUI.octoui and pfUI.octoui.Options
  if O and O.Open and O.frame then
    O:Open("ctgeneral")
  elseif pfUI and pfUI.gui and pfUI.gui.frames and pfUI.gui.frames["Combat Text"] then
    pfUI.gui:Show()
    pfUI.gui.frames["Combat Text"]:Click()
  else
    B:Print("combat text lives in pfUI Octo now: /pfui - Combat Text (/pfui sct test)")
  end
end

B:Command("sct", "combat text - moved to pfUI Octo (/pfui, Combat Text)", function(rest)
  rest = string.lower(rest or "")
  if rest ~= "" and SlashCmdList.PFUI then
    SlashCmdList.PFUI("sct " .. rest)
  else
    OpenPfUI()
  end
end)

-- threat label, cap and popups live in pfUI Octo's meters now
B:Command("threat", "threat - moved to pfUI Octo (/pfthreat, Meters - Threat)", function(rest)
  rest = rest or ""
  local O = pfUI and pfUI.octoui and pfUI.octoui.Options
  if rest ~= "" and SlashCmdList.PFTHREAT then
    SlashCmdList.PFTHREAT(rest)
  elseif O and O.Open and O.frame then
    O:Open("mtthreat")
  else
    B:Print("threat lives in pfUI Octo now: /pfthreat, or /pfui - Meters - Threat")
  end
end)

B:On("OBG_INIT", function()
  if not (IsAddOnLoaded and (IsAddOnLoaded("sct") or IsAddOnLoaded("SCT"))) then
    SLASH_OCTOBGSCT1 = "/sct"
    SlashCmdList["OCTOBGSCT"] = function(msg) B.commands.sct.fn(msg) end
  end
end)
