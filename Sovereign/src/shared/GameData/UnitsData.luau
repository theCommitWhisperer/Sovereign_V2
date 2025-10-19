--!strict
-- UnitsData: Definitions for all units

local UnitsData = {}

export type UnitData = {
	type: string,
	subtype: string,
	cost: { [string]: number },
	training_time: number,
	tags: { string },
	movement: { speed_meters_per_second: number },
	hit_points: number,
	attack_damage: number,
	attack_range_meters: number,
	sight_range: number,
	carry_capacity: number?,
}

UnitsData.King = {
	type = "Unit",
	subtype = "Royalty",
	cost = {},
	training_time = 0,
	tags = { "military", "hero" },
	movement = { speed_meters_per_second = 2.8 },
	hit_points = 500,
	attack_damage = 25,
	attack_range_meters = 8,
	sight_range = 80,
} :: UnitData

UnitsData.Peasant = {
	type = "Unit",
	subtype = "Worker",
	cost = { Gold = 10, population = 1 },
	training_time = 15,
	tags = { "civilian", "worker" },
	movement = { speed_meters_per_second = 3.2 },
	hit_points = 25,
	attack_damage = 1,
	attack_range_meters = 5,
	sight_range = 40,
	carry_capacity = 10,
} :: UnitData

UnitsData.Ox = {
	type = "Unit",
	subtype = "Transport",
	cost = { Gold = 20, population = 1 },
	training_time = 20,
	tags = { "civilian", "transport" },
	movement = { speed_meters_per_second = 2.0 },
	hit_points = 50,
	attack_damage = 0,
	attack_range_meters = 0,
	sight_range = 30,
	carry_capacity = 50,
} :: UnitData

-- Specialized worker types (peasants become these)
UnitsData.Woodcutter = {
	type = "Unit",
	subtype = "Resource Worker",
	cost = {},
	training_time = 0,
	tags = { "civilian", "worker", "woodcutter" },
	movement = { speed_meters_per_second = 3.0 },
	hit_points = 25,
	attack_damage = 1,
	attack_range_meters = 5,
	sight_range = 40,
	carry_capacity = 15,
} :: UnitData

UnitsData.Stonemason = {
	type = "Unit",
	subtype = "Resource Worker",
	cost = {},
	training_time = 0,
	tags = { "civilian", "worker", "stonemason" },
	movement = { speed_meters_per_second = 2.8 },
	hit_points = 30,
	attack_damage = 2,
	attack_range_meters = 5,
	sight_range = 40,
	carry_capacity = 12,
} :: UnitData

UnitsData.Farmer = {
	type = "Unit",
	subtype = "Resource Worker",
	cost = {},
	training_time = 0,
	tags = { "civilian", "worker", "farmer" },
	movement = { speed_meters_per_second = 3.0 },
	hit_points = 25,
	attack_damage = 1,
	attack_range_meters = 5,
	sight_range = 40,
	carry_capacity = 20,
} :: UnitData

return UnitsData
