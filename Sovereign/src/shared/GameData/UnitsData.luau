--!strict
-- UnitsData: Contains all unit definitions for the game.

local UnitsData = {}

export type UnitData = {
	type: string,
	subtype: string?,
	faction: string?,
	cost: { [string]: number },
	training_time_seconds: number?,
	tags: { string }?,
	health: {
		max_health: number,
	},
	movement: {
		speed_meters_per_second: number,
		can_swim: boolean?,
		can_climb: boolean?,
	},
	carry_capacity: number?,
	combat: {
		attack_damage: number,
		attack_speed: number, -- Corresponds to attack_cooldown
		attack_range: number, -- in meters
		armor: number,
	}?,
	population_cost: number?,
	sight_range: number?,
	special_abilities: { string }?,
	description: string?,
}

UnitsData.King = {
	type = "Unit",
	subtype = "Hero",
	faction = "Neutral",
	description = "The player's main hero unit. If the King dies, you lose.",
	cost = { Gold = 0 },
	training_time_seconds = 0,
	health = {
		max_health = 500,
	},
	movement = {
		speed_meters_per_second = 1.5,
		can_swim = false,
		can_climb = false,
	},
	carry_capacity = 0,
	combat = {
		attack_damage = 30,
		attack_speed = 2.0,
		attack_range = 3,
		armor = 10,
	},
	population_cost = 0,
} :: UnitData

UnitsData.Peasant = {
	type = "Unit",
	subtype = "Worker",
	faction = "Neutral",
	tags = { "civilian", "worker" },
	description = "Basic worker unit. Can gather resources and construct buildings.",
	cost = {
		Food = 5,
	},
	training_time_seconds = 5,
	health = {
		max_health = 25,
	},
	movement = {
		speed_meters_per_second = 1.0,
		can_swim = false,
		can_climb = false,
	},
	carry_capacity = 10,
	combat = {
		attack_damage = 2,
		attack_speed = 2.5,
		attack_range = 2,
		armor = 0,
	},
	population_cost = 1,
} :: UnitData

UnitsData.Woodcutter = {
	type = "Unit",
	subtype = "Worker",
	faction = "Neutral",
	description = "A peasant specialized in chopping wood.",
	cost = { Food = 0 },
	training_time_seconds = 0,
	health = {
		max_health = 25,
	},
	movement = {
		speed_meters_per_second = 1.0,
		can_swim = false,
		can_climb = false,
	},
	carry_capacity = 15,
	combat = {
		attack_damage = 2,
		attack_speed = 1.0,
		attack_range = 1,
		armor = 0,
	},
	population_cost = 0,
} :: UnitData

UnitsData.Stonemason = {
	type = "Unit",
	subtype = "Worker",
	faction = "Neutral",
	description = "A peasant specialized in mining stone.",
	cost = { Food = 0 },
	training_time_seconds = 0,
	health = {
		max_health = 30,
	},
	movement = {
		speed_meters_per_second = 0.9,
		can_swim = false,
		can_climb = false,
	},
	carry_capacity = 20,
	combat = {
		attack_damage = 3,
		attack_speed = 1.2,
		attack_range = 1,
		armor = 1,
	},
	population_cost = 0,
} :: UnitData

UnitsData.Farmer = {
	type = "Unit",
	subtype = "Worker",
	faction = "Neutral",
	description = "A peasant specialized in gathering food.",
	cost = { Food = 0 },
	training_time_seconds = 0,
	health = {
		max_health = 25,
	},
	movement = {
		speed_meters_per_second = 1.0,
		can_swim = false,
		can_climb = false,
	},
	carry_capacity = 25,
	combat = {
		attack_damage = 1,
		attack_speed = 1.0,
		attack_range = 1,
		armor = 0,
	},
	population_cost = 0,
} :: UnitData

UnitsData.Spearman = {
	type = "Unit",
	subtype = "Infantry",
	faction = "Neutral",
	description = "Basic infantry unit, effective against cavalry.",
	cost = {
		Food = 10,
		Gold = 5,
	},
	training_time_seconds = 10,
	health = {
		max_health = 50,
	},
	movement = {
		speed_meters_per_second = 1.2,
		can_swim = false,
		can_climb = false,
	},
	carry_capacity = 0,
	combat = {
		attack_damage = 10,
		attack_speed = 1.5,
		attack_range = 2,
		armor = 2,
	},
	population_cost = 1,
} :: UnitData

UnitsData.Viking = {
	type = "Unit",
	subtype = "Infantry",
	faction = "Viking",
	description = "A fierce raider from the north. Strong and tough.",
	cost = {
		Food = 10,
		Gold = 100,
	},
	training_time_seconds = 10,
	health = {
		max_health = 80,
	},
	movement = {
		speed_meters_per_second = 1.2,
		can_swim = false,
		can_climb = false,
	},
	carry_capacity = 0,
	combat = {
		attack_damage = 20,
		attack_speed = 1.5,
		attack_range = 2,
		armor = 3,
	},
	population_cost = 1,
} :: UnitData

UnitsData.Archer = {
	type = "Unit",
	subtype = "Ranged",
	cost = {
		Food = 15,
		Gold = 10,
		Wood = 5,
	},
	training_time_seconds = 12,
	health = {
		max_health = 30,
	},
	movement = {
		speed_meters_per_second = 1.3,
		can_swim = false,
		can_climb = false,
	},
	carry_capacity = 0,
	combat = {
		attack_damage = 8,
		attack_speed = 2.0,
		attack_range = 15,
		armor = 0,
	},
	population_cost = 1,
} :: UnitData

UnitsData.Knight = {
	type = "Unit",
	subtype = "Cavalry",
	faction = "Neutral",
	cost = {
		Food = 30,
		Gold = 40,
	},
	training_time_seconds = 20,
	health = {
		max_health = 100,
	},
	movement = {
		speed_meters_per_second = 2.0,
		can_swim = false,
		can_climb = false,
	},
	carry_capacity = 0,
	combat = {
		attack_damage = 30,
		attack_speed = 1.2,
		attack_range = 2,
		armor = 5,
	},
	population_cost = 2,
} :: UnitData

-- CIVILIAN UNITS
UnitsData.Monk = {
	type = "Unit",
	subtype = "Religious",
	faction = "Irish",
	cost = { Gold = 50, Food = 1 },
	training_time_seconds = 30,
	tags = { "civilian", "religious", "healer" },
	health = { max_health = 40 },
	movement = { speed_meters_per_second = 2.5 },
	combat = {
		attack_damage = 0,
		attack_speed = 0,
		attack_range = 0,
		armor = 0,
	},
	sight_range = 50,
	special_abilities = { "Heal", "Bless" },
	description = "Irish monk. Can heal units and provide blessings.",
} :: UnitData

UnitsData.Bard = {
	type = "Unit",
	subtype = "Support",
	faction = "Irish",
	cost = { Gold = 75, Food = 1 },
	training_time_seconds = 25,
	tags = { "civilian", "support", "morale" },
	health = { max_health = 35 },
	movement = { speed_meters_per_second = 3.0 },
	combat = {
		attack_damage = 0,
		attack_speed = 0,
		attack_range = 0,
		armor = 0,
	},
	sight_range = 60,
	special_abilities = { "Battle Song", "Inspire", "Demoralize Enemy" },
	description = "Celtic bard. Boosts morale of nearby troops and can demoralize enemies.",
} :: UnitData

-- IRISH LIGHT INFANTRY
UnitsData.Kern = {
	type = "Unit",
	subtype = "Light Infantry",
	faction = "Irish",
	cost = { Gold = 20, Food = 1, Weapons = 1 },
	training_time_seconds = 20,
	tags = { "military", "infantry", "light", "skirmisher" },
	health = { max_health = 60 },
	movement = { speed_meters_per_second = 4.0 },
	combat = {
		attack_damage = 8,
		attack_speed = 2.0,
		attack_range = 20, -- Javelin range
		armor = 1,
	},
	sight_range = 70,
	special_abilities = { "Javelin Throw", "Quick Retreat" },
	description = "Light Irish skirmisher armed with javelins and short sword.",
} :: UnitData

UnitsData.Ceithern = {
	type = "Unit",
	subtype = "Light Infantry",
	faction = "Irish",
	cost = { Gold = 15, Food = 1 },
	training_time_seconds = 18,
	tags = { "military", "infantry", "light", "militia" },
	health = { max_health = 50 },
	movement = { speed_meters_per_second = 3.8 },
	combat = {
		attack_damage = 6,
		attack_speed = 2.2,
		attack_range = 3,
		armor = 0,
	},
	sight_range = 60,
	special_abilities = { "Ambush" },
	description = "Lightly armed Irish warriors. Good for raids and ambushes.",
} :: UnitData

-- IRISH MEDIUM INFANTRY
UnitsData.Bonnacht = {
	type = "Unit",
	subtype = "Medium Infantry",
	faction = "Irish",
	cost = { Gold = 35, Food = 1, Weapons = 2 },
	training_time_seconds = 25,
	tags = { "military", "infantry", "medium" },
	health = { max_health = 90 },
	movement = { speed_meters_per_second = 3.2 },
	combat = {
		attack_damage = 12,
		attack_speed = 2.0,
		attack_range = 3,
		armor = 3,
	},
	sight_range = 65,
	special_abilities = { "Shield Bash" },
	description = "Professional Irish soldiers with sword and shield.",
} :: UnitData

-- IRISH HEAVY INFANTRY
UnitsData.Gallowglass = {
	type = "Unit",
	subtype = "Heavy Infantry",
	faction = "Irish",
	cost = { Gold = 60, Food = 2, Weapons = 3, Iron_Bars = 2 },
	training_time_seconds = 35,
	tags = { "military", "infantry", "heavy", "elite" },
	health = { max_health = 150 },
	movement = { speed_meters_per_second = 2.5 },
	combat = {
		attack_damage = 20,
		attack_speed = 2.5,
		attack_range = 4, -- Two-handed axe reach
		armor = 5,
	},
	sight_range = 60,
	special_abilities = { "Cleave", "Intimidate" },
	description = "Elite Irish heavy infantry armed with two-handed axes. Descendants of Norse-Gaels.",
} :: UnitData

UnitsData.Fianna = {
	type = "Unit",
	subtype = "Elite Infantry",
	faction = "Irish",
	cost = { Gold = 80, Food = 2, Weapons = 3, Honor = 10 },
	training_time_seconds = 40,
	tags = { "military", "infantry", "elite", "legendary" },
	health = { max_health = 120 },
	movement = { speed_meters_per_second = 3.5 },
	combat = {
		attack_damage = 18,
		attack_speed = 1.8,
		attack_range = 3,
		armor = 4,
	},
	sight_range = 80,
	special_abilities = { "Heroic Charge", "Rally", "Berserk" },
	description = "Legendary warrior band of Irish mythology. Fast and deadly.",
} :: UnitData

-- IRISH RANGED UNITS
UnitsData.Slinger = {
	type = "Unit",
	subtype = "Ranged Infantry",
	faction = "Irish",
	cost = { Gold = 15, Food = 1 },
	training_time_seconds = 15,
	tags = { "military", "ranged", "infantry", "light" },
	health = { max_health = 40 },
	movement = { speed_meters_per_second = 3.5 },
	combat = {
		attack_damage = 6,
		attack_speed = 1.5,
		attack_range = 25,
		armor = 0,
	},
	sight_range = 90,
	special_abilities = { "Quick Shot" },
	description = "Irish slinger. Cheap ranged unit with good rate of fire.",
} :: UnitData

UnitsData.Longbowman = {
	type = "Unit",
	subtype = "Ranged Infantry",
	faction = "Irish",
	cost = { Gold = 30, Food = 1, Wood = 5 },
	training_time_seconds = 22,
	tags = { "military", "ranged", "infantry" },
	health = { max_health = 55 },
	movement = { speed_meters_per_second = 3.0 },
	combat = {
		attack_damage = 10,
		attack_speed = 2.5,
		attack_range = 40,
		armor = 1,
	},
	sight_range = 100,
	special_abilities = { "Volley", "Fire Arrow" },
	description = "Irish archer with longbow. Good range and damage.",
} :: UnitData

-- IRISH CAVALRY
UnitsData.Light_Cavalry = {
	type = "Unit",
	subtype = "Light Cavalry",
	faction = "Irish",
	cost = { Gold = 45, Food = 2, Horses = 1 },
	training_time_seconds = 30,
	tags = { "military", "cavalry", "light", "scout" },
	health = { max_health = 80 },
	movement = { speed_meters_per_second = 7.0 },
	combat = {
		attack_damage = 10,
		attack_speed = 2.0,
		attack_range = 3,
		armor = 2,
	},
	sight_range = 100,
	special_abilities = { "Scout", "Hit and Run" },
	description = "Fast Irish cavalry for scouting and raids.",
} :: UnitData

UnitsData.Hobelar = {
	type = "Unit",
	subtype = "Medium Cavalry",
	faction = "Irish",
	cost = { Gold = 55, Food = 2, Horses = 1, Weapons = 2 },
	training_time_seconds = 32,
	tags = { "military", "cavalry", "medium" },
	health = { max_health = 100 },
	movement = { speed_meters_per_second = 6.0 },
	combat = {
		attack_damage = 14,
		attack_speed = 2.0,
		attack_range = 3,
		armor = 3,
	},
	sight_range = 80,
	special_abilities = { "Charge", "Trample" },
	description = "Irish light horsemen. Can dismount to fight.",
} :: UnitData

-- IRISH HEROES
UnitsData.Celtic_Champion = {
	type = "Unit",
	subtype = "Hero",
	faction = "Irish",
	cost = { Gold = 200, Food = 3, Honor = 50 },
	training_time_seconds = 60,
	tags = { "military", "hero", "unique" },
	health = { max_health = 300 },
	movement = { speed_meters_per_second = 3.8 },
	combat = {
		attack_damage = 35,
		attack_speed = 1.5,
		attack_range = 4,
		armor = 7,
	},
	sight_range = 90,
	special_abilities = { "Warp Spasm", "Battle Fury", "Heroic Leap", "Challenge" },
	description = "Legendary Celtic hero. Inspired by Cú Chulainn.",
} :: UnitData

UnitsData.Druid = {
	type = "Unit",
	subtype = "Hero Caster",
	faction = "Irish",
	cost = { Gold = 150, Food = 2, Honor = 30 },
	training_time_seconds = 50,
	tags = { "military", "hero", "caster", "support" },
	health = { max_health = 100 },
	movement = { speed_meters_per_second = 2.8 },
	combat = {
		attack_damage = 5,
		attack_speed = 3.0,
		attack_range = 20, -- Magic range
		armor = 2,
	},
	sight_range = 100,
	special_abilities = { "Lightning Strike", "Nature's Wrath", "Heal", "Entangle", "Summon Wolves" },
	description = "Powerful Celtic druid with nature magic.",
} :: UnitData

UnitsData.High_King = {
	type = "Unit",
	subtype = "Hero Leader",
	faction = "Irish",
	cost = { Gold = 500, Food = 5, Honor = 100 },
	training_time_seconds = 90,
	tags = { "military", "hero", "unique", "king" },
	health = { max_health = 500 },
	movement = { speed_meters_per_second = 3.0 },
	combat = {
		attack_damage = 30,
		attack_speed = 2.0,
		attack_range = 3,
		armor = 10,
	},
	sight_range = 100,
	special_abilities = { "Royal Decree", "Inspire Army", "Divine Right", "Summon the Fianna" },
	description = "The High King of Ireland. Powerful leader unit.",
} :: UnitData

-- SPECIAL/MYTHICAL UNITS
UnitsData.Banshee = {
	type = "Unit",
	subtype = "Mythical",
	faction = "Irish",
	cost = { Gold = 100, Honor = 20 },
	training_time_seconds = 45,
	tags = { "military", "mythical", "fear" },
	health = { max_health = 60 },
	movement = { speed_meters_per_second = 4.0 },
	combat = {
		attack_damage = 0,
		attack_speed = 5.0,
		attack_range = 30,
		armor = 0,
	},
	sight_range = 80,
	special_abilities = { "Wail", "Terror", "Death Omen" },
	description = "Mythical Irish spirit. Causes fear and lowers enemy morale.",
} :: UnitData

UnitsData.Wolfhound = {
	type = "Unit",
	subtype = "War Beast",
	faction = "Irish",
	cost = { Gold = 25, Food = 1 },
	training_time_seconds = 20,
	tags = { "military", "beast", "fast" },
	health = { max_health = 40 },
	movement = { speed_meters_per_second = 8.0 },
	combat = {
		attack_damage = 8,
		attack_speed = 1.5,
		attack_range = 2,
		armor = 0,
	},
	sight_range = 80,
	special_abilities = { "Track", "Howl", "Pack Hunter" },
	description = "Irish Wolfhound. Fast war dog, good against light units.",
} :: UnitData

return UnitsData
