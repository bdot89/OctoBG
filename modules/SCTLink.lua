-- OctoBG :: link to pfUI Octo's combat text
-- Combat text moved out of OctoBG into pfUI Octo on 19 Oct 2026 (the user:
-- "the menu should be in PFUI totally moved over out of OBG"): the engine,
-- message types and options are pfUI\modules\sct*.lua now, settings copied
-- once from OctoBGDB.sct (left in the saved file for that). What OctoBG still
-- needs is here, as B.SCT so the callers did not change:
--   B.SCT:Notify(key, text, r, g, b)  OctoBG's alerts (enemy cooldowns, Kill
--                                     On Sight, stealth) as pfUI combat text
--   B.SCT:Plate(guid)                 a unit's nameplate (the threat label)
--   B.SCT.PlaySound(key), .SOUNDS     sounds (pfUI's list when pfUI runs)
--   /sct, /obg sct                    open pfUI's Combat Text options

local B = OctoBG
local CT = { plateOf = {}, plateScanAt = 0 }
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

-- ---------------------------------------------------------------- nameplates

-- GUID -> nameplate: ClassicAPI's lookup, else the plates' nampower GUIDs
-- (frame:GetName(1)), rebuilt at most every 0.25 s
function CT:PlateGuid(f)
  local ok, g = pcall(f.GetName, f, 1)
  if ok and type(g) == "string" and string.sub(g, 1, 2) == "0x" then return g end
  return nil
end

function CT:Plate(guid)
  if not guid then return nil end
  if C_NamePlate and C_NamePlate.GetNamePlateForGUID then
    local ok, p = pcall(C_NamePlate.GetNamePlateForGUID, guid)
    if ok and p and p.IsVisible and p:IsVisible() then return p end
  end
  local p = self.plateOf[guid]
  if p and p:IsVisible() and self:PlateGuid(p) == guid then return p end
  local now = GetTime()
  if now - self.plateScanAt < 0.25 then return nil end
  self.plateScanAt = now
  local map = {}
  local kids = { WorldFrame:GetChildren() }
  for i = 1, table.getn(kids) do
    local k = kids[i]
    if k:IsVisible() then
      local g = self:PlateGuid(k)
      if g then map[g] = k end
    end
  end
  self.plateOf = map
  return map[guid]
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

B:On("OBG_INIT", function()
  if not (IsAddOnLoaded and (IsAddOnLoaded("sct") or IsAddOnLoaded("SCT"))) then
    SLASH_OCTOBGSCT1 = "/sct"
    SlashCmdList["OCTOBGSCT"] = function(msg) B.commands.sct.fn(msg) end
  end
end)
