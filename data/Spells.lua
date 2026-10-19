-- OctoBG :: cooldown data - spells
-- From EnemyCooldowns 2.0 by Nivhalla (merged into OctoBG). Only the global
-- ECD_* tables were renamed into the OctoBG.CDData namespace; values unchanged.

OctoBG.CDData = OctoBG.CDData or {}
local D = OctoBG.CDData

-- Data/Spells.lua
-- Spell database organized by class

D.CLASS_SPELLS = {
    ["WARRIOR"] = {
        "Charge",
        "Intercept",
        "Mortal Strike",
        "Whirlwind",
        "Sweeping Strikes",
        "Overpower",
        "Revenge",
        "Bloodthirst",
        "Shield Slam",
        "Shield Bash",
        "Pummel",
        "Concussion Blow",
        "Intimidating Shout",
        "Death Wish",
        "Recklessness",
        "Shield Wall",
        "Retaliation",
        "Disarm",
        "Berserker Rage",
        "Last Stand"
    },
    ["MAGE"] = {
        "Frost Nova",
        "Cone of Cold",
        "Cold Snap",
        "Ice Block",
        "Icicles",
        "Fire Blast",
        "Blast Wave",
        "Counterspell",
        "Evocation",
        "Blink",
        "Presence of Mind",
        "Arcane Power",
        "Combustion"
    },
    ["ROGUE"] = {
        "Vanish",
        "Sprint",
        "Preparation",
        "Cold Blood",
        "Adrenaline Rush",
        "Blade Flurry",
        "Kick",
        "Gouge",
        "Blind",
        "Kidney Shot",
        "Evasion",
        "Cloak of Shadows"
    },
    ["PRIEST"] = {
        "Power Word: Shield",
        "Fade",
        "Psychic Scream",
        "Desperate Prayer",
        "Fear Ward",
        "Mana Burn",
        "Silence",
        "Inner Focus",
        "Power Infusion"
    },
    ["WARLOCK"] = {
        "Howl of Terror",
        "Death Coil",
        "Spell Lock",
        "Shadowburn",
        "Conflagrate",
        "Shadow Ward",
        "Amplify Curse",
        "Inferno",
        "Ritual of Doom"
    },
    ["PALADIN"] = {
        "Hammer of Justice",
        "Repentance",
        "Turn Undead",
        "Divine Shield",
        "Hand of Protection",
        "Divine Protection",
        "Lay on Hands",
        "Divine Favor",
        "Holy Shock",
        "Crusader Strike",
        "Holy Strike"
    },
    ["SHAMAN"] = {
        "Frost Shock",
        "Flame Shock",
        "Earth Shock",
        "Grounding Totem",
        "Fire Elemental Totem",
        "Earth Elemental Totem",
        "Nature's Swiftness",
        "Elemental Mastery",
        "Stormstrike",
        "Reincarnation",
        "Lightning Strike"
    },
    ["DRUID"] = {
        "Bash",
        "Feral Charge",
        "Enrage",
        "Frenzied Regeneration",
        "Tiger's Fury",
        "Pounce",
        "Nature's Grasp",
        "Barkskin",
        "Nature's Swiftness",
        "Swiftmend",
        "Innervate",
        "Rebirth",
        "Tranquility"
    },
    ["HUNTER"] = {
        "Freezing Trap",
        "Frost Trap",
        "Immolation Trap",
        "Explosive Trap",
        "Scatter Shot",
        "Intimidation",
        "Aimed Shot",
        "Multi-Shot",
        "Arcane Shot",
        "Concussive Shot",
        "Counterattack",
        "Rapid Fire",
        "Bestial Wrath",
        "Deterrence",
        "Feign Death",
        "Wing Clip"
    },
	["OTHERS"] = {
	}
}

D.ITEMS_SPELLS = {
	[52317] = { -- Insignia of the Horde
		["duration"] = 180,
		["texture"] = "Interface\\Icons\\INV_Jewelry_Trinketpvp_02",
		["name"] = "Insignia of the Horde/Alliance",
	},
	[6615]= { -- Free Action Potion
		["duration"] = 120,
		["texture"] = "Interface\\Icons\\INV_Potion_04",
		["name"] = "Free Action",
	},
	[3169]= { -- Invulnerability Potion
		["duration"] = 120,
		["texture"] = "Interface\\Icons\\INV_Potion_43",
		["name"] = "Invulnerability",
	},
	[835] ={ -- Tidal
		["duration"] = 900,
		["texture"] = "Interface\\Icons\\INV_Misc_Rune_01",
		["name"] = "Tidal",
	},
}

-- Populate "OTHERS" with the item names.
-- The insignia shares one spellID across factions and is resolved at runtime
-- to the faction-specific name, so both variants must be listed here or the
-- filter checkbox would never match what is actually tracked.
table.insert(D.CLASS_SPELLS["OTHERS"], "Insignia of the Horde")
table.insert(D.CLASS_SPELLS["OTHERS"], "Insignia of the Alliance")

for spellID, itemData in pairs(D.ITEMS_SPELLS) do
    if itemData.name and spellID ~= 52317 then
        table.insert(D.CLASS_SPELLS["OTHERS"], itemData.name)
    end
end

-- Blacklisted spell categories (don't track these)
D.BLACKLISTED_CATEGORIES = {
    [11] = true
}

-- Shortest cooldown a spell can have once the caster's talents are fully
-- invested. The server only ever reports the BASE cooldown -- the enemy's
-- talents are not queryable -- so this table drives the "might already be
-- ready" shading on the bar for the window between the talented minimum and
-- the base value.
--
-- These are the vanilla values. If your server retunes a talent, correct the
-- number here; nothing else needs to change. Anything not listed is assumed
-- to have no talented reduction and shows no uncertainty window.
--
-- Note this table only affects the SHADING. The addon also learns each
-- enemy's real cooldown by watching for early recasts (see CD:LearnCooldown in modules/Cooldowns.lua),
-- and a learned value always wins over the base value.
D.TALENT_MIN_CD = {
    -- Mage
    ["Frost Nova"] = 21,     -- Improved Frost Nova, 2 ranks x 2s (base 25)
    ["Fire Blast"] = 6.5,    -- Improved Fire Blast, 3 ranks x 0.5s (base 8)
    ["Blast Wave"] = 42,     -- Improved Blast Wave, 3 ranks x 1s (base 45)
    -- Priest
    ["Psychic Scream"] = 26, -- Improved Psychic Scream, 2 ranks x 2s (base 30)
    -- Warrior
    ["Intercept"] = 15,      -- Improved Intercept, 3 ranks x 5s (base 30)
    -- Rogue
    ["Blind"] = 240,         -- Elusiveness, 2 ranks x 30s (base 300)
    ["Vanish"] = 240,        -- Elusiveness, 2 ranks x 30s (base 300)
}

-- Blacklisted by NAME, so every rank and every faction variant is covered
-- with one entry. These are consumables, mounts, food/drink and world-object
-- casts: they technically report a cooldown but are noise on a PvP tracker.
D.BLACKLISTED_NAMES = {
    -- Food and drink
    ["Drink"] = true,
    ["Food"] = true,
    ["Tea"] = true,
    ["Refreshment"] = true,
    ["Restore Mana"] = true,
    ["Restore Energy"] = true,
    ["Restore Health"] = true,
    -- Travel and utility
    ["Hearthstone"] = true,
    ["Traveler's Tent"] = true,
    ["MOLL-E Terminal"] = true,
    ["Goblin Brainwashing Device"] = true,
    ["Auctioneer"] = true,
    ["Ritual of Doom"] = true,
    ["Ritual of Souls"] = true,
    ["Ritual of Summoning"] = true,
    -- Profession / misc casts
    ["First Aid"] = true,
    ["Cooking"] = true,
    ["Fishing"] = true,
    ["Opening"] = true,
    ["Disenchanting"] = true,
    ["Pick Lock"] = true,
}

-- Blacklisted individual spells
D.BLACKLISTED_SPELLS = {
    [3714] = true,
	[46001] = true, -- MOLL-E Terminal
	[46002] = true, -- Goblin Brainwashing Device
	[46472] = true, -- Auctioneer,
	[51060]= true, -- Uncontained Magic
}

D.CLASS_ICONS = {
    ["DRUID"] = "Interface\\Icons\\INV_Misc_MonsterClaw_04",
    ["HUNTER"] = "Interface\\Icons\\INV_Weapon_Bow_07",
    ["MAGE"] = "Interface\\Icons\\INV_Staff_13",
    ["PALADIN"] = "Interface\\Icons\\INV_Hammer_01",
    ["PRIEST"] = "Interface\\Icons\\INV_Staff_30",
    ["ROGUE"] = "Interface\\Icons\\INV_ThrowingKnife_04",
    ["SHAMAN"] = "Interface\\Icons\\INV_Jewelry_Talisman_04",
    ["WARLOCK"] = "Interface\\Icons\\Spell_Nature_Drowsy",
    ["WARRIOR"] = "Interface\\Icons\\INV_Sword_27",
	["OTHERS"] = "Interface\\Icons\\INV_Misc_QuestionMark",
}
 
D.IMMUNITY_SPELLS = {
	-- Potions
	[6615]= 30, -- Free Action Potion
	[3169]=6, -- Invulnerability Potion
	-- Spells
    [11958]= 10, -- Ice Block (Rank 1)
    [27619]= 10, -- Ice Block (Rank 2)
    [642] = 10,    -- Divine Shield (Rank 1)
    [1020] = 12,  -- Divine Shield (Rank 2)
    [1022]= 6, -- Hand of Protection (Rank 1)
    [5599]= 8, -- Hand of Protection (Rank 2)
    [10278]= 10, -- Hand of Protection (Rank 3)
    [498]= 6, -- Divine Protection (Rank 1)
    [5573]= 7, -- Divine Protection (Rank 2)
	[1044]= 10,  -- Hand of Freedom
}

-- Spells worth an audible / visual alert when an enemy uses them.
-- Keyed by spell NAME so every rank is covered by one entry.
D.ALERT_SPELLS = {
    -- Immunities & hard defensives
    ["Ice Block"] = true,
    ["Divine Shield"] = true,
    ["Hand of Protection"] = true,
    ["Divine Protection"] = true,
    ["Shield Wall"] = true,
    ["Evasion"] = true,
    ["Deterrence"] = true,
    ["Cloak of Shadows"] = true,
    ["Invulnerability"] = true,
    ["Free Action"] = true,
    -- Escapes / resets
    ["Vanish"] = true,
    ["Preparation"] = true,
    ["Cold Snap"] = true,
    ["Blink"] = true,
    ["Feign Death"] = true,
    ["Hand of Freedom"] = true,
    ["Will of the Forsaken"] = true,
    ["Escape Artist"] = true,
    ["Stoneform"] = true,
    ["Perception"] = true,
    -- Big offensive cooldowns
    ["Recklessness"] = true,
    ["Death Wish"] = true,
    ["Retaliation"] = true,
    ["Adrenaline Rush"] = true,
    ["Cold Blood"] = true,
    ["Arcane Power"] = true,
    ["Combustion"] = true,
    ["Presence of Mind"] = true,
    ["Power Infusion"] = true,
    ["Inner Focus"] = true,
    ["Nature's Swiftness"] = true,
    ["Elemental Mastery"] = true,
    ["Bestial Wrath"] = true,
    ["Rapid Fire"] = true,
    ["Divine Favor"] = true,
    ["Lay on Hands"] = true,
    ["Last Stand"] = true,
    ["Barkskin"] = true,
    ["Tiger's Fury"] = true,
    ["Amplify Curse"] = true,
    ["Insignia of the Horde"] = true,
    ["Insignia of the Alliance"] = true,
}



D.SPELLS = {
	["Dark Harvest"] = {
		["duration"] = 30,
		["texture"] = "Interface\\Icons\\Spell_Shadow_SoulLeech",
		["spellID"] = 52552,
	},
	["Swiftmend"] = {
		["duration"] = 15,
		["spellID"] = 18562,
		["texture"] = "Interface\\Icons\\INV_Relics_IdolofRejuvenation",
	},
	["Bloodrage"] = {
		["duration"] = 60,
		["spellID"] = 2687,
		["texture"] = "Interface\\Icons\\Ability_Racial_BloodRage",
	},
	["Sweeping Strikes"] = {
		["duration"] = 30,
		["spellID"] = 12292,
		["texture"] = "Interface\\Icons\\Ability_Rogue_SliceDice",
	},
	["Berserker Rage"] = {
		["duration"] = 30,
		["spellID"] = 18499,
		["texture"] = "Interface\\Icons\\Spell_Nature_AncestralGuardian",
	},
	["Hammer of Justice"] = {
		["duration"] = 60,
		["spellID"] = 10308,
		["texture"] = "Interface\\Icons\\Spell_Holy_SealOfMight",
	},
	["Aimed Shot"] = {
		["duration"] = 6,
		["texture"] = "Interface\\Icons\\INV_Spear_07",
		["spellID"] = 20904,
	},
	["Raptor Strike"] = {
		["duration"] = 6,
		["spellID"] = 14266,
		["texture"] = "Interface\\Icons\\Ability_MeleeDamage",
	},
	["Blind"] = {
		["duration"] = 300,
		["spellID"] = 2094,
		["texture"] = "Interface\\Icons\\Spell_Shadow_MindSteal",
	},
	["Immolation"] = {
		["duration"] = 3,
		["spellID"] = 20153,
		["texture"] = "Interface\\Icons\\Spell_Shadow_SummonInfernal",
	},
	["Baited Shot"] = {
		["duration"] = 8,
		["texture"] = "Interface\\Icons\\inv_misc_food_66",
		["spellID"] = 46321,
	},
	["Frost Trap"] = {
		["duration"] = 15,
		["spellID"] = 13809,
		["texture"] = "Interface\\Icons\\Spell_Frost_FreezingBreath",
	},
	["Shadowburn"] = {
		["duration"] = 15,
		["spellID"] = 18871,
		["texture"] = "Interface\\Icons\\Spell_Shadow_ScourgeBuild",
	},
	["Frost Nova"] = {
		["duration"] = 25,
		["spellID"] = 10230,
		["texture"] = "Interface\\Icons\\Spell_Frost_FrostNova",
	},
	["Stealth"] = {
		["duration"] = 10,
		["spellID"] = 1787,
		["texture"] = "Interface\\Icons\\Ability_Stealth",
	},
	["Restore Mana"] = {
		["duration"] = 60,
		["spellID"] = 17530,
		["texture"] = "Interface\\Icons\\Temp",
	},
	["MOLL-E Terminal"] = {
		["duration"] = 300,
		["texture"] = "Interface\\Icons\\INV_Letter_13",
		["spellID"] = 46001,
	},
	["Arcane Power"] = {
		["duration"] = 180,
		["spellID"] = 12042,
		["texture"] = "Interface\\Icons\\Spell_Nature_Lightning",
	},
	["Escape Artist"] = {
		["duration"] = 90,
		["texture"] = "Interface\\Icons\\Ability_Rogue_Trip",
		["spellID"] = 20589,
	},
	["Stoneform"] = {
		["duration"] = 180,
		["spellID"] = 20594,
		["texture"] = "Interface\\Icons\\Spell_Shadow_UnholyStrength",
	},
	["Enlighten"] = {
		["duration"] = 60,
		["spellID"] = 51476,
		["texture"] = "Interface\\Icons\\btnholyscriptures",
	},
	["Fire Blast"] = {
		["duration"] = 8,
		["spellID"] = 10199,
		["texture"] = "Interface\\Icons\\Spell_Fire_Fireball",
	},
	["Scatter Shot"] = {
		["duration"] = 30,
		["texture"] = "Interface\\Icons\\Ability_GolemStormBolt",
		["spellID"] = 19503,
	},
	["Shield Block"] = {
		["duration"] = 5,
		["spellID"] = 2565,
		["texture"] = "Interface\\Icons\\Ability_Defend",
	},
	["Regeneration"] = {
		["duration"] = 60,
		["texture"] = "Interface\\Icons\\INV_Potion_79",
		["spellID"] = 3223,
	},
	["Consecration"] = {
		["duration"] = 8,
		["spellID"] = 20924,
		["texture"] = "Interface\\Icons\\Spell_Holy_InnerFire",
	},
	["Slow"] = {
		["duration"] = 10,
		["spellID"] = 11436,
		["texture"] = "Interface\\Icons\\Spell_Nature_Slow",
	},
	["Tea"] = {
		["duration"] = 60,
		["spellID"] = 19398,
		["texture"] = "Interface\\Icons\\Temp",
	},
	["Poison Spit"] = {
		["duration"] = 8,
		["spellID"] = 46273,
		["texture"] = "Interface\\Icons\\Spell_Nature_CorrosiveBreath",
	},
	["Howl of Terror"] = {
		["duration"] = 40,
		["spellID"] = 17928,
		["texture"] = "Interface\\Icons\\Spell_Shadow_DeathScream",
	},
	["Nature's Grasp"] = {
		["duration"] = 60,
		["spellID"] = 17329,
		["texture"] = "Interface\\Icons\\Spell_Nature_NaturesWrath",
	},
	["Scorpid Poison"] = {
		["duration"] = 3,
		["texture"] = "Interface\\Icons\\Ability_PoisonSting",
		["spellID"] = 24586,
	},
	["Major Healthstone"] = {
		["duration"] = 60,
		["texture"] = "Interface\\Icons\\INV_Stone_04",
		["spellID"] = 23477,
	},
	["Inferno Effect"] = {
		["duration"] = 10,
		["spellID"] = 22703,
		["texture"] = "Interface\\Icons\\Spell_Frost_Stun",
	},
	["Crusader Strike"] = {
		["duration"] = 6,
		["spellID"] = 10337,
		["texture"] = "Interface\\Icons\\Spell_Holy_CrusaderStrike",
	},
	["Wing Clip"] = {
		["duration"] = 3,
		["spellID"] = 14268,
		["texture"] = "Interface\\Icons\\Ability_Rogue_Trip",
	},
	["Avatar"] = {
		["duration"] = 300,
		["texture"] = "Interface\\Icons\\Ability_Racial_Avatar",
		["spellID"] = 51741,
	},
	["Death Coil"] = {
		["duration"] = 120,
		["texture"] = "Interface\\Icons\\Spell_Shadow_DeathCoil",
		["spellID"] = 17926,
	},
	["Chastise"] = {
		["duration"] = 40,
		["spellID"] = 51480,
		["texture"] = "Interface\\Icons\\Spell_Holy_UnyieldingFaith",
	},
	["Lash of Pain"] = {
		["duration"] = 10,
		["spellID"] = 11780,
		["texture"] = "Interface\\Icons\\Spell_Shadow_Curse",
	},
	["Lesser Invisibility"] = {
		["duration"] = 300,
		["spellID"] = 7870,
		["texture"] = "Interface\\Icons\\Spell_Magic_LesserInvisibilty",
	},
	["Ice Barrier"] = {
		["duration"] = 30,
		["texture"] = "Interface\\Icons\\Spell_Ice_Lament",
		["spellID"] = 13033,
	},
	["Drink"] = {
		["duration"] = 60,
		["spellID"] = 1137,
		["texture"] = "Interface\\Icons\\INV_Drink_07",
	},
	["Holy Strike"] = {
		["duration"] = 6,
		["spellID"] = 10333,
		["texture"] = "Interface\\Icons\\INV_Sword_01",
	},
	["Lay on Hands"] = {
		["duration"] = 3600,
		["texture"] = "Interface\\Icons\\Spell_Holy_LayOnHands",
		["spellID"] = 10310,
	},
	["Hearthstone"] = {
		["duration"] = 1800,
		["spellID"] = 8690,
		["texture"] = "Interface\\Icons\\INV_Misc_Rune_01_Purple",
	},
	["Sprint"] = {
		["duration"] = 240,
		["spellID"] = 11305,
		["texture"] = "Interface\\Icons\\Ability_Rogue_Sprint",
	},
	["Intimidating Shout"] = {
		["duration"] = 180,
		["spellID"] = 5246,
		["texture"] = "Interface\\Icons\\Ability_GolemThunderClap",
	},
	["Savage Bite"] = {
		["duration"] = 6,
		["spellID"] = 45736,
		["texture"] = "Interface\\Icons\\Ability_Racial_Cannibalize",
	},
	["Lacerate"] = {
		["duration"] = 10,
		["spellID"] = 48049,
		["texture"] = "Interface\\Icons\\spell_lacerate_1C",
	},
	["Arcane Shot"] = {
		["duration"] = 6,
		["texture"] = "Interface\\Icons\\Ability_ImpalingBolt",
		["spellID"] = 14287,
	},
	["Perception"] = {
		["duration"] = 180,
		["spellID"] = 20600,
		["texture"] = "Interface\\Icons\\Spell_Nature_Sleep",
	},
	["Fire Ward"] = {
		["duration"] = 30,
		["spellID"] = 10225,
		["texture"] = "Interface\\Icons\\Spell_Fire_FireArmor",
	},
	["Hamstring"] = {
		["duration"] = 6,
		["spellID"] = 7373,
		["texture"] = "Interface\\Icons\\Ability_ShockWave",
	},
	["Gouge"] = {
		["spellID"] = 11286,
		["firstSeen"] = 127978.837,
		["duration"] = 10,
		["texture"] = "Interface\\Icons\\Ability_Gouge",
		["spellName"] = "Gouge",
	},
	["Distract"] = {
		["duration"] = 30,
		["texture"] = "Interface\\Icons\\Ability_Rogue_Distract",
		["spellID"] = 1725,
	},
	["Cold Blood"] = {
		["duration"] = 180,
		["spellID"] = 14177,
		["texture"] = "Interface\\Icons\\Spell_Ice_Lament",
	},
	["Power Word: Shield"] = {
		["duration"] = 4,
		["texture"] = "Interface\\Icons\\Spell_Holy_PowerWordShield",
		["spellID"] = 10901,
	},
	["Shadowmeld"] = {
		["duration"] = 60,
		["spellID"] = 20580,
		["texture"] = "Interface\\Icons\\Ability_Ambush",
	},
	["Innervate"] = {
		["duration"] = 360,
		["spellID"] = 29166,
		["texture"] = "Interface\\Icons\\Spell_Nature_Lightning",
	},
	["Repentance"] = {
		["duration"] = 60,
		["spellID"] = 51558,
		["texture"] = "Interface\\Icons\\Spell_Holy_PrayerOfHealing",
	},
	["Web"] = {
		["duration"] = 60,
		["texture"] = "Interface\\Icons\\Spell_Nature_Web",
		["spellID"] = 36533,
	},
	["Charge"] = {
		["duration"] = 15,
		["texture"] = "Interface\\Icons\\Ability_Warrior_Charge",
		["spellID"] = 11578,
	},
	["Searing Shot"] = {
		["duration"] = 10,
		["spellID"] = 52646,
		["texture"] = "Interface\\Icons\\Ability_SearingArrow",
	},
	["Shadow Ward"] = {
		["duration"] = 30,
		["spellID"] = 28610,
		["texture"] = "Interface\\Icons\\Spell_Shadow_AntiShadow",
	},
	["Torment"] = {
		["duration"] = 5,
		["texture"] = "Interface\\Icons\\Spell_Shadow_GatherShadows",
		["spellID"] = 11774,
	},
	["Presence of Mind"] = {
		["duration"] = 180,
		["spellID"] = 12043,
		["texture"] = "Interface\\Icons\\Spell_Nature_EnchantArmor",
	},
	["Overpower"] = {
		["duration"] = 5,
		["spellID"] = 11585,
		["texture"] = "Interface\\Icons\\Ability_MeleeDamage",
	},
	["Multi-Shot"] = {
		["duration"] = 10,
		["spellID"] = 25294,
		["texture"] = "Interface\\Icons\\Ability_UpgradeMoonGlaive",
	},
	["Arcane Rupture"] = {
		["duration"] = 15,
		["spellID"] = 51954,
		["texture"] = "Interface\\Icons\\Spell_Arcane_Blast",
	},
	["Immolation Trap"] = {
		["duration"] = 15,
		["spellID"] = 14305,
		["texture"] = "Interface\\Icons\\Spell_Fire_FlameShock",
	},
	["Frost Ward"] = {
		["duration"] = 30,
		["spellID"] = 28609,
		["texture"] = "Interface\\Icons\\Spell_Frost_FrostWard",
	},
	["Psychic Scream"] = {
		["duration"] = 30,
		["spellID"] = 10890,
		["texture"] = "Interface\\Icons\\Spell_Shadow_PsychicScream",
	},
	["Blink"] = {
		["duration"] = 15,
		["spellID"] = 1953,
		["texture"] = "Interface\\Icons\\Spell_Arcane_Blink",
	},
	["Pummel"] = {
		["duration"] = 10,
		["spellID"] = 6552,
		["texture"] = "Interface\\Icons\\INV_Gauntlets_04",
	},
	["Restore Energy"] = {
		["duration"] = 60,
		["spellID"] = 9512,
		["texture"] = "Interface\\Icons\\Temp",
	},
	["Concussive Shot"] = {
		["duration"] = 12,
		["spellID"] = 5116,
		["texture"] = "Interface\\Icons\\Spell_Frost_Stun",
	},
	["Fear Ward"] = {
		["duration"] = 30,
		["texture"] = "Interface\\Icons\\Spell_Holy_Excorcism",
		["spellID"] = 6346,
	},
	["Shield Wall"] = {
		["duration"] = 1800,
		["spellID"] = 871,
		["texture"] = "Interface\\Icons\\Ability_Warrior_ShieldWall",
	},
	["Will of the Forsaken"] = {
		["duration"] = 150,
		["spellID"] = 7744,
		["texture"] = "Interface\\Icons\\Spell_Shadow_RaiseDead",
	},
	["Flare"] = {
		["duration"] = 15,
		["spellID"] = 1543,
		["texture"] = "Interface\\Icons\\Spell_Fire_Flare",
	},
	["Disarm"] = {
		["duration"] = 60,
		["spellID"] = 676,
		["texture"] = "Interface\\Icons\\Ability_Warrior_Disarm",
	},
	["Hammer of Wrath"] = {
		["duration"] = 6,
		["spellID"] = 24239,
		["texture"] = "Interface\\Icons\\Ability_ThunderClap",
	},
	["Holy Shock"] = {
		["duration"] = 20,
		["spellID"] = 51786,
		["texture"] = "Interface\\Icons\\Spell_Holy_SearingLight",
	},
	["Bloodthirst"] = {
		["duration"] = 6,
		["spellID"] = 23894,
		["texture"] = "Interface\\Icons\\Spell_Nature_BloodLust",
	},
	["Cold Snap"] = {
		["duration"] = 600,
		["texture"] = "Interface\\Icons\\Spell_Frost_WizardMark",
		["spellID"] = 12472,
	},
	["Faerie Fire (Feral)"] = {
		["duration"] = 6,
		["spellID"] = 17392,
		["texture"] = "Interface\\Icons\\Spell_Nature_FaerieFire",
	},
	["Hand of Freedom"] = {
		["duration"] = 24,
		["spellID"] = 1044,
		["texture"] = "Interface\\Icons\\Spell_Holy_SealOfValor",
	},
	["Frenzied Regeneration"] = {
		["duration"] = 300,
		["spellID"] = 22896,
		["texture"] = "Interface\\Icons\\Ability_BullRush",
	},
	["Suffering"] = {
		["duration"] = 120,
		["spellID"] = 17752,
		["texture"] = "Interface\\Icons\\Spell_Shadow_BlackPlague",
	},
	["Kidney Shot"] = {
		["duration"] = 20,
		["spellID"] = 8643,
		["texture"] = "Interface\\Icons\\Ability_Rogue_KidneyShot",
	},
	["Barkskin"] = {
		["duration"] = 60,
		["spellID"] = 22812,
		["texture"] = "Interface\\Icons\\Spell_Nature_StoneClawTotem",
	},
	["Mongoose Bite"] = {
		["duration"] = 5,
		["spellID"] = 14271,
		["texture"] = "Interface\\Icons\\Ability_Hunter_SwiftStrike",
	},
	["Master Strike"] = {
		["duration"] = 30,
		["spellID"] = 54023,
		["texture"] = "Interface\\Icons\\master_strike_1",
	},
	["Vanish"] = {
		["duration"] = 300,
		["spellID"] = 1857,
		["texture"] = "Interface\\Icons\\Ability_Vanish",
	},
	["Deterrence"] = {
		["duration"] = 300,
		["spellID"] = 19263,
		["texture"] = "Interface\\Icons\\Ability_Whirlwind",
	},
	["Rapid Fire"] = {
		["duration"] = 300,
		["spellID"] = 3045,
		["texture"] = "Interface\\Icons\\Ability_Hunter_RunningShot",
	},
	["Invulnerability"] = {
		["duration"] = 300,
		["spellID"] = 3169,
		["texture"] = "Interface\\Icons\\Spell_Holy_DivineIntervention",
	},
	["Whirlwind"] = {
		["duration"] = 10,
		["spellID"] = 1680,
		["texture"] = "Interface\\Icons\\Ability_Whirlwind",
	},
	["Starshards"] = {
		["duration"] = 30,
		["texture"] = "Interface\\Icons\\Spell_Arcane_StarFire",
		["spellID"] = 19305,
	},
	["Fade"] = {
		["duration"] = 30,
		["texture"] = "Interface\\Icons\\Spell_Magic_LesserInvisibilty",
		["spellID"] = 10942,
	},
	["Mortal Strike"] = {
		["duration"] = 6,
		["texture"] = "Interface\\Icons\\Ability_Warrior_SavageBlow",
		["spellID"] = 21553,
	},
	["Bash"] = {
		["duration"] = 60,
		["spellID"] = 8983,
		["texture"] = "Interface\\Icons\\Ability_Druid_Bash",
	},
	["Hurricane"] = {
		["duration"] = 10,
		["spellID"] = 17401,
		["texture"] = "Interface\\Icons\\Spell_Nature_Cyclone",
	},
	["Silence"] = {
		["duration"] = 45,
		["texture"] = "Interface\\Icons\\Spell_Shadow_ImpPhaseShift",
		["spellID"] = 15487,
	},
	["Death Wish"] = {
		["duration"] = 180,
		["spellID"] = 12328,
		["texture"] = "Interface\\Icons\\Spell_Shadow_DeathPact",
	},
	["Healing Draught"] = {
		["duration"] = 10,
		["spellID"] = 21393,
		["texture"] = "Interface\\Icons\\Temp",
	},
	["Skyrider's Tenacity"] = {
		["duration"] = 4,
		["texture"] = "Interface\\Icons\\Spell_Nature_Sentinal",
		["spellID"] = 57693,
	},
	["Judgement"] = {
		["duration"] = 10,
		["spellID"] = 20271,
		["texture"] = "Interface\\Icons\\Spell_Holy_RighteousFury",
	},
	["Enrage"] = {
		["duration"] = 60,
		["spellID"] = 5229,
		["texture"] = "Interface\\Icons\\Ability_Druid_Enrage",
	},
	["Nature's Swiftness"] = {
		["duration"] = 180,
		["spellID"] = 17116,
		["texture"] = "Interface\\Icons\\Spell_Nature_RavenForm",
	},
	["Goblin Brainwashing Device"] = {
		["duration"] = 600,
		["texture"] = "Interface\\Icons\\INV_Gizmo_01",
		["spellID"] = 46002,
	},
	["Ghostly Strike"] = {
		["duration"] = 20,
		["texture"] = "Interface\\Icons\\Spell_Shadow_Curse",
		["spellID"] = 14278,
	},
	["Healing Potion"] = {
		["duration"] = 10,
		["spellID"] = 17534,
		["texture"] = "Interface\\Icons\\Temp",
	},
	["Berserk"] = {
		["duration"] = 360,
		["spellID"] = 45708,
		["texture"] = "Interface\\Icons\\Ability_Druid_Berserk",
	},
	["Heathen's Light"] = {
		["duration"] = 8,
		["spellID"] = 52428,
		["texture"] = "Interface\\Icons\\Spell_Holy_GreaterBlessingofLight",
	},
	["Kill Command"] = {
		["duration"] = 12,
		["texture"] = "Interface\\Icons\\ability_hunter_killcommand",
		["spellID"] = 41827,
	},
	["Carve"] = {
		["duration"] = 10,
		["spellID"] = 52416,
		["texture"] = "Interface\\Icons\\INV_ThrowingKnife_06",
	},
	["Revealed Flaw"] = {
		["duration"] = 180,
		["spellID"] = 28815,
		["texture"] = "Interface\\Icons\\Ability_Warrior_Revenge",
	},
	["Preparation"] = {
		["duration"] = 420,
		["spellID"] = 14185,
		["texture"] = "Interface\\Icons\\Spell_Shadow_AntiShadow",
	},
	["Deadly Throw"] = {
		["duration"] = 10,
		["texture"] = "Interface\\Icons\\INV_ThrowingKnife_03",
		["spellID"] = 45605,
	},
	["Explosive Trap"] = {
		["duration"] = 15,
		["spellID"] = 14317,
		["texture"] = "Interface\\Icons\\Spell_Fire_SelfDestruct",
	},
	["Ice Block"] = {
		["duration"] = 300,
		["texture"] = "Interface\\Icons\\Spell_Frost_Frost",
		["spellID"] = 11958,
	},
	["Freezing Trap"] = {
		["duration"] = 15,
		["texture"] = "Interface\\Icons\\Spell_Frost_ChainsOfIce",
		["spellID"] = 14311,
	},
	["Prowl"] = {
		["duration"] = 10,
		["spellID"] = 9913,
		["texture"] = "Interface\\Icons\\Ability_Ambush",
	},
	["Evasion"] = {
		["spellName"] = "Evasion",
		["firstSeen"] = 128028.209,
		["duration"] = 240,
		["texture"] = "Interface\\Icons\\Spell_Shadow_ShadowWard",
		["spellID"] = 5277,
	},
	["Flourish"] = {
		["duration"] = 40,
		["spellID"] = 45604,
		["texture"] = "Interface\\Icons\\Ability_DualWield",
	},
	["Hand of Protection"] = {
		["duration"] = 300,
		["spellID"] = 10278,
		["texture"] = "Interface\\Icons\\Spell_Holy_SealOfProtection",
	},
	["Quel'dorei Meditation"] = {
		["duration"] = 180,
		["spellID"] = 46021,
		["texture"] = "Interface\\Icons\\Spell_Holy_MindSooth",
	},
	["Counterspell"] = {
		["duration"] = 30,
		["spellID"] = 2139,
		["texture"] = "Interface\\Icons\\Spell_Frost_IceShock",
	},
	["Mind Blast"] = {
		["duration"] = 8,
		["texture"] = "Interface\\Icons\\Spell_Shadow_UnholyFrenzy",
		["spellID"] = 10947,
	},
	["Feign Death"] = {
		["duration"] = 30,
		["spellID"] = 5384,
		["texture"] = "Interface\\Icons\\Ability_Rogue_FeignDeath",
	},
	["Bite"] = {
		["duration"] = 6,
		["spellID"] = 17261,
		["texture"] = "Interface\\Icons\\Ability_Racial_Cannibalize",
	},
	["Growl"] = {
		["duration"] = 10,
		["texture"] = "Interface\\Icons\\Ability_Physical_Taunt",
		["spellID"] = 6795,
	},
	["Viper Sting"] = {
		["duration"] = 6,
		["spellID"] = 14280,
		["texture"] = "Interface\\Icons\\Ability_Hunter_AimedShot",
	},
	["Cone of Cold"] = {
		["duration"] = 10,
		["spellID"] = 10161,
		["texture"] = "Interface\\Icons\\Spell_Frost_Glacier",
	},
	["Soul Fire"] = {
		["duration"] = 30,
		["spellID"] = 51684,
		["texture"] = "Interface\\Icons\\Spell_Fire_Fireball02",
	},
	["Blade Flurry"] = {
		["duration"] = 4,
		["spellID"] = 13877,
		["texture"] = "Interface\\Icons\\Ability_Warrior_PunishingBlow",
	},
	["Traveler's Tent"] = {
		["duration"] = 7200,
		["spellID"] = 46072,
		["texture"] = "Interface\\Icons\\Temp",
	},
	["Ritual of Souls"] = {
		["duration"] = 300,
		["spellID"] = 45920,
		["texture"] = "Interface\\Icons\\INV_Misc_ShadowEgg",
	},
	["Free Action"] = {
		["duration"] = 60,
		["spellID"] = 6615,
		["texture"] = "Interface\\Icons\\INV_Potion_04",
	},
	["Barkskin (Feral)"] = {
		["duration"] = 600,
		["spellID"] = 51452,
		["texture"] = "Interface\\Icons\\Spell_Nature_StoneClawTotem",
	},
	["Inner Focus"] = {
		["duration"] = 180,
		["spellID"] = 14751,
		["texture"] = "Interface\\Icons\\Spell_Frost_WindWalkOn",
	},
	["Vampiric Embrace"] = {
		["duration"] = 10,
		["texture"] = "Interface\\Icons\\Spell_Shadow_UnsummonBuilding",
		["spellID"] = 15286,
	},
	["Pain Spike"] = {
		["duration"] = 40,
		["spellID"] = 57707,
		["texture"] = "Interface\\Icons\\Spell_Shadow_PainSpike",
	},
	["Death by Peasant"] = {
		["duration"] = 60,
		["spellID"] = 18308,
		["texture"] = "Interface\\Icons\\Spell_Shadow_SummonVoidWalker",
	},
	["Thunder Clap"] = {
		["duration"] = 4,
		["texture"] = "Interface\\Icons\\Spell_Nature_ThunderClap",
		["spellID"] = 11580,
	},
	["Feral Charge"] = {
		["duration"] = 15,
		["spellID"] = 16979,
		["texture"] = "Interface\\Icons\\Ability_Hunter_Pet_Bear",
	},
	["Intercept"] = {
		["duration"] = 30,
		["texture"] = "Interface\\Icons\\Ability_Rogue_Sprint",
		["spellID"] = 20617,
	},
	["Intimidation"] = {
		["duration"] = 60,
		["texture"] = "Interface\\Icons\\Ability_Devour",
		["spellID"] = 19577,
	},
	["Conflagrate"] = {
		["duration"] = 10,
		["spellID"] = 18932,
		["texture"] = "Interface\\Icons\\Spell_Fire_Fireball",
	},
	["Rebirth"] = {
		["duration"] = 1800,
		["spellID"] = 20748,
		["texture"] = "Interface\\Icons\\Spell_Nature_Reincarnation",
	},
	["Shock"] = {
		["duration"] = 6,
		["spellID"] = 2610,
		["texture"] = "Interface\\Icons\\Spell_Nature_WispHeal",
	},
	["Dash"] = {
		["duration"] = 300,
		["spellID"] = 9821,
		["texture"] = "Interface\\Icons\\Ability_Druid_Dash",
	},
	["Kick"] = {
		["duration"] = 10,
		["spellID"] = 1769,
		["texture"] = "Interface\\Icons\\Ability_Kick",
	},
	["Spell Lock"] = {
		["duration"] = 30,
		["texture"] = "Interface\\Icons\\Spell_Shadow_MindRot",
		["spellID"] = 19647,
	},
	["Divine Shield"] = {
		["duration"] = 300,
		["spellID"] = 1020,
		["texture"] = "Interface\\Icons\\Spell_Holy_DivineIntervention",
	},
	["Tidal"] = {
		["duration"] = 900,
		["spellID"] = 835,
		["texture"] = "Interface\\Icons\\INV_Misc_Rune_01",
	},
}