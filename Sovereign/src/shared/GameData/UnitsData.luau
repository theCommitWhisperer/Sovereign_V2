--!strict

export type UnitData = {
	type: string,
	subtype: string,
	cost: { [string]: number },
	training_time_seconds: number?, -- Make optional for units that already exist
	health: {
		max_health: number,
		current_health: number,
	},
	movement: {
		speed_meters_per_second: number,
		can_swim: boolean,
		can_climb: boolean,
	},
	carry_capacity: number,
	combat: {
		attack_damage: number,
		attack_speed: number,
		attack_range: number,
		armor: number,
	}?,
	population_cost: number?,
}

local UnitsData: { [string]: UnitData } = {}

UnitsData.King = {
	type = "Unit",
	subtype = "Hero",
	cost = { Gold = 0 },
	training_time_seconds = 0,
	health = {
		max_health = 200,
		current_health = 200,
	},
	movement = {
		speed_meters_per_second = 1.5,
		can_swim = false,
		can_climb = false,
	},
	carry_capacity = 0,
	combat = {
		attack_damage = 25,
		attack_speed = 1.0,
		attack_range = 2,
		armor = 10,
	},
	population_cost = 0,
} :: UnitData

UnitsData.Peasant = {
	type = "Unit",
	subtype = "Worker",
	cost = {
		Food = 5,
	},
	training_time_seconds = 5,
	health = {
		max_health = 25,
		current_health = 25,
	},
	movement = {
		speed_meters_per_second = 1.0,
		can_swim = false,
		can_climb = false,
	},
	carry_capacity = 10,
	combat = {
		attack_damage = 1,
		attack_speed = 1.0,
		attack_range = 1,
		armor = 0,
	},
	population_cost = 1,
} :: UnitData

UnitsData.Woodcutter = {
	type = "Unit",
	subtype = "Worker",
	cost = { Food = 0 },
	training_time_seconds = 0,
	health = {
		max_health = 25,
		current_health = 25,
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
	cost = { Food = 0 },
	training_time_seconds = 0,
	health = {
		max_health = 30,
		current_health = 30,
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
	cost = { Food = 0 },
	training_time_seconds = 0,
	health = {
		max_health = 25,
		current_health = 25,
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
	cost = {
		Food = 10,
		Gold = 5,
	},
	training_time_seconds = 10,
	health = {
		max_health = 50,
		current_health = 50,
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
	cost = {
		Food = 10,
		Gold = 100,
	},
	training_time_seconds = 10,
	health = {
		max_health = 80,
		current_health = 80,
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
		current_health = 30,
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
	cost = {
		Food = 30,
		Gold = 40,
	},
	training_time_seconds = 20,
	health = {
		max_health = 100,
		current_health = 100,
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

return UnitsData
