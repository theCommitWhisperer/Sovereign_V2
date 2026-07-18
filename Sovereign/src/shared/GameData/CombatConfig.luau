--!strict
-- CombatConfig: Single source of truth for all combat v2 tuning.
-- Counter matrix, unit combat profiles, stances, positional bonuses,
-- projectiles, abilities, building durability, and engine tick rates.

export type DamageType = "Slash" | "Pierce" | "Blunt" | "Magic" | "Siege"
export type ArmorClass = "Unarmored" | "Light" | "Medium" | "Heavy" | "Structure"
export type AttackType = "Melee" | "Ranged"

export type ProjectileDef = {
	speed: number, -- studs/sec
	arcHeight: number, -- studs at apex
	visual: string, -- client visual key
	baseAccuracy: number, -- 0..1 vs stationary target
	movingPenalty: number, -- accuracy subtracted vs moving target
}

export type UnitCombatProfile = {
	damageType: DamageType,
	armorClass: ArmorClass,
	attackType: AttackType,
	tags: { string }?, -- "cavalry", "spear", "ranged", "civilian", "hero", "siege", "beast", "caster"
	bonusVsTags: { [string]: number }?, -- extra multiplier vs defender tags
	projectile: string?, -- key into CombatConfig.Projectiles
	abilities: { string }?, -- keys into CombatConfig.Abilities
}

local CombatConfig = {}

-- ═══════════════════════════════════════════════════════════════════════════
-- ENGINE
-- ═══════════════════════════════════════════════════════════════════════════

CombatConfig.Engine = {
	COMBAT_TICK_RATE = 0.1, -- fighting units update at 10 Hz
	IDLE_SCAN_RATE = 0.5, -- idle units scan for enemies at 2 Hz
	GRID_CELL_SIZE = 32, -- studs, spatial grid cell
	SEARCH_RANGE = 60, -- default enemy search radius (studs)
	AGGRESSIVE_SEARCH_MULT = 1.5,
	MELEE_RANGE = 8, -- studs fallback
	METERS_TO_STUDS = 3,
	RANGED_RANGE_MULT = 1.5, -- extra reach for ranged subtypes
	MAX_REPLICATION_EVENTS_PER_TICK = 120,
	BUILDING_SEARCH_RANGE = 80, -- how far units look for enemy buildings when no units found
}

-- ═══════════════════════════════════════════════════════════════════════════
-- COUNTER MATRIX  (damage type vs armor class multiplier)
-- ═══════════════════════════════════════════════════════════════════════════

CombatConfig.CounterMatrix = {
	Slash = { Unarmored = 1.15, Light = 1.10, Medium = 1.00, Heavy = 0.85, Structure = 0.50 },
	Pierce = { Unarmored = 1.00, Light = 1.10, Medium = 1.05, Heavy = 1.15, Structure = 0.35 },
	Blunt = { Unarmored = 0.90, Light = 1.00, Medium = 1.10, Heavy = 1.25, Structure = 0.80 },
	Magic = { Unarmored = 1.10, Light = 1.10, Medium = 1.10, Heavy = 1.10, Structure = 0.60 },
	Siege = { Unarmored = 0.70, Light = 0.70, Medium = 0.70, Heavy = 0.70, Structure = 3.00 },
} :: { [DamageType]: { [ArmorClass]: number } }

-- ═══════════════════════════════════════════════════════════════════════════
-- STANCES & POSITIONING
-- ═══════════════════════════════════════════════════════════════════════════

CombatConfig.StanceModifiers = {
	Aggressive = { damage = 1.25, defense = 0.85 },
	Defensive = { damage = 0.75, defense = 1.40 },
	Hold = { damage = 1.00, defense = 1.20 },
	Charge = { damage = 1.50, defense = 0.70 },
}

CombatConfig.Positional = {
	CHARGE_DISTANCE = 30,
	CHARGE_DAMAGE_BONUS = 1.5,
	IRISH_CHARGE_BONUS = 1.3, -- replaces charge bonus for Irish factions (stacks with fury instead)
	FLANKING_DAMAGE_BONUS = 1.4,
	REAR_ATTACK_BONUS = 1.6,
	HIGH_GROUND_BONUS = 1.25,
	HIGH_GROUND_HEIGHT = 5, -- studs of elevation required
	-- Formation cohesion: allies close by make you harder to kill
	FORMATION_RADIUS = 9, -- studs
	FORMATION_MIN_ALLIES = 3,
	FORMATION_DEFENSE_MULT = 0.88, -- damage taken multiplier when in cohesion
	-- Brace: spear units in Defensive/Hold negate charges against them
	BRACE_COUNTER_BONUS = 1.5, -- extra damage spears deal to a charging attacker on their next hit
}

CombatConfig.Morale = {
	ATTACKER_SCALE = 0.25, -- morale swings damage by ±12.5%
	DAMAGE_TAKEN_MORALE_LOSS = -5,
	DAMAGE_DEALT_MORALE_GAIN = 2,
	NEARBY_DEATH_ENEMY_BONUS = 5,
	NEARBY_DEATH_RADIUS = 30,
}

-- ═══════════════════════════════════════════════════════════════════════════
-- PROJECTILES
-- ═══════════════════════════════════════════════════════════════════════════

CombatConfig.Projectiles = {
	Arrow = { speed = 90, arcHeight = 8, visual = "Arrow", baseAccuracy = 0.92, movingPenalty = 0.20 },
	Longbow = { speed = 110, arcHeight = 12, visual = "Arrow", baseAccuracy = 0.90, movingPenalty = 0.15 },
	Stone = { speed = 70, arcHeight = 10, visual = "Stone", baseAccuracy = 0.85, movingPenalty = 0.25 },
	Javelin = { speed = 80, arcHeight = 6, visual = "Javelin", baseAccuracy = 0.88, movingPenalty = 0.22 },
	Bolt = { speed = 130, arcHeight = 3, visual = "Bolt", baseAccuracy = 0.95, movingPenalty = 0.15 },
	MagicBolt = { speed = 60, arcHeight = 2, visual = "Magic", baseAccuracy = 1.0, movingPenalty = 0.0 },
} :: { [string]: ProjectileDef }

-- ═══════════════════════════════════════════════════════════════════════════
-- ABILITIES (passive + triggered flavor abilities)
-- ═══════════════════════════════════════════════════════════════════════════

CombatConfig.Abilities = {
	-- Irish core (kept + tuned)
	CelticFury = {
		moraleThreshold = 80,
		damageMult = 1.2,
		speedMult = 1.3,
	},
	WarCry = {
		cooldown = 30,
		minMorale = 60,
		radius = 25,
		moraleBoost = 15,
	},
	ShieldWall = {
		radius = 10,
		minAllies = 2,
		baseReduction = 0.4,
		perAllyReduction = 0.05,
		maxReduction = 0.7,
	},
	-- Expanded roster flavor
	Heal = { cooldown = 8, radius = 18, amount = 12 }, -- Monk, Druid, Priest
	BattleSong = { radius = 22, damageMult = 1.08, moralePerTick = 1, tickEvery = 5 }, -- Bard
	Wail = { cooldown = 25, radius = 20, moraleDamage = -20 }, -- Banshee
	PackHunter = { radius = 14, perAllyDamage = 0.10, maxBonus = 0.4 }, -- Wolfhound (per nearby wolfhound)
	Trample = { chargeBonusMult = 1.2 }, -- Knight/Hobelar: stronger charges
	HitAndRun = { retreatHealthPct = 0.35, speedMult = 1.25 }, -- Hobelar/Kern: flee when hurt
	Berserk = { healthPct = 0.4, damageMult = 1.35, defenseMult = 0.8 }, -- Fianna/Viking: rage below 40% HP
	Ambush = { firstStrikeMult = 1.5 }, -- Bonnacht: first hit on a fresh target
	ShieldBash = { cooldown = 12, stunSeconds = 1.2 }, -- Gallowglass: periodic stun
	Volley = { cooldown = 20, extraShots = 2 }, -- Longbowman: periodic multi-shot
}

-- ═══════════════════════════════════════════════════════════════════════════
-- BUILDING DURABILITY (buildings have no HP in BuildingsData; defined here)
-- ═══════════════════════════════════════════════════════════════════════════

CombatConfig.BuildingHealth = {
	Default = 1000,
	ByType = {
		Keep = 3000,
		Barracks = 1500,
		ArcheryRange = 1200,
		Stable = 1500,
		WatchTower = 1400,
		Wall = 2000,
		WoodWall = 1200,
		StoneWall = 2500,
		Gate = 1800,
		House = 600,
		Farm = 500,
		LumberCamp = 700,
		Quarry = 800,
		Mine = 800,
		Granary = 900,
		Storehouse = 900,
		Market = 800,
		Church = 1000,
		Tavern = 700,
	} :: { [string]: number },
}

-- ═══════════════════════════════════════════════════════════════════════════
-- UNIT COMBAT PROFILES (overlay on UnitsData; every combat-capable unit)
-- ═══════════════════════════════════════════════════════════════════════════

local CIVILIAN: UnitCombatProfile = {
	damageType = "Blunt",
	armorClass = "Unarmored",
	attackType = "Melee",
	tags = { "civilian" },
}

local UnitProfiles: { [string]: UnitCombatProfile } = {
	King = {
		damageType = "Slash",
		armorClass = "Heavy",
		attackType = "Melee",
		tags = { "hero" },
		abilities = { "WarCry" },
	},
	Peasant = CIVILIAN,
	Woodcutter = CIVILIAN,
	Stonemason = CIVILIAN,
	Farmer = CIVILIAN,
	Miner = CIVILIAN,
	Fisherman = CIVILIAN,
	Smelter = CIVILIAN,
	Blacksmith = CIVILIAN,
	Carpenter = CIVILIAN,
	Tanner = CIVILIAN,
	Miller = CIVILIAN,
	Baker = CIVILIAN,
	Brewer = CIVILIAN,
	Merchant = CIVILIAN,
	Trader = CIVILIAN,
	Innkeeper = CIVILIAN,
	Scribe = CIVILIAN,
	Administrator = CIVILIAN,

	Spearman = {
		damageType = "Pierce",
		armorClass = "Medium",
		attackType = "Melee",
		tags = { "spear", "infantry" },
		bonusVsTags = { cavalry = 1.8 },
	},
	Viking = {
		damageType = "Slash",
		armorClass = "Medium",
		attackType = "Melee",
		tags = { "infantry", "raider" },
		abilities = { "Berserk" },
	},
	Archer = {
		damageType = "Pierce",
		armorClass = "Light",
		attackType = "Ranged",
		tags = { "ranged" },
		projectile = "Arrow",
	},
	Knight = {
		damageType = "Slash",
		armorClass = "Heavy",
		attackType = "Melee",
		tags = { "cavalry" },
		bonusVsTags = { ranged = 1.3, civilian = 1.3 },
		abilities = { "Trample" },
	},
	Monk = {
		damageType = "Magic",
		armorClass = "Unarmored",
		attackType = "Melee",
		tags = { "caster", "support" },
		abilities = { "Heal" },
	},
	Priest = {
		damageType = "Magic",
		armorClass = "Unarmored",
		attackType = "Melee",
		tags = { "caster", "support", "civilian" },
		abilities = { "Heal" },
	},
	Bard = {
		damageType = "Blunt",
		armorClass = "Unarmored",
		attackType = "Melee",
		tags = { "support" },
		abilities = { "BattleSong" },
	},
	Kern = {
		damageType = "Slash",
		armorClass = "Light",
		attackType = "Melee",
		tags = { "infantry", "skirmisher" },
		abilities = { "HitAndRun" },
	},
	Ceithern = {
		damageType = "Pierce",
		armorClass = "Light",
		attackType = "Ranged",
		tags = { "ranged", "skirmisher" },
		projectile = "Javelin",
		bonusVsTags = { cavalry = 1.4 },
	},
	Bonnacht = {
		damageType = "Slash",
		armorClass = "Medium",
		attackType = "Melee",
		tags = { "infantry" },
		abilities = { "Ambush" },
	},
	Gallowglass = {
		damageType = "Slash",
		armorClass = "Heavy",
		attackType = "Melee",
		tags = { "infantry", "elite" },
		abilities = { "ShieldBash" },
	},
	Fianna = {
		damageType = "Slash",
		armorClass = "Medium",
		attackType = "Melee",
		tags = { "infantry", "elite", "hero" },
		abilities = { "Berserk", "WarCry" },
	},
	Slinger = {
		damageType = "Blunt",
		armorClass = "Light",
		attackType = "Ranged",
		tags = { "ranged" },
		projectile = "Stone",
	},
	Longbowman = {
		damageType = "Pierce",
		armorClass = "Light",
		attackType = "Ranged",
		tags = { "ranged" },
		projectile = "Longbow",
		abilities = { "Volley" },
	},
	Hobelar = {
		damageType = "Slash",
		armorClass = "Light",
		attackType = "Melee",
		tags = { "cavalry", "skirmisher" },
		bonusVsTags = { ranged = 1.3 },
		abilities = { "Trample", "HitAndRun" },
	},
	Druid = {
		damageType = "Magic",
		armorClass = "Light",
		attackType = "Ranged",
		tags = { "caster" },
		projectile = "MagicBolt",
		abilities = { "Heal" },
	},
	Banshee = {
		damageType = "Magic",
		armorClass = "Unarmored",
		attackType = "Ranged",
		tags = { "caster" },
		projectile = "MagicBolt",
		abilities = { "Wail" },
	},
	Wolfhound = {
		damageType = "Slash",
		armorClass = "Unarmored",
		attackType = "Melee",
		tags = { "beast" },
		abilities = { "PackHunter" },
	},
}

CombatConfig.UnitProfiles = UnitProfiles

-- Fallback profile by UnitsData.subtype when a unit has no explicit profile
local SubtypeDefaults: { [string]: UnitCombatProfile } = {
	Worker = CIVILIAN,
	Hero = { damageType = "Slash", armorClass = "Heavy", attackType = "Melee", tags = { "hero" } },
	Ranged = { damageType = "Pierce", armorClass = "Light", attackType = "Ranged", tags = { "ranged" }, projectile = "Arrow" },
	["Ranged Infantry"] = { damageType = "Pierce", armorClass = "Light", attackType = "Ranged", tags = { "ranged" }, projectile = "Arrow" },
	Cavalry = { damageType = "Slash", armorClass = "Heavy", attackType = "Melee", tags = { "cavalry" } },
}
CombatConfig.SubtypeDefaults = SubtypeDefaults

local DefaultProfile: UnitCombatProfile = {
	damageType = "Slash",
	armorClass = "Medium",
	attackType = "Melee",
	tags = { "infantry" },
}
CombatConfig.DefaultProfile = DefaultProfile

function CombatConfig.getProfile(unitType: string, subtype: string?): UnitCombatProfile
	local profile = CombatConfig.UnitProfiles[unitType]
	if profile then
		return profile
	end
	if subtype then
		local bySubtype = CombatConfig.SubtypeDefaults[subtype]
		if bySubtype then
			return bySubtype
		end
	end
	return CombatConfig.DefaultProfile
end

function CombatConfig.getBuildingMaxHealth(buildingType: string?): number
	if buildingType then
		local hp = CombatConfig.BuildingHealth.ByType[buildingType]
		if hp then
			return hp
		end
		-- Wall pieces often carry suffixes ("StoneWall_Corner"): prefix match
		for key, value in CombatConfig.BuildingHealth.ByType do
			if string.find(buildingType, key, 1, true) == 1 then
				return value
			end
		end
	end
	return CombatConfig.BuildingHealth.Default
end

function CombatConfig.hasTag(profile: UnitCombatProfile, tag: string): boolean
	if not profile.tags then
		return false
	end
	return table.find(profile.tags :: { string }, tag) ~= nil
end

return CombatConfig
