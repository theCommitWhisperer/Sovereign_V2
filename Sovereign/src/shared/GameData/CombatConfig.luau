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

export type WeaponKind = "Sword" | "Axe" | "Spear" | "Bow" | "Javelin" | "Staff" | "Club" | "Sling" | "None"

export type UnitCombatProfile = {
	damageType: DamageType,
	armorClass: ArmorClass,
	attackType: AttackType,
	tags: { string }?, -- "cavalry", "spear", "ranged", "civilian", "hero", "siege", "beast", "caster"
	bonusVsTags: { [string]: number }?, -- extra multiplier vs defender tags
	projectile: string?, -- key into CombatConfig.Projectiles
	abilities: { string }?, -- keys into CombatConfig.Abilities
	weapon: WeaponKind?, -- visual weapon prop (see WeaponVisuals); inferred if nil
	shield: boolean?, -- visual shield on the off-hand side
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
-- TARGET SELECTION (battle "feel": spread, group fights, natural chaos)
-- Score = distance − counter preference + crowding penalties + jitter;
-- lowest score wins. Tuning these changes how battles break apart.
-- ═══════════════════════════════════════════════════════════════════════════

CombatConfig.Targeting = {
	CROWDING_PENALTY = 10, -- score per ally already attacking that target
	RANGED_CROWDING_MULT = 0.4, -- ranged units mind crowding less (they share targets fine)
	SOFT_CAP_ATTACKERS = 4, -- beyond this many attackers, add OVERCROWD_PENALTY
	OVERCROWD_PENALTY = 45,
	COUNTER_WEIGHT = 16, -- score bonus for favourable counter matchups
	SCORE_JITTER = 8, -- random noise so identical units choose differently
	SCAN_JITTER_MAX = 0.35, -- seconds of per-unit scan desync
	RETARGET_INTERVAL = 1.5, -- chasing (not yet fighting) units re-evaluate this often
	RETARGET_MARGIN = 15, -- new target must beat current score by this much to switch
	SURROUND_RADIUS = 3.2, -- melee approach ring radius around the target
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

-- Player-facing stances. Each has combat modifiers (damage/defense, read by
-- DamageResolver) plus behaviour flags read by CombatService.
--   March    — the default when you issue a move. Passive: units travel
--              together at the group's slowest speed and do NOT auto-engage.
--   Attack   — seek out and charge enemies across a wide radius (attack-move).
--   Defend   — hold ground; only engage enemies that come near the guard post,
--              then return to it. Eligible for Shield Wall.
--   Skirmish — engage but kite: ranged keep their distance, melee hit-and-run.
CombatConfig.StanceModifiers = {
	March = { damage = 1.00, defense = 1.00 },
	Attack = { damage = 1.25, defense = 0.85 },
	Defend = { damage = 0.90, defense = 1.40 },
	Skirmish = { damage = 1.10, defense = 0.80 },
}

-- `braces`: the unit plants itself and receives a charge instead of absorbing it.
-- Read by DamageResolver.isBraced, which additionally requires the "spear" tag —
-- a braced swordsman is just a swordsman standing still.
--
-- This exists as data because the old brace test was the literal
-- `stance == "Defensive" or stance == "Hold"`. Those names were renamed to the
-- March/Attack/Defend/Skirmish vocabulary and nobody updated the test, so
-- isBraced() returned false for every unit in the game and the entire
-- brace-counter branch in CombatService.resolveHit was unreachable dead code for
-- its whole life. A stance rename now silently drops a flag off this table
-- rather than silently disabling a mechanic. Do NOT reuse `canCharge == false`
-- for this: March also can't charge, and a marching column must not brace.
CombatConfig.StanceBehavior = {
	March = { autoEngage = false, searchMult = 0, canCharge = false, leash = 0, kite = false, groupSpeed = true, braces = false },
	Attack = { autoEngage = true, searchMult = 1.5, canCharge = true, leash = math.huge, kite = false, groupSpeed = false, braces = false },
	Defend = { autoEngage = true, searchMult = 0.9, canCharge = false, leash = 26, kite = false, groupSpeed = false, braces = true },
	Skirmish = { autoEngage = true, searchMult = 1.2, canCharge = true, leash = math.huge, kite = true, groupSpeed = false, braces = false },
}

CombatConfig.DefaultStance = "Attack" -- newly spawned combat units
CombatConfig.MoveStance = "March" -- applied when the player issues a move order

CombatConfig.Skirmish = {
	-- Kite when an enemy gets within this fraction of the unit's attack range
	RANGED_KEEP_DISTANCE = 0.75,
	MELEE_RETREAT_TIME = 0.6, -- seconds a melee skirmisher backs off after a hit
	RETREAT_DISTANCE = 14, -- studs to fall back when kiting
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
	-- Trebuchet payload: slower, higher arc than the catapult stone; great vs
	-- stationary buildings, poor vs moving troops
	TrebuchetStone = { speed = 55, arcHeight = 22, visual = "Stone", baseAccuracy = 0.9, movingPenalty = 0.45 },
	-- Oilliphéist breath: fast gout of Otherworld fire
	WyrmFire = { speed = 75, arcHeight = 4, visual = "Magic", baseAccuracy = 0.95, movingPenalty = 0.1 },
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
-- HERO COMBAT (the player's Lord, third person)
-- ═══════════════════════════════════════════════════════════════════════════
--
-- Everything the server-authoritative hero state machine (server/Combat/
-- HeroCombat.luau) needs, and everything the client feedback layer
-- (client/Combat/HeroCombatController) mirrors for prediction. There is exactly
-- one copy of these numbers so the two can never drift.
--
-- TIMING VOCABULARY — every melee action is three phases, all in seconds:
--   windup      the swing is committed but nothing can be hit yet. This is the
--               window in which an opponent can see it coming.
--   activeWindow how long the hitbox arc is live. The server sweeps ONCE at the
--               start of it (a per-frame sweep on a 100-unit battlefield is not
--               affordable), so this value is really "how generous the sweep is"
--               — it is sent to clients as the hitflash duration.
--   recovery    committed, cannot act. nextActionAt = now + windup + active +
--               recovery.
--
--   comboWindow is measured from the END of recovery: press light again inside
--   it and you advance to the next step, miss it and the chain resets to step 1.
--   It must be > 0 or the combo is unreachable by a human.

export type HeroComboStep = {
	damageMult: number, -- multiplies the resolved (post-armor/counter) damage
	range: number, -- studs from the hero's PrimaryPart
	arcCos: number, -- cos of the swing's half-angle; LOWER = wider
	windup: number,
	activeWindow: number,
	recovery: number,
	comboWindow: number, -- grace period after recovery to chain the next step
	staminaCost: number,
}

export type HeroConfig = {
	-- Base fighter stats. GameManager (Lord) and ArenaMode (arena hero) both
	-- seed registerPlayerFighter from here so the two modes can't diverge.
	fighter: {
		baseType: string, -- seeds the combat damage-type profile ONLY
		maxHealth: number,
		attackDamage: number, -- the base DamageResolver feeds off; combo mults scale it
		armor: number,
	},
	lightCombo: { HeroComboStep },
	heavy: {
		damageMult: number,
		range: number,
		arcCos: number,
		windup: number,
		activeWindow: number,
		recovery: number,
		staminaCost: number,
		-- A heavy is a chain OPENER or a step-1/step-2 finisher, never the cap on
		-- a full light chain: allowing light→light→light→heavy makes the heavy
		-- free (the third light already staggered everyone) and the combo becomes
		-- a single unconditional rotation.
		maxComboIndexToChainFrom: number,
		holdSeconds: number, -- client: LMB held longer than this = heavy, not light
	},
	block: {
		damageReduction: number, -- 0..1 fraction of incoming damage removed
		parryWindow: number, -- seconds from block start in which a hit is a parry
		parryRiposteMult: number, -- damage mult on the light attack that follows
		parryRiposteWindow: number, -- how long the riposte stays available
		parryStunSeconds: number, -- applied to the parried attacker
		directional: boolean,
		facingDot: number, -- attacker must be within this dot of the hero's look
		moveSpeedMult: number, -- client: how slow you walk with the shield up
		staminaCostPerParry: number,
	},
	dodge: {
		distance: number, -- studs travelled
		speed: number, -- studs/sec the client rolls at
		invulnSeconds: number, -- i-frames, from the moment the server accepts it
		recovery: number, -- committed-but-vulnerable tail
		cooldown: number,
		staminaCost: number,
	},
	ranged: {
		-- The bow reuses the hero's attackDamage through the same resolveHit
		-- pipeline as melee, so armor/counter/morale all apply. damageMult is
		-- tuned so a shot lands near the legacy flat 45 off a base of 70.
		damageMult: number,
		range: number,
		arcCos: number,
		windup: number,
		recovery: number,
		cooldown: number,
		projectile: string, -- key into CombatConfig.Projectiles
		staminaCost: number,
		-- The hero fighter is seeded from a MELEE profile (Gallowglass, Slash), so
		-- without this override his arrows were resolved as sword cuts against the
		-- counter matrix: 0.85x into Heavy armour instead of 1.15x. Per-attack
		-- override rather than mutating the profile, which is a shared table.
		damageType: DamageType,
	},
	stamina: {
		-- DEFAULT OFF. The owner asked for combo / heavy / block / parry / dodge;
		-- a stamina bar was not on that list and adding a resource the player has
		-- to babysit changes the feel of a power-fantasy Lord from "wade into the
		-- peasants" to "manage a meter". Every cost above is already authored, so
		-- flipping this to true is a one-line balance experiment, not a rewrite.
		enabled: boolean,
		max: number,
		regenPerSecond: number,
		regenDelay: number, -- seconds after a spend before regen resumes
	},
	stagger: {
		-- Getting hit hard while in windup interrupts the swing.
		interruptDamageFraction: number, -- of maxHealth, in one hit
		seconds: number,
	},
	-- ── UNCONDITIONAL FRIENDLY FIRE ────────────────────────────────────────
	-- The player's swings hit ANYTHING in the arc: enemies, allied units, and
	-- his own peasants. This is a deliberate design decision by the project
	-- owner, not an oversight.
	--
	-- TRADEOFF, stated plainly: in a multiplayer match this is a griefing
	-- vector — a Lord can walk into his own army and cut it down, and there is
	-- no server-side check that stops him because "was that a mistake or was it
	-- intent?" is not answerable from a swing. It is accepted because the
	-- alternative (arc filtering by faction) means the player's sword passes
	-- harmlessly through a peasant standing between him and an enemy, which
	-- reads as a broken hitbox every single time. If this ever needs to become
	-- a per-lobby setting, flip this flag from the lobby settings table — every
	-- consumer reads it through CombatConfig, nothing hardcodes it.
	--
	-- Note this ONLY widens the PLAYER'S aimed attacks. The autonomous combat
	-- loop still refuses to target allies, so AI units never friendly-fire.
	playerAttacksHitAllies: boolean,
}

local MELEE = CombatConfig.Engine.MELEE_RANGE -- 8 studs; hero reach is this + a bit

CombatConfig.Hero = {
	fighter = {
		baseType = "Gallowglass",
		maxHealth = 800,
		attackDamage = 70,
		armor = 10,
	},

	-- Three-hit chain: quick opener, quick link, slow heavy finisher. Total
	-- damage of a full chain ≈ 1.0 + 1.15 + 1.65 = 3.8x a soldier's swing, over
	-- ~1.5s — strong, but you are locked in for that whole 1.5s.
	lightCombo = {
		{
			damageMult = 1.00,
			range = MELEE + 2, -- 10
			arcCos = 0.40, -- cos(~66°): wide enough to catch a small crowd
			windup = 0.12,
			activeWindow = 0.10,
			recovery = 0.26,
			comboWindow = 0.55,
			staminaCost = 8,
		},
		{
			damageMult = 1.15,
			range = MELEE + 2, -- 10
			arcCos = 0.45, -- slightly tighter backhand
			windup = 0.10,
			activeWindow = 0.10,
			recovery = 0.24,
			comboWindow = 0.50,
			staminaCost = 8,
		},
		{
			damageMult = 1.65,
			range = MELEE + 3, -- 11: the finisher steps in
			arcCos = 0.25, -- cos(~75°): widest of the three, it is a full spin
			windup = 0.18,
			activeWindow = 0.14,
			recovery = 0.42,
			comboWindow = 0.00, -- chain ends here; index resets to 1
			staminaCost = 14,
		},
	},

	heavy = {
		damageMult = 2.20,
		range = MELEE + 4, -- 12
		arcCos = 0.10, -- cos(~84°): nearly a half-circle cleave
		windup = 0.42, -- long enough to be reacted to
		activeWindow = 0.16,
		recovery = 0.55,
		staminaCost = 22,
		maxComboIndexToChainFrom = 2,
		holdSeconds = 0.35,
	},

	block = {
		damageReduction = 0.65,
		parryWindow = 0.28,
		parryRiposteMult = 1.80,
		parryRiposteWindow = 1.20,
		parryStunSeconds = 1.20, -- matches Abilities.ShieldBash.stunSeconds
		directional = true,
		facingDot = 0.15, -- cos(~81°): the shield covers the front, not the flanks
		moveSpeedMult = 0.45,
		staminaCostPerParry = 10,
	},

	dodge = {
		distance = 18,
		speed = 34,
		invulnSeconds = 0.35,
		recovery = 0.25,
		cooldown = 0.90,
		staminaCost = 18,
	},

	ranged = {
		damageMult = 0.65, -- 70 * 0.65 ≈ 45, the legacy flat bow damage
		range = 140,
		arcCos = 0.93, -- cos(~21°): a tight aim cone
		windup = 0.30, -- draw the bow
		recovery = 0.25,
		cooldown = 0.80,
		projectile = "Longbow",
		staminaCost = 6,
		damageType = "Pierce" :: DamageType, -- a bow is Pierce, not the profile's Slash
	},

	stamina = {
		enabled = false,
		max = 100,
		regenPerSecond = 18,
		regenDelay = 0.60,
	},

	stagger = {
		interruptDamageFraction = 0.08, -- 8% of max HP in one hit breaks a windup
		seconds = 0.45,
	},

	playerAttacksHitAllies = true,
} :: HeroConfig

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
		weapon = "Sword",
		shield = true,
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
		weapon = "Spear",
		shield = true,
	},
	Pikeman = {
		damageType = "Pierce",
		armorClass = "Medium",
		attackType = "Melee",
		tags = { "spear", "infantry" },
		bonusVsTags = { cavalry = 2.0 },
		weapon = "Spear",
	},
	MenAtArms = {
		damageType = "Slash",
		armorClass = "Heavy",
		attackType = "Melee",
		tags = { "infantry" },
		weapon = "Sword",
		shield = true,
	},
	BatteringRam = {
		damageType = "Siege",
		armorClass = "Structure",
		attackType = "Melee",
		tags = { "siege" },
		weapon = "None",
	},
	Catapult = {
		damageType = "Siege",
		armorClass = "Light",
		attackType = "Ranged",
		tags = { "siege", "ranged" },
		bonusVsTags = { structure = 1.25 }, -- "structure" is the implicit tag all buildings carry
		projectile = "Stone",
		weapon = "None",
	},
	Trebuchet = {
		damageType = "Siege",
		armorClass = "Light", -- wooden frame: melee tears it apart if it gets close
		attackType = "Ranged",
		tags = { "siege", "ranged" },
		bonusVsTags = { structure = 1.6 }, -- dedicated wall-breaker
		projectile = "TrebuchetStone",
		weapon = "None",
	},
	Siege_Tower = {
		damageType = "Blunt",
		armorClass = "Structure", -- thick timber sheathing shrugs off arrows and blades
		attackType = "Melee",
		tags = { "siege", "transport" },
		weapon = "None",
	},
	Viking = {
		damageType = "Slash",
		armorClass = "Medium",
		attackType = "Melee",
		tags = { "infantry", "raider" },
		abilities = { "Berserk" },
		weapon = "Axe",
		shield = true,
	},
	Archer = {
		damageType = "Pierce",
		armorClass = "Light",
		attackType = "Ranged",
		tags = { "ranged" },
		projectile = "Arrow",
		weapon = "Bow",
	},
	Knight = {
		damageType = "Slash",
		armorClass = "Heavy",
		attackType = "Melee",
		tags = { "cavalry" },
		bonusVsTags = { ranged = 1.3, civilian = 1.3 },
		abilities = { "Trample" },
		weapon = "Sword",
		shield = true,
	},
	Monk = {
		damageType = "Magic",
		armorClass = "Unarmored",
		attackType = "Melee",
		tags = { "caster", "support" },
		abilities = { "Heal" },
		weapon = "Staff",
	},
	Priest = {
		damageType = "Magic",
		armorClass = "Unarmored",
		attackType = "Melee",
		tags = { "caster", "support", "civilian" },
		abilities = { "Heal" },
		weapon = "Staff",
	},
	Bard = {
		damageType = "Blunt",
		armorClass = "Unarmored",
		attackType = "Melee",
		tags = { "support" },
		abilities = { "BattleSong" },
		weapon = "Club",
	},
	Kern = {
		damageType = "Slash",
		armorClass = "Light",
		attackType = "Melee",
		tags = { "infantry", "skirmisher" },
		abilities = { "HitAndRun" },
		weapon = "Sword",
	},
	Ceithern = {
		damageType = "Pierce",
		armorClass = "Light",
		attackType = "Ranged",
		tags = { "ranged", "skirmisher" },
		projectile = "Javelin",
		bonusVsTags = { cavalry = 1.4 },
		weapon = "Javelin",
	},
	Bonnacht = {
		damageType = "Slash",
		armorClass = "Medium",
		attackType = "Melee",
		tags = { "infantry" },
		abilities = { "Ambush" },
		weapon = "Axe",
	},
	Gallowglass = {
		damageType = "Slash",
		armorClass = "Heavy",
		attackType = "Melee",
		tags = { "infantry", "elite" },
		abilities = { "ShieldBash" },
		weapon = "Axe", -- two-handed galloglass axe
		shield = true,
	},
	Fianna = {
		damageType = "Slash",
		armorClass = "Medium",
		attackType = "Melee",
		tags = { "infantry", "elite", "hero" },
		abilities = { "Berserk", "WarCry" },
		weapon = "Sword",
	},
	Slinger = {
		damageType = "Blunt",
		armorClass = "Light",
		attackType = "Ranged",
		tags = { "ranged" },
		projectile = "Stone",
		weapon = "Sling",
	},
	Longbowman = {
		damageType = "Pierce",
		armorClass = "Light",
		attackType = "Ranged",
		tags = { "ranged" },
		projectile = "Longbow",
		abilities = { "Volley" },
		weapon = "Bow",
	},
	Hobelar = {
		damageType = "Slash",
		armorClass = "Light",
		attackType = "Melee",
		tags = { "cavalry", "skirmisher" },
		bonusVsTags = { ranged = 1.3 },
		abilities = { "Trample", "HitAndRun" },
		weapon = "Spear", -- light lance
	},
	Druid = {
		damageType = "Magic",
		armorClass = "Light",
		attackType = "Ranged",
		tags = { "caster" },
		projectile = "MagicBolt",
		abilities = { "Heal" },
		weapon = "Staff",
	},
	Banshee = {
		damageType = "Magic",
		armorClass = "Unarmored",
		attackType = "Ranged",
		tags = { "caster" },
		projectile = "MagicBolt",
		abilities = { "Wail" },
		weapon = "None",
	},
	Wolfhound = {
		damageType = "Slash",
		armorClass = "Unarmored",
		attackType = "Melee",
		tags = { "beast" },
		abilities = { "PackHunter" },
		weapon = "None",
	},

	-- ── Hero hub rosters (Royal Assembly Hall / Sidhe Mound / Coastal Long-Port) ──
	High_King = {
		damageType = "Slash",
		armorClass = "Heavy",
		attackType = "Melee",
		tags = { "hero", "infantry" },
		abilities = { "WarCry", "ShieldWall" },
		weapon = "Sword",
		shield = true,
	},
	Celtic_Champion = {
		damageType = "Slash",
		armorClass = "Medium",
		attackType = "Melee",
		tags = { "hero", "infantry" },
		abilities = { "CelticFury", "Berserk" },
		weapon = "Spear", -- the Gáe Bolg
	},
	Brehon = {
		damageType = "Magic",
		armorClass = "Light",
		attackType = "Ranged",
		tags = { "hero", "caster", "support" },
		projectile = "MagicBolt",
		abilities = { "Heal", "WarCry" }, -- Binding Judgment ≈ WarCry morale shock
		weapon = "Staff",
	},
	Sidhe_Warden = {
		damageType = "Magic",
		armorClass = "Medium",
		attackType = "Melee",
		tags = { "mythical", "hero" },
		abilities = { "Ambush", "CelticFury" }, -- Otherworld Step first-strike
		weapon = "Spear",
	},
	Cu_Sidhe = {
		damageType = "Slash",
		armorClass = "Unarmored",
		attackType = "Melee",
		tags = { "mythical", "beast" },
		bonusVsTags = { ranged = 1.3, civilian = 1.2 },
		abilities = { "PackHunter", "HitAndRun" },
		weapon = "None",
	},
	Sea_Reaver = {
		damageType = "Slash",
		armorClass = "Medium",
		attackType = "Melee",
		tags = { "hero", "infantry", "raider" },
		bonusVsTags = { ranged = 1.25 },
		abilities = { "Berserk", "Trample" }, -- Tidal Charge ≈ heavier charges
		weapon = "Axe",
	},
	Selkie = {
		damageType = "Magic",
		armorClass = "Unarmored",
		attackType = "Ranged",
		tags = { "mythical", "caster", "healer" },
		projectile = "MagicBolt",
		abilities = { "Heal", "Wail" }, -- Mend the Tide / Storm Wail
		weapon = "None",
	},
	Oillipheist = {
		damageType = "Magic",
		armorClass = "Heavy", -- scaled hide
		attackType = "Ranged",
		tags = { "mythical", "flying", "beast" },
		bonusVsTags = { structure = 1.3 }, -- Otherworld fire chews through roofs
		projectile = "WyrmFire",
		abilities = { "Wail" }, -- Terror ≈ the Banshee's morale shock
		weapon = "None",
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
	Siege = { damageType = "Siege", armorClass = "Structure", attackType = "Melee", tags = { "siege" }, weapon = "None" },
	["Hero Caster"] = { damageType = "Magic", armorClass = "Light", attackType = "Ranged", tags = { "hero", "caster" }, projectile = "MagicBolt", weapon = "Staff" },
	["Hero Leader"] = { damageType = "Slash", armorClass = "Heavy", attackType = "Melee", tags = { "hero" }, weapon = "Sword", shield = true },
	Mythical = { damageType = "Magic", armorClass = "Light", attackType = "Melee", tags = { "mythical" } },
	["War Beast"] = { damageType = "Slash", armorClass = "Unarmored", attackType = "Melee", tags = { "beast" }, weapon = "None" },
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

-- Visual weapon for a profile: explicit if set, otherwise inferred from
-- attack type + damage type. Civilians and beasts get none.
function CombatConfig.getWeaponKind(profile: UnitCombatProfile): WeaponKind
	if profile.weapon then
		return profile.weapon :: WeaponKind
	end
	if CombatConfig.hasTag(profile, "civilian") or CombatConfig.hasTag(profile, "beast") then
		return "None"
	end
	if profile.attackType == "Ranged" then
		return if profile.damageType == "Magic" then "Staff" else "Bow"
	end
	if profile.damageType == "Pierce" then
		return "Spear"
	elseif profile.damageType == "Blunt" then
		return "Club"
	end
	return "Sword"
end

return CombatConfig
