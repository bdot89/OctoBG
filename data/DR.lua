-- OctoBG :: cooldown data - diminishing returns
-- From EnemyCooldowns 2.0 by Nivhalla (merged into OctoBG), renamed into OctoBG.CDData.

local D = OctoBG.CDData

-- Data/DR.lua
-- Diminishing returns categories and the spells that feed them.
--
-- Vanilla DR rules: each application within the window halves the next one
-- (100% -> 50% -> 25% -> immune). The window is 15 seconds measured from the
-- moment the effect ends. We only ever see the CAST, so the effect end is
-- estimated from the base duration scaled by the current DR level.

D.DR_WINDOW = 15

-- Display order, label and colour for each category.
D.DR_CATEGORIES = {
    { key = "stun",    label = "Stun",    r = 0.95, g = 0.85, b = 0.25 },
    { key = "fear",    label = "Fear",    r = 0.70, g = 0.45, b = 0.90 },
    { key = "root",    label = "Root",    r = 0.35, g = 0.75, b = 0.95 },
    { key = "incap",   label = "Incap",   r = 0.95, g = 0.55, b = 0.25 },
    { key = "silence", label = "Silence", r = 0.80, g = 0.80, b = 0.80 },
    { key = "sleep",   label = "Sleep",   r = 0.55, g = 0.55, b = 0.95 },
    { key = "charm",   label = "Charm",   r = 0.95, g = 0.35, b = 0.65 },
}

-- Multiplier applied to the base duration at each DR level.
-- Index = number of applications already made inside the window.
D.DR_MULTIPLIERS = { 1.0, 0.5, 0.25, 0 }

-- spellID -> { cat = <category key>, duration = <base full duration in seconds> }
D.DR_SPELLS = {
    -- ---------- STUN ----------
    [1833]  = { cat = "stun", duration = 4 },   -- Cheap Shot
    [408]   = { cat = "stun", duration = 2 },   -- Kidney Shot (R1)
    [8643]  = { cat = "stun", duration = 3 },   -- Kidney Shot (R2)
    [853]   = { cat = "stun", duration = 3 },   -- Hammer of Justice (R1)
    [5588]  = { cat = "stun", duration = 4 },   -- Hammer of Justice (R2)
    [5589]  = { cat = "stun", duration = 5 },   -- Hammer of Justice (R3)
    [10308] = { cat = "stun", duration = 6 },   -- Hammer of Justice (R4)
    [12809] = { cat = "stun", duration = 5 },   -- Concussion Blow
    [20253] = { cat = "stun", duration = 3 },   -- Intercept Stun (R1)
    [20614] = { cat = "stun", duration = 3 },   -- Intercept Stun (R2)
    [20615] = { cat = "stun", duration = 3 },   -- Intercept Stun (R3)
    [7922]  = { cat = "stun", duration = 1 },   -- Charge Stun
    [5211]  = { cat = "stun", duration = 2 },   -- Bash (R1)
    [6798]  = { cat = "stun", duration = 3 },   -- Bash (R2)
    [8983]  = { cat = "stun", duration = 4 },   -- Bash (R3)
    [9005]  = { cat = "stun", duration = 2 },   -- Pounce (R1)
    [9823]  = { cat = "stun", duration = 3 },   -- Pounce (R2)
    [9827]  = { cat = "stun", duration = 4 },   -- Pounce (R3)
    [20549] = { cat = "stun", duration = 2 },   -- War Stomp
    [12355] = { cat = "stun", duration = 2 },   -- Impact
    [15283] = { cat = "stun", duration = 5 },   -- Stunning Blow (weapon proc)
    [19410] = { cat = "stun", duration = 3 },   -- Improved Concussive Shot

    -- ---------- FEAR ----------
    [5782]  = { cat = "fear", duration = 10 },  -- Fear (R1)
    [6213]  = { cat = "fear", duration = 15 },  -- Fear (R2)
    [6215]  = { cat = "fear", duration = 20 },  -- Fear (R3)
    [5484]  = { cat = "fear", duration = 15 },  -- Howl of Terror (R1)
    [17928] = { cat = "fear", duration = 15 },  -- Howl of Terror (R2)
    [8122]  = { cat = "fear", duration = 8 },   -- Psychic Scream (R1)
    [8124]  = { cat = "fear", duration = 8 },   -- Psychic Scream (R2)
    [10888] = { cat = "fear", duration = 8 },   -- Psychic Scream (R3)
    [10890] = { cat = "fear", duration = 8 },   -- Psychic Scream (R4)
    [5246]  = { cat = "fear", duration = 8 },   -- Intimidating Shout
    [1513]  = { cat = "fear", duration = 20 },  -- Scare Beast (R1)
    [14326] = { cat = "fear", duration = 20 },  -- Scare Beast (R2)
    [14327] = { cat = "fear", duration = 20 },  -- Scare Beast (R3)
    [6358]  = { cat = "fear", duration = 15 },  -- Seduction

    -- ---------- ROOT ----------
    [122]   = { cat = "root", duration = 8 },   -- Frost Nova (R1)
    [865]   = { cat = "root", duration = 8 },   -- Frost Nova (R2)
    [6131]  = { cat = "root", duration = 8 },   -- Frost Nova (R3)
    [10230] = { cat = "root", duration = 8 },   -- Frost Nova (R4)
    [339]   = { cat = "root", duration = 12 },  -- Entangling Roots (R1)
    [1062]  = { cat = "root", duration = 15 },  -- Entangling Roots (R2)
    [5195]  = { cat = "root", duration = 18 },  -- Entangling Roots (R3)
    [5196]  = { cat = "root", duration = 21 },  -- Entangling Roots (R4)
    [9852]  = { cat = "root", duration = 24 },  -- Entangling Roots (R5)
    [9853]  = { cat = "root", duration = 27 },  -- Entangling Roots (R6)
    [19306] = { cat = "root", duration = 5 },   -- Counterattack
    [23694] = { cat = "root", duration = 5 },   -- Improved Hamstring

    -- ---------- INCAPACITATE ----------
    [118]   = { cat = "incap", duration = 20 }, -- Polymorph (R1)
    [12824] = { cat = "incap", duration = 30 }, -- Polymorph (R2)
    [12825] = { cat = "incap", duration = 40 }, -- Polymorph (R3)
    [12826] = { cat = "incap", duration = 50 }, -- Polymorph (R4)
    [1776]  = { cat = "incap", duration = 4 },  -- Gouge (R1)
    [1777]  = { cat = "incap", duration = 4 },  -- Gouge (R2)
    [8629]  = { cat = "incap", duration = 4 },  -- Gouge (R3)
    [11285] = { cat = "incap", duration = 4 },  -- Gouge (R4)
    [11286] = { cat = "incap", duration = 4 },  -- Gouge (R5)
    [2094]  = { cat = "incap", duration = 10 }, -- Blind
    [3355]  = { cat = "incap", duration = 10 }, -- Freezing Trap (R1)
    [14308] = { cat = "incap", duration = 15 }, -- Freezing Trap (R2)
    [14309] = { cat = "incap", duration = 20 }, -- Freezing Trap (R3)
    [6770]  = { cat = "incap", duration = 25 }, -- Sap (R1)
    [2070]  = { cat = "incap", duration = 35 }, -- Sap (R2)
    [11297] = { cat = "incap", duration = 45 }, -- Sap (R3)
    [20066] = { cat = "incap", duration = 6 },  -- Repentance
    [19503] = { cat = "incap", duration = 4 },  -- Scatter Shot

    -- ---------- SILENCE ----------
    [15487] = { cat = "silence", duration = 5 },  -- Silence
    [18469] = { cat = "silence", duration = 4 },  -- Improved Counterspell
    [19244] = { cat = "silence", duration = 3 },  -- Spell Lock (R1)
    [19647] = { cat = "silence", duration = 6 },  -- Spell Lock (R2)
    [1330]  = { cat = "silence", duration = 3 },  -- Garrote - Silence

    -- ---------- SLEEP ----------
    [2637]  = { cat = "sleep", duration = 20 }, -- Hibernate (R1)
    [18657] = { cat = "sleep", duration = 30 }, -- Hibernate (R2)
    [18658] = { cat = "sleep", duration = 40 }, -- Hibernate (R3)
    [700]   = { cat = "sleep", duration = 20 }, -- Sleep
    [19386] = { cat = "sleep", duration = 12 }, -- Wyvern Sting (R1)
    [24132] = { cat = "sleep", duration = 12 }, -- Wyvern Sting (R2)
    [24133] = { cat = "sleep", duration = 12 }, -- Wyvern Sting (R3)

    -- ---------- CHARM ----------
    [605]   = { cat = "charm", duration = 15 }, -- Mind Control (R1)
    [10911] = { cat = "charm", duration = 15 }, -- Mind Control (R2)
    [10912] = { cat = "charm", duration = 15 }, -- Mind Control (R3)
}
