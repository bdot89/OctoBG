-- OctoBG :: threat label options
-- The "Threat label" page (Setup). It used to sit with the combat text pages
-- (SCTOptions.lua); combat text moved to pfUI Octo on 19 Oct 2026, this page
-- stayed (the label is OctoBG's: modules/Threat.lua).

local B = OctoBG
local U = B.U
local W = B.W
local O = B.Options
local CT = B.SCT
local BUILD = O.BUILD
local Chk, Sld, Drop, Px, On = O.Chk, O.Sld, O.Drop, O.Px, O.On

local function PlaySnd(v) CT.PlaySound(v) end

local function TT() return B.db.threat end

BUILD.threat = function(p)
  local TH = B.Threat
  local function Show() TH:Sample(6) end
  W.Heading(p, "Threat", {
    on = On(TT, "enabled", Show, "Threat by your target's nameplate."),
    text = "Your threat by your target's nameplate: green, yellow near your cap, red past it - or Aggro when the mob is on you.",
    about = "The numbers come from the server, the same answers TWThreat shows - so it only works in a party or raid, "
      .. "on a mob in combat. If this server does not send them, OctoBG stops asking and says so in the status line. "
      .. "Nameplate colours by who has aggro are pfUI's (pfUI options: Nameplates - combat state colours)." })
  W.Live(p, function() return "Status: " .. TH:Status() end)
  W.Buttons(p, { { "Show a sample", Show, 120,
    "The label on your target's nameplate (or in its box) for a few seconds - target anything with a nameplate first." } })
  W.Card(p, "Your cap", { text = "How much threat you allow yourself before the label turns red." })
  W.Live(p, function() return "Now: |cffffd100" .. TH:CapText() .. "|r.  In game: |cffffd100/obg threat 70 2|r" end)
  Sld(p, "Stay under", "Your threat as a share of the player you stay behind. Yellow from 80 % of this, red past it.",
    10, 150, 5, TT, "limit", nil, function(v) return v .. "%" end)
  Drop(p, "...of", "The top: stay behind the tank. The top two: behind the tank and the next one too (raids with an "
    .. "off-tank or a big hitter).", TH.REFS, TT, "ref")
  W.Buttons(p, {
    { "Safe 70%", function() B.db.threat.limit, B.db.threat.ref = 70, 1 end, 80 },
    { "Push 90%", function() B.db.threat.limit, B.db.threat.ref = 90, 1 end, 80 },
    { "Edge 100%", function() B.db.threat.limit, B.db.threat.ref = 100, 1 end, 86,
      "Right up to the tank's threat - the mob turns at 110 % in melee, 130 % at range." },
  })
  W.Card(p, "Look and place", { text = "How the threat label looks and where it sits." })
  Drop(p, "Show it as", "Words (Threat 45%), just the number, or a bar.", TH.LOOKS, TT, "look", Show)
  Drop(p, "Where", "A box I place: drag the \"Threat\" box with Move frames at the top.", TH.PLACES, TT, "where", Show)
  Sld(p, "Move sideways", "Shift the label left (minus) or right.", -150, 150, 1, TT, "x", Show, Px)
  Sld(p, "Move up / down", "Shift the label down (minus) or up.", -100, 100, 1, TT, "y", Show, Px)
  Sld(p, "Text size", "How big the label is.", 8, 30, 1, TT, "size", Show, Px)
  Drop(p, "Outline", "A dark edge around the label's letters.", CT.OUTLINES, TT, "outline", Show)
  Chk(p, "Show the next player", "When I have aggro: \"Aggro  next 92%\" - for tanks.", TT, "next")
  W.Card(p, "Popups", { folded = true, text = "A big message in the middle of the screen when you go over your cap." })
  Chk(p, "Shout when I pass my cap", "A big message in the middle of the screen, once each time you cross it.", TT, "popup")
  Chk(p, "Also when I pull aggro", "\"AGGRO!\" - tanks may want this off.", TT, "popupAggro")
  Drop(p, "Sound", "Plays with the popup. Picking one plays it.", CT.SOUNDS, TT, "popupSound", PlaySnd)
  W.Edit(p, "Message", "What the popup says.", function() return B.db.threat.popupText end, function(v)
    if v and v ~= "" then B.db.threat.popupText = v end
  end, 200)
  W.Buttons(p, { { "Test the popup", function()
    U.Alert(B.db.threat.popupText, 1, 0.25, 0.2)
    CT.PlaySound(B.db.threat.popupSound)
  end, 120 } })
end


-- in the topic list under Setup, after General
for i = 1, table.getn(O.SECTIONS) do
  if O.SECTIONS[i][1] == "general" then
    table.insert(O.SECTIONS, i + 1, { "threat", "Threat label" })
    break
  end
end
