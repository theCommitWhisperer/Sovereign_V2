--!strict
-- UnitsData: All unit definitions. Pure data — one FLAT record per unit.
--
-- SCHEMA (flat, no nested tables):
--   display_name          player-facing name (may be faction-flavored)
--   subtype               classification used by combat profiles, worker checks
--                         and weapon visuals ("Worker", "Infantry", "Ranged", ...)
--   faction               culture the unit belongs to ("Neutral" = all factions)
--   description           flavor / tooltip text
--   model_name?           override for the Assets/Units/<name> rig key
--                         (defaults to the unit's table key, e.g. "Peasant")
--   cost                  { [resource]: amount } to train
--   training_time_seconds seconds in the training queue
--   population_cost       housing/population used
--   max_health            hit points
--   move_speed            meters per second (WalkSpeed = move_speed * 16)
--   attack_damage         damage per hit (0 = non-combatant / support)
--   attack_speed          seconds between attacks
--   attack_range          meters (combat converts to studs)
--   armor                 flat damage reduction
--   sight_range           vision distance
--   carry_capacity        resources carried per trip (workers)
--   can_swim?             can cross water
--   can_fly?              airborne: MovementSystem skips ground pathfinding and
--                         flies the unit straight to its target over walls
--   tags?                 free-form labels ("civilian", "elite", ...)
--   special_abilities?    ability names (see CombatConfig.Abilities)
--
-- IMPORTANT: table KEYS are stable internal IDs. They are referenced by
-- BuildingsData.can_train_units, AI/spawn systems, CombatConfig.UnitProfiles
-- and the Assets/Units/<ID> model folders. Rename display_name freely; never
-- rename a key without migrating every reference.

export type UnitData = {
	display_name: string,
	subtype: string,
	faction: string,
	description: string,
	model_name: string?,
	cost: { [string]: number },
	training_time_seconds: number,
	population_cost: number,
	max_health: number,
	move_speed: number,
	attack_damage: number,
	attack_speed: number,
	attack_range: number,
	armor: number,
	sight_range: number,
	carry_capacity: number,
	can_swim: boolean?,
	can_fly: boolean?,
	tags: { string }?,
	special_abilities: { string }?,
}

-- Everything optional except identity; the helper fills shared defaults so each
-- record only lists what makes the unit different.
type UnitSpec = {
	display_name: string,
	subtype: string,
	faction: string?,
	description: string?,
	model_name: string?,
	cost: { [string]: number }?,
	training_time_seconds: number?,
	population_cost: number?,
	max_health: number?,
	move_speed: number?,
	attack_damage: number?,
	attack_speed: number?,
	attack_range: number?,
	armor: number?,
	sight_range: number?,
	carry_capacity: number?,
	can_swim: boolean?,
	can_fly: boolean?,
	tags: { string }?,
	special_abilities: { string }?,
}

local function makeUnit(spec: UnitSpec): UnitData
	return {
		display_name = spec.display_name,
		subtype = spec.subtype,
		faction = spec.faction or "Neutral",
		description = spec.description or "",
		model_name = spec.model_name,
		cost = spec.cost or {},
		training_time_seconds = spec.training_time_seconds or 0,
		population_cost = spec.population_cost or 0,
		max_health = spec.max_health or 50,
		move_speed = spec.move_speed or 1.0,
		attack_damage = spec.attack_damage or 0,
		attack_speed = spec.attack_speed or 1.0,
		attack_range = spec.attack_range or 1,
		armor = spec.armor or 0,
		sight_range = spec.sight_range or 60,
		carry_capacity = spec.carry_capacity or 0,
		can_swim = spec.can_swim,
		can_fly = spec.can_fly,
		tags = spec.tags,
		special_abilities = spec.special_abilities,
	}
end

local UnitsData: { [string]: UnitData } = {}

-- ═══════════════════════════════════════════════════════════════════════════
-- CORE / HERO
-- ═══════════════════════════════════════════════════════════════════════════

UnitsData.King = makeUnit({
	display_name = "King",
	subtype = "Hero",
	description = "The player's main hero unit. If the King dies, you lose.",
	max_health = 500,
	move_speed = 1.5,
	attack_damage = 30,
	attack_speed = 2.0,
	attack_range = 3,
	armor = 10,
})

-- ═══════════════════════════════════════════════════════════════════════════
-- WORKERS (Peasant is trainable; the rest are job transforms of the Peasant)
-- ═══════════════════════════════════════════════════════════════════════════

UnitsData.Peasant = makeUnit({
	display_name = "Peasant",
	subtype = "Worker",
	description = "Basic worker unit. Can gather resources and construct buildings.",
	tags = { "civilian", "worker" },
	cost = { Food = 5 },
	training_time_seconds = 5,
	population_cost = 1,
	max_health = 25,
	attack_damage = 2,
	attack_speed = 2.5,
	attack_range = 2,
	carry_capacity = 10,
})

UnitsData.Woodcutter = makeUnit({
	display_name = "Woodcutter",
	subtype = "Worker",
	description = "A peasant specialized in chopping wood.",
	max_health = 25,
	attack_damage = 2,
	carry_capacity = 15,
})

UnitsData.Stonemason = makeUnit({
	display_name = "Stonemason",
	subtype = "Worker",
	description = "A peasant specialized in mining stone.",
	max_health = 30,
	move_speed = 0.9,
	attack_damage = 3,
	attack_speed = 1.2,
	armor = 1,
	carry_capacity = 20,
})

UnitsData.Farmer = makeUnit({
	display_name = "Farmer",
	subtype = "Worker",
	description = "A peasant specialized in gathering food.",
	max_health = 25,
	attack_damage = 1,
	carry_capacity = 25,
})

UnitsData.Miner = makeUnit({
	display_name = "Miner",
	subtype = "Worker",
	description = "Specialized in mining iron and coal from underground deposits.",
	max_health = 30,
	move_speed = 0.9,
	attack_damage = 3,
	attack_speed = 1.5,
	armor = 1,
	carry_capacity = 15,
})

UnitsData.Fisherman = makeUnit({
	display_name = "Fisherman",
	subtype = "Worker",
	description = "Catches fish from nearby waters to feed the settlement.",
	max_health = 25,
	attack_damage = 2,
	carry_capacity = 20,
	can_swim = true,
})

UnitsData.Smelter = makeUnit({
	display_name = "Smelter",
	subtype = "Worker",
	description = "Smelts iron ore into iron bars at the furnace.",
	max_health = 30,
	move_speed = 0.9,
	attack_damage = 3,
	attack_speed = 1.2,
	armor = 2,
	carry_capacity = 15,
})

UnitsData.Blacksmith = makeUnit({
	display_name = "Blacksmith",
	subtype = "Worker",
	description = "Forges weapons and armor from iron bars.",
	max_health = 35,
	move_speed = 0.9,
	attack_damage = 5,
	attack_speed = 1.3,
	armor = 3,
	carry_capacity = 20,
})

UnitsData.Carpenter = makeUnit({
	display_name = "Carpenter",
	subtype = "Worker",
	description = "Crafts furniture and wooden goods from lumber.",
	max_health = 28,
	attack_damage = 3,
	attack_speed = 1.2,
	armor = 1,
	carry_capacity = 15,
})

UnitsData.Tanner = makeUnit({
	display_name = "Tanner",
	subtype = "Worker",
	description = "Processes animal hides into leather for armor and goods.",
	max_health = 25,
	attack_damage = 2,
	armor = 1,
	carry_capacity = 12,
})

UnitsData.Miller = makeUnit({
	display_name = "Miller",
	subtype = "Worker",
	description = "Grinds grain into flour at the mill.",
	max_health = 26,
	attack_damage = 2,
	carry_capacity = 18,
})

UnitsData.Baker = makeUnit({
	display_name = "Baker",
	subtype = "Worker",
	description = "Bakes bread and pastries to feed the people.",
	max_health = 25,
	attack_damage = 2,
	carry_capacity = 15,
})

UnitsData.Brewer = makeUnit({
	display_name = "Brewer",
	subtype = "Worker",
	description = "Brews ale and spirits to boost morale.",
	max_health = 26,
	attack_damage = 2,
	carry_capacity = 18,
})

UnitsData.Merchant = makeUnit({
	display_name = "Merchant",
	subtype = "Worker",
	description = "Manages trade and commerce at the marketplace.",
	max_health = 25,
	move_speed = 1.2,
	attack_damage = 2,
	carry_capacity = 25,
})

UnitsData.Trader = makeUnit({
	display_name = "Trader",
	subtype = "Worker",
	description = "Manages international trade at the trading post.",
	max_health = 26,
	move_speed = 1.3,
	attack_damage = 2,
	carry_capacity = 30,
})

UnitsData.Innkeeper = makeUnit({
	display_name = "Innkeeper",
	subtype = "Worker",
	description = "Serves food, drink, and lodging at the inn or tavern.",
	max_health = 25,
	attack_damage = 2,
	carry_capacity = 15,
})

UnitsData.Scribe = makeUnit({
	display_name = "Scribe",
	subtype = "Worker",
	description = "Copies and illuminates manuscripts, preserving knowledge.",
	max_health = 22,
	move_speed = 0.9,
	attack_damage = 1,
	attack_speed = 0.8,
	carry_capacity = 8,
})

UnitsData.Priest = makeUnit({
	display_name = "Priest",
	subtype = "Worker",
	description = "Leads worship and provides spiritual guidance at churches and chapels.",
	max_health = 24,
	attack_damage = 1,
	attack_speed = 0.8,
	carry_capacity = 5,
})

UnitsData.Administrator = makeUnit({
	display_name = "Administrator",
	subtype = "Worker",
	description = "Manages administrative affairs at the town hall.",
	max_health = 26,
	attack_damage = 2,
	carry_capacity = 10,
})

-- ═══════════════════════════════════════════════════════════════════════════
-- STANDARD CORPS (available to every faction)
-- Archers, Pikemen, Men-at-Arms, Knights + siege
-- ═══════════════════════════════════════════════════════════════════════════

UnitsData.Spearman = makeUnit({
	display_name = "Levy Spearman",
	subtype = "Infantry",
	description = "Basic levied infantry with spear and shield. Effective against cavalry.",
	tags = { "military", "infantry", "spear" },
	cost = { Food = 10, Gold = 5 },
	training_time_seconds = 10,
	population_cost = 1,
	max_health = 50,
	move_speed = 1.2,
	attack_damage = 10,
	attack_speed = 1.5,
	attack_range = 2,
	armor = 2,
})

UnitsData.Pikeman = makeUnit({
	display_name = "Pikeman",
	subtype = "Infantry",
	description = "Disciplined soldier with a long pike. Devastating against charging cavalry.",
	tags = { "military", "infantry", "spear" },
	cost = { Food = 12, Gold = 10, Wood = 5 },
	training_time_seconds = 12,
	population_cost = 1,
	max_health = 60,
	move_speed = 1.1,
	attack_damage = 12,
	attack_speed = 1.8,
	attack_range = 3,
	armor = 3,
	special_abilities = { "Brace" },
})

UnitsData.MenAtArms = makeUnit({
	display_name = "Man-at-Arms",
	subtype = "Infantry",
	description = "Professional soldier in mail with sword and shield. The backbone of any army.",
	tags = { "military", "infantry" },
	cost = { Food = 15, Gold = 20 },
	training_time_seconds = 15,
	population_cost = 1,
	max_health = 80,
	move_speed = 1.2,
	attack_damage = 15,
	attack_speed = 1.5,
	attack_range = 2,
	armor = 4,
})

UnitsData.Archer = makeUnit({
	display_name = "Archer",
	subtype = "Ranged",
	description = "Ranged unit with a shortbow. Cheap and effective at a distance.",
	tags = { "military", "ranged" },
	cost = { Food = 15, Gold = 10, Wood = 5 },
	training_time_seconds = 12,
	population_cost = 1,
	max_health = 30,
	move_speed = 1.3,
	attack_damage = 8,
	attack_speed = 2.0,
	attack_range = 15,
})

UnitsData.Knight = makeUnit({
	display_name = "Knight",
	subtype = "Cavalry",
	description = "Armored heavy cavalry. Powerful charge, expensive to field.",
	tags = { "military", "cavalry", "heavy" },
	cost = { Food = 30, Gold = 40 },
	training_time_seconds = 20,
	population_cost = 2,
	max_health = 100,
	move_speed = 2.0,
	attack_damage = 30,
	attack_speed = 1.2,
	attack_range = 2,
	armor = 5,
})

-- ═══════════════════════════════════════════════════════════════════════════
-- SIEGE (baseline entries; the siege system builds on these)
-- ═══════════════════════════════════════════════════════════════════════════

UnitsData.BatteringRam = makeUnit({
	display_name = "Battering Ram",
	subtype = "Siege",
	description = "Slow wooden ram. Crushes gates and walls; nearly useless against troops.",
	tags = { "military", "siege" },
	cost = { Wood = 100, Gold = 50 },
	training_time_seconds = 40,
	population_cost = 3,
	max_health = 400,
	move_speed = 0.6,
	attack_damage = 60,
	attack_speed = 4.0,
	attack_range = 3,
	armor = 8,
})

UnitsData.Catapult = makeUnit({
	display_name = "Catapult",
	subtype = "Siege",
	description = "Hurls stones over long range. Demolishes buildings from afar.",
	tags = { "military", "siege" },
	cost = { Wood = 150, Gold = 100 },
	training_time_seconds = 50,
	population_cost = 3,
	max_health = 200,
	move_speed = 0.5,
	attack_damage = 80,
	attack_speed = 6.0,
	attack_range = 35,
	armor = 4,
	sight_range = 80,
})

UnitsData.Trebuchet = makeUnit({
	display_name = "Trebuchet",
	subtype = "Siege",
	description = "Counterweight engine of terrifying reach. Reduces castles to rubble, "
		.. "but must all but stop to loose — nearly helpless up close.",
	tags = { "military", "siege" },
	cost = { Wood = 220, Gold = 160, Iron_Bars = 10 },
	training_time_seconds = 70,
	population_cost = 4,
	max_health = 220,
	move_speed = 0.3, -- immobile-while-firing flavor: it barely crawls
	attack_damage = 120,
	attack_speed = 9.0,
	attack_range = 55,
	armor = 3,
	sight_range = 100,
})

UnitsData.Siege_Tower = makeUnit({
	display_name = "Siege Tower",
	subtype = "Siege",
	description = "Rolling wooden tower. No weapon of its own, but push it against an "
		.. "enemy wall and nearby foot soldiers clamber over to the far side.",
	tags = { "military", "siege", "transport" },
	cost = { Wood = 180, Gold = 60 },
	training_time_seconds = 55,
	population_cost = 4,
	max_health = 700,
	move_speed = 0.5,
	attack_damage = 0, -- transport, not a weapon
	attack_speed = 4.0,
	attack_range = 2,
	armor = 10,
	sight_range = 70,
	special_abilities = { "Wall Ferry" },
})

-- ═══════════════════════════════════════════════════════════════════════════
-- NORSE RAIDERS (NPC "Viking" faction)
-- ═══════════════════════════════════════════════════════════════════════════

UnitsData.Viking = makeUnit({
	display_name = "Norse Raider",
	subtype = "Infantry",
	faction = "Viking",
	description = "A fierce Viking raider from across the sea. Strong and tough.",
	tags = { "military", "infantry", "raider" },
	cost = { Food = 10, Gold = 100 },
	training_time_seconds = 10,
	population_cost = 1,
	max_health = 80,
	move_speed = 1.2,
	attack_damage = 20,
	attack_speed = 1.5,
	attack_range = 2,
	armor = 3,
	special_abilities = { "Berserk" },
})

-- ═══════════════════════════════════════════════════════════════════════════
-- IRISH ROSTER (Gaelic Ireland: clansmen, gallowglass, the Fianna)
-- ═══════════════════════════════════════════════════════════════════════════

UnitsData.Monk = makeUnit({
	display_name = "Irish Monk",
	subtype = "Religious",
	faction = "Irish",
	description = "Monk of the Irish monasteries. Can heal units and provide blessings.",
	tags = { "civilian", "religious", "healer" },
	cost = { Gold = 50, Food = 1 },
	training_time_seconds = 30,
	max_health = 40,
	move_speed = 2.5,
	attack_damage = 0,
	attack_speed = 0,
	attack_range = 0,
	sight_range = 50,
	special_abilities = { "Heal", "Bless" },
})

UnitsData.Bard = makeUnit({
	display_name = "Celtic Bard",
	subtype = "Support",
	faction = "Irish",
	description = "Celtic bard. Boosts morale of nearby troops and can demoralize enemies.",
	tags = { "civilian", "support", "morale" },
	cost = { Gold = 75, Food = 1 },
	training_time_seconds = 25,
	max_health = 35,
	move_speed = 3.0,
	attack_damage = 0,
	attack_speed = 0,
	attack_range = 0,
	special_abilities = { "Battle Song", "Inspire", "Demoralize Enemy" },
})

UnitsData.Kern = makeUnit({
	display_name = "Kern Skirmisher",
	subtype = "Light Infantry",
	faction = "Irish",
	description = "Light Irish skirmisher armed with javelins and a short sword.",
	tags = { "military", "infantry", "light", "skirmisher" },
	cost = { Gold = 20, Food = 1, Weapons = 1 },
	training_time_seconds = 20,
	max_health = 60,
	move_speed = 4.0,
	attack_damage = 8,
	attack_speed = 2.0,
	attack_range = 20, -- javelin range
	armor = 1,
	sight_range = 70,
	special_abilities = { "Javelin Throw", "Quick Retreat" },
})

UnitsData.Ceithern = makeUnit({
	display_name = "Clan Militia",
	subtype = "Light Infantry",
	faction = "Irish",
	description = "Lightly armed clansmen raised from the tuath. Good for raids and ambushes.",
	tags = { "military", "infantry", "light", "militia" },
	cost = { Gold = 15, Food = 1 },
	training_time_seconds = 18,
	max_health = 50,
	move_speed = 3.8,
	attack_damage = 6,
	attack_speed = 2.2,
	attack_range = 3,
	special_abilities = { "Ambush" },
})

UnitsData.Bonnacht = makeUnit({
	display_name = "Irish Swordsman",
	subtype = "Medium Infantry",
	faction = "Irish",
	description = "Professional Irish soldier with sword and shield, billeted on the clans.",
	tags = { "military", "infantry", "medium" },
	cost = { Gold = 35, Food = 1, Weapons = 2 },
	training_time_seconds = 25,
	max_health = 90,
	move_speed = 3.2,
	attack_damage = 12,
	attack_speed = 2.0,
	attack_range = 3,
	armor = 3,
	sight_range = 65,
	special_abilities = { "Shield Bash" },
})

UnitsData.Gallowglass = makeUnit({
	display_name = "Gallowglass",
	subtype = "Heavy Infantry",
	faction = "Irish",
	description = "Elite Norse-Gael mercenary in mail, swinging a two-handed axe.",
	tags = { "military", "infantry", "heavy", "elite" },
	cost = { Gold = 60, Food = 2, Weapons = 3, Iron_Bars = 2 },
	training_time_seconds = 35,
	max_health = 150,
	move_speed = 2.5,
	attack_damage = 20,
	attack_speed = 2.5,
	attack_range = 4, -- two-handed axe reach
	armor = 5,
	special_abilities = { "Cleave", "Intimidate" },
})

UnitsData.Fianna = makeUnit({
	display_name = "Fianna Warrior",
	subtype = "Elite Infantry",
	faction = "Irish",
	description = "Legendary warrior band of Irish myth — the war band of Fionn mac Cumhaill.",
	tags = { "military", "infantry", "elite", "legendary" },
	cost = { Gold = 80, Food = 2, Weapons = 3, Honor = 10 },
	training_time_seconds = 40,
	max_health = 120,
	move_speed = 3.5,
	attack_damage = 18,
	attack_speed = 1.8,
	attack_range = 3,
	armor = 4,
	sight_range = 80,
	special_abilities = { "Heroic Charge", "Rally", "Berserk" },
})

UnitsData.Slinger = makeUnit({
	display_name = "Slinger",
	subtype = "Ranged Infantry",
	faction = "Irish",
	description = "Cheap ranged unit with a sling and a good rate of fire.",
	tags = { "military", "ranged", "infantry", "light" },
	cost = { Gold = 15, Food = 1 },
	training_time_seconds = 15,
	max_health = 40,
	move_speed = 3.5,
	attack_damage = 6,
	attack_speed = 1.5,
	attack_range = 25,
	sight_range = 90,
	special_abilities = { "Quick Shot" },
})

UnitsData.Longbowman = makeUnit({
	display_name = "Longbowman",
	subtype = "Ranged Infantry",
	faction = "Irish",
	description = "Archer with a great yew longbow. Excellent range and damage.",
	tags = { "military", "ranged", "infantry" },
	cost = { Gold = 30, Food = 1, Wood = 5 },
	training_time_seconds = 22,
	max_health = 55,
	move_speed = 3.0,
	attack_damage = 10,
	attack_speed = 2.5,
	attack_range = 40,
	armor = 1,
	sight_range = 100,
	special_abilities = { "Volley", "Fire Arrow" },
})

UnitsData.Light_Cavalry = makeUnit({
	display_name = "Light Cavalry",
	subtype = "Light Cavalry",
	faction = "Irish",
	description = "Fast unarmored horsemen for scouting and raids.",
	tags = { "military", "cavalry", "light", "scout" },
	cost = { Gold = 45, Food = 2, Horses = 1 },
	training_time_seconds = 30,
	max_health = 80,
	move_speed = 7.0,
	attack_damage = 10,
	attack_speed = 2.0,
	attack_range = 3,
	armor = 2,
	sight_range = 100,
	special_abilities = { "Scout", "Hit and Run" },
})

UnitsData.Hobelar = makeUnit({
	display_name = "Hobelar Rider",
	subtype = "Medium Cavalry",
	faction = "Irish",
	description = "Irish light horseman on a hobby pony. Can dismount to fight.",
	tags = { "military", "cavalry", "medium" },
	cost = { Gold = 55, Food = 2, Horses = 1, Weapons = 2 },
	training_time_seconds = 32,
	max_health = 100,
	move_speed = 6.0,
	attack_damage = 14,
	attack_speed = 2.0,
	attack_range = 3,
	armor = 3,
	sight_range = 80,
	special_abilities = { "Charge", "Trample" },
})

-- ═══════════════════════════════════════════════════════════════════════════
-- IRISH HEROES & MYTH
-- ═══════════════════════════════════════════════════════════════════════════

UnitsData.Celtic_Champion = makeUnit({
	display_name = "Celtic Champion",
	subtype = "Hero",
	faction = "Irish",
	description = "Legendary Celtic hero, inspired by Cú Chulainn — the Hound of Ulster.",
	tags = { "military", "hero", "unique" },
	cost = { Gold = 200, Food = 3, Honor = 50 },
	training_time_seconds = 60,
	max_health = 300,
	move_speed = 3.8,
	attack_damage = 35,
	attack_speed = 1.5,
	attack_range = 4,
	armor = 7,
	sight_range = 90,
	special_abilities = { "Warp Spasm", "Battle Fury", "Heroic Leap", "Challenge" },
})

UnitsData.Druid = makeUnit({
	display_name = "Druid",
	subtype = "Hero Caster",
	faction = "Irish",
	description = "Powerful Celtic druid wielding nature magic.",
	tags = { "military", "hero", "caster", "support" },
	cost = { Gold = 150, Food = 2, Honor = 30 },
	training_time_seconds = 50,
	max_health = 100,
	move_speed = 2.8,
	attack_damage = 5,
	attack_speed = 3.0,
	attack_range = 20, -- magic range
	armor = 2,
	sight_range = 100,
	special_abilities = { "Lightning Strike", "Nature's Wrath", "Heal", "Entangle", "Summon Wolves" },
})

UnitsData.High_King = makeUnit({
	display_name = "High King of Ireland",
	subtype = "Hero Leader",
	faction = "Irish",
	description = "The High King crowned at Tara, heir of Brian Boru. Powerful leader unit.",
	tags = { "military", "hero", "unique", "king" },
	cost = { Gold = 500, Food = 5, Honor = 100 },
	training_time_seconds = 90,
	max_health = 500,
	move_speed = 3.0,
	attack_damage = 30,
	attack_speed = 2.0,
	attack_range = 3,
	armor = 10,
	sight_range = 100,
	special_abilities = { "Royal Decree", "Inspire Army", "Divine Right", "Summon the Fianna" },
})

UnitsData.Banshee = makeUnit({
	display_name = "Banshee",
	subtype = "Mythical",
	faction = "Irish",
	description = "Wailing spirit of Irish legend. Causes fear and lowers enemy morale.",
	tags = { "military", "mythical", "fear" },
	cost = { Gold = 100, Honor = 20 },
	training_time_seconds = 45,
	max_health = 60,
	move_speed = 4.0,
	attack_damage = 0,
	attack_speed = 5.0,
	attack_range = 30,
	sight_range = 80,
	special_abilities = { "Wail", "Terror", "Death Omen" },
})

UnitsData.Wolfhound = makeUnit({
	display_name = "Irish Wolfhound",
	subtype = "War Beast",
	faction = "Irish",
	description = "Great Irish war hound. Fast, and deadly against light units.",
	tags = { "military", "beast", "fast" },
	cost = { Gold = 25, Food = 1 },
	training_time_seconds = 20,
	max_health = 40,
	move_speed = 8.0,
	attack_damage = 8,
	attack_speed = 1.5,
	attack_range = 2,
	sight_range = 80,
	special_abilities = { "Track", "Howl", "Pack Hunter" },
})

-- ═══════════════════════════════════════════════════════════════════════════
-- HERO HUB ROSTERS (original units — each trainable ONLY at its hub building)
--   Royal Assembly Hall → High_King, Celtic_Champion, Fianna, Brehon
--   Sidhe Mound         → Druid, Banshee, Sidhe_Warden, Cu_Sidhe
--   Coastal Long-Port   → Gallowglass, Sea_Reaver, Selkie
-- ═══════════════════════════════════════════════════════════════════════════

UnitsData.Brehon = makeUnit({
	display_name = "High Brehon",
	subtype = "Hero Caster",
	faction = "Irish",
	description = "Lawspeaker of the assembly at Tara. His judgments bind friend and foe alike.",
	tags = { "military", "hero", "caster", "support" },
	cost = { Gold = 180, Food = 2, Honor = 40 },
	training_time_seconds = 55,
	population_cost = 1,
	max_health = 140,
	move_speed = 2.8,
	attack_damage = 8,
	attack_speed = 2.5,
	attack_range = 18,
	armor = 3,
	sight_range = 90,
	special_abilities = { "Binding Judgment", "Oath of Kings", "Heal" },
})

UnitsData.Sidhe_Warden = makeUnit({
	display_name = "Sídhe Warden",
	subtype = "Mythical",
	faction = "Irish",
	description = "Sentinel of the hollow hills. Steps out of the Otherworld to strike the first blow.",
	tags = { "military", "mythical", "elite" },
	cost = { Gold = 140, Honor = 30 },
	training_time_seconds = 50,
	population_cost = 1,
	max_health = 180,
	move_speed = 3.6,
	attack_damage = 22,
	attack_speed = 1.8,
	attack_range = 3,
	armor = 5,
	sight_range = 90,
	special_abilities = { "Otherworld Step", "Faerie Ward" },
})

UnitsData.Cu_Sidhe = makeUnit({
	display_name = "Cú Sídhe",
	subtype = "Mythical",
	faction = "Irish",
	description = "Spectral hound of the fairy mounds. Hunts in packs and melts back into the mist.",
	tags = { "military", "mythical", "beast", "fast" },
	cost = { Gold = 60, Honor = 10 },
	training_time_seconds = 30,
	population_cost = 1,
	max_health = 70,
	move_speed = 8.5,
	attack_damage = 12,
	attack_speed = 1.4,
	attack_range = 2,
	armor = 1,
	sight_range = 100,
	special_abilities = { "Spectral Howl", "Pack Hunter", "Hit and Run" },
})

UnitsData.Sea_Reaver = makeUnit({
	display_name = "Norse-Gael Sea-Reaver",
	subtype = "Hero",
	faction = "Irish",
	description = "Half-Norse champion of the long-port. Leads boarding parties from the surf.",
	tags = { "military", "hero", "infantry", "raider" },
	cost = { Gold = 160, Food = 2, Weapons = 3, Honor = 35 },
	training_time_seconds = 55,
	population_cost = 1,
	max_health = 260,
	move_speed = 3.4,
	attack_damage = 28,
	attack_speed = 1.6,
	attack_range = 3,
	armor = 6,
	sight_range = 85,
	can_swim = true,
	special_abilities = { "Boarding Fury", "Tidal Charge", "Berserk" },
})

UnitsData.Oillipheist = makeUnit({
	display_name = "Oilliphéist, Wyrm of the Otherworld",
	subtype = "Mythical",
	faction = "Irish",
	description = "The great serpent of Irish legend that gouged the Shannon with its body. "
		.. "Called up through the Sídhe mound, it flies over walls and armies alike and "
		.. "scours stone with Otherworld fire.",
	tags = { "military", "mythical", "flying", "legendary" },
	cost = { Gold = 800, Food = 5, Honor = 150 },
	training_time_seconds = 120,
	population_cost = 5,
	max_health = 900,
	move_speed = 3.0,
	attack_damage = 45,
	attack_speed = 3.0,
	attack_range = 25, -- breath of Otherworld fire
	armor = 8,
	sight_range = 130,
	can_fly = true,
	special_abilities = { "Otherworld Fire", "Terror" },
})

UnitsData.Selkie = makeUnit({
	display_name = "Selkie Shorecaller",
	subtype = "Mythical",
	faction = "Irish",
	description = "Seal-folk mystic of the coast. Mends wounds with sea mist and wails storms at foes.",
	tags = { "military", "mythical", "caster", "healer" },
	cost = { Gold = 120, Honor = 25 },
	training_time_seconds = 45,
	population_cost = 1,
	max_health = 90,
	move_speed = 3.2,
	attack_damage = 6,
	attack_speed = 2.8,
	attack_range = 20,
	armor = 1,
	sight_range = 95,
	can_swim = true,
	special_abilities = { "Sea Mist", "Mend the Tide", "Storm Wail" },
})

return UnitsData
