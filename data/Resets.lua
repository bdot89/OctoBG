-- OctoBG :: cooldown data - resets
-- From EnemyCooldowns 2.0 by Nivhalla (merged into OctoBG), renamed into OctoBG.CDData.

local D = OctoBG.CDData

-- Data/Resets.lua
-- Spells that reset other spells' cooldowns.
--
-- NOTE: The IDs below were previously swapped. Confirmed against the addon's own
-- harvested data in Data/Spells.lua:
--     Ice Block = 11958 (300s CD)
--     Cold Snap = 12472 (600s CD)
-- The old file had a [11958] entry labelled "Cold Snap" which meant casting
-- Ice Block wiped Frost Nova / Ice Barrier / Icy Veins off the tracker.

D.SPELL_RESETS = {
    -- Cold Snap (Mage) resets all Frost cooldowns
    [12472] = {
        11958, -- Ice Block
        122,   -- Frost Nova (R1)
        865,   -- Frost Nova (R2)
        6131,  -- Frost Nova (R3)
        10230, -- Frost Nova (R4)
        11426, -- Ice Barrier (R1)
        13031, -- Ice Barrier (R2)
        13032, -- Ice Barrier (R3)
        13033, -- Ice Barrier (R4)
        6143,  -- Frost Ward (R1)
        8461,  -- Frost Ward (R2)
        8462,  -- Frost Ward (R3)
        10177, -- Frost Ward (R4)
        28609, -- Frost Ward (R5)
        120,   -- Cone of Cold (R1)
        8492,  -- Cone of Cold (R2)
        10159, -- Cone of Cold (R3)
        10160, -- Cone of Cold (R4)
        10161, -- Cone of Cold (R5)
    },

    -- Preparation (Rogue) resets these
    [14185] = {
        13877, -- Blade Flurry
        408,   -- Kidney Shot (R1)
        8643,  -- Kidney Shot (R2)
        2094,  -- Blind
        2983,  -- Sprint (R1)
        8696,  -- Sprint (R2)
        11305, -- Sprint (R3)
        5277,  -- Evasion (R1)
        26669, -- Evasion (R2)
        1776,  -- Gouge (R1)
        1777,  -- Gouge (R2)
        8629,  -- Gouge (R3)
        11285, -- Gouge (R4)
        11286, -- Gouge (R5)
        14278, -- Ghostly Strike
        14183, -- Premeditation
        1856,  -- Vanish (R1)
        1857,  -- Vanish (R2)
        14177, -- Cold Blood
    },
}
