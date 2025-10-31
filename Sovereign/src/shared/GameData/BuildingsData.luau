--!strict
-- BuildingsData: Definitions for all buildings

local BuildingsData = {}

export type BuildingData = {
	model_asset_name: string?,
	type: string,
	subtype: string,
	cost: { [string]: number },
	construction: { build_time_seconds: number },
	size: Vector3,
	storage_capacity: { [string]: number }?,
	components: { any }?,
	popularity_impact: number?,
	deletion_confirmation_required: boolean?,
	produces_resource: string?,
	production_rate: number?,
	requires_worker: boolean?,
	consumes_resource: string?,
	consumption_rate: number?,
	housing_capacity: number?,
	maintenance_cost: { [string]: number }?,
	can_train_units: { string }?,
	max_queue_size: number?,
}

BuildingsData.Keep = {
	model_asset_name = nil,
	type = "Building",
	subtype = "Main Building",
	cost = { Wood = 0 },
	construction = { build_time_seconds = 0 },
	size = Vector3.new(20, 15, 20),
	storage_capacity = {
		Wood = 1000,
		Stone = 1000,
		Gold = 1000,
		Food = 1000,
		Iron_Bars = 500,
		Weapons = 500,
	},
	components = {},
	can_train_units = { "Peasant" }, -- ADD THIS
	max_queue_size = 5, -- ADD THIS - Maximum units in training queue
} :: BuildingData

BuildingsData.Storehouse = {
	model_asset_name = nil,
	type = "Building",
	subtype = "Storage",
	cost = { Wood = 20, Stone = 5 },
	construction = { build_time_seconds = 10 },
	size = Vector3.new(12, 10, 12),
	storage_capacity = {
		Wood = 500,
		Stone = 500,
		Iron_Bars = 200,
		Weapons = 100,
	},
	components = {},
} :: BuildingData

BuildingsData.Granary = {
	model_asset_name = nil,
	type = "Building",
	subtype = "Storage",
	cost = { Wood = 15, Stone = 5 },
	construction = { build_time_seconds = 8 },
	size = Vector3.new(10, 12, 10),
	storage_capacity = {
		Food = 1000,
	},
	components = {},
} :: BuildingData

BuildingsData.Hovel = {
	model_asset_name = nil,
	type = "Building",
	subtype = "Housing",
	cost = { Wood = 10 },
	construction = { build_time_seconds = 5 },
	size = Vector3.new(8, 6, 8),
	storage_capacity = {},
	components = {},
	housing_capacity = 5, -- Each hovel houses 5 peasants
} :: BuildingData

BuildingsData.Woodcutters_Post = {
	model_asset_name = nil,
	type = "Building",
	subtype = "Resource Gathering",
	cost = { Wood = 5 },
	construction = { build_time_seconds = 7 },
	size = Vector3.new(10, 8, 10),
	storage_capacity = {
		Wood = 30,
	},
	components = {},
	produces_resource = "Wood",
	production_rate = 1,
	requires_worker = true,
} :: BuildingData

BuildingsData.Stone_Quarry = {
	model_asset_name = nil,
	type = "Building",
	subtype = "Resource Gathering",
	cost = { Wood = 10 },
	construction = { build_time_seconds = 10 },
	size = Vector3.new(12, 8, 12),
	storage_capacity = {
		Stone = 100,
	},
	components = {},
	produces_resource = "Stone",
	production_rate = 0.8,
	requires_worker = true,
} :: BuildingData

BuildingsData.Farm = {
	model_asset_name = nil,
	type = "Building",
	subtype = "Food Production",
	cost = { Wood = 15 },
	construction = { build_time_seconds = 10 },
	size = Vector3.new(16, 6, 16),
	storage_capacity = {
		Food = 150,
	},
	components = {},
	produces_resource = "Food",
	production_rate = 2,
	requires_worker = true,
	maintenance_cost = { Wood = 0.5 }, -- Minimal upkeep for tools
} :: BuildingData

BuildingsData.Kitchen = {
	model_asset_name = nil,
	type = "Building",
	subtype = "Food Processing",
	cost = { Wood = 10, Stone = 5 },
	construction = { build_time_seconds = 8 },
	size = Vector3.new(8, 8, 8),
	storage_capacity = {
		Food = 100,
	},
	components = {},
	requires_worker = true,
	consumes_resource = "Food",
	consumption_rate = 0.5,
} :: BuildingData

BuildingsData.Restaurant = {
	model_asset_name = nil,
	type = "Building",
	subtype = "Food Service",
	cost = { Wood = 20, Stone = 10 },
	construction = { build_time_seconds = 12 },
	size = Vector3.new(12, 10, 12),
	storage_capacity = {
		Food = 50,
	},
	components = {},
	popularity_impact = 3,
	requires_worker = true,
	consumes_resource = "Food",
	consumption_rate = 1,
} :: BuildingData

BuildingsData.Barracks = {
	model_asset_name = nil,
	type = "Building",
	subtype = "Military",
	cost = { Wood = 30, Stone = 20 },
	construction = { build_time_seconds = 15 },
	size = Vector3.new(16, 12, 16),
	storage_capacity = {},
	components = {},
	can_train_units = { "Spearman", "Archer", "Knight" },
	max_queue_size = 10,
	maintenance_cost = { Gold = 2 }, -- Military buildings are expensive to maintain
} :: BuildingData

-- PRODUCTION CHAIN BUILDINGS

BuildingsData.Iron_Mine = {
	model_asset_name = nil,
	type = "Building",
	subtype = "Resource Gathering",
	cost = { Wood = 20, Stone = 15 },
	construction = { build_time_seconds = 12 },
	size = Vector3.new(14, 10, 14),
	storage_capacity = {
		Iron_Ore = 100,
	},
	components = {},
	produces_resource = "Iron_Ore",
	production_rate = 0.6,
	requires_worker = true,
	maintenance_cost = { Wood = 1 }, -- Needs timber supports
} :: BuildingData

BuildingsData.Smithy = {
	model_asset_name = nil,
	type = "Building",
	subtype = "Production",
	cost = { Wood = 25, Stone = 20 },
	construction = { build_time_seconds = 15 },
	size = Vector3.new(12, 10, 12),
	storage_capacity = {
		Iron_Ore = 50,
		Iron_Bars = 50,
	},
	components = {},
	produces_resource = "Iron_Bars",
	production_rate = 1.0,
	requires_worker = true,
	consumes_resource = "Iron_Ore",
	consumption_rate = 2.0, -- Consumes 2 Iron Ore per production cycle
	maintenance_cost = { Wood = 1 }, -- Fuel for forge
} :: BuildingData

BuildingsData.Weaponsmith = {
	model_asset_name = nil,
	type = "Building",
	subtype = "Production",
	cost = { Wood = 30, Stone = 25, Iron_Bars = 10 },
	construction = { build_time_seconds = 18 },
	size = Vector3.new(14, 10, 14),
	storage_capacity = {
		Iron_Bars = 30,
		Weapons = 50,
	},
	components = {},
	produces_resource = "Weapons",
	production_rate = 0.8,
	requires_worker = true,
	consumes_resource = "Iron_Bars",
	consumption_rate = 3.0, -- Consumes 3 Iron Bars per production cycle
	maintenance_cost = { Wood = 1, Gold = 1 }, -- Fuel + skilled labor
} :: BuildingData

BuildingsData.Bakery = {
	model_asset_name = nil,
	type = "Building",
	subtype = "Food Processing",
	cost = { Wood = 15, Stone = 10 },
	construction = { build_time_seconds = 10 },
	size = Vector3.new(10, 8, 10),
	storage_capacity = {
		Food = 100,
		Bread = 150,
	},
	components = {},
	produces_resource = "Bread",
	production_rate = 1.5,
	requires_worker = true,
	consumes_resource = "Food",
	consumption_rate = 2.0, -- Consumes 2 Food (wheat) to make bread
	popularity_impact = 2, -- People like fresh bread!
	maintenance_cost = { Wood = 1 }, -- Fuel for ovens
} :: BuildingData

BuildingsData.Brewery = {
	model_asset_name = nil,
	type = "Building",
	subtype = "Food Processing",
	cost = { Wood = 20, Stone = 15 },
	construction = { build_time_seconds = 12 },
	size = Vector3.new(12, 10, 12),
	storage_capacity = {
		Food = 100,
		Ale = 200,
	},
	components = {},
	produces_resource = "Ale",
	production_rate = 1.2,
	requires_worker = true,
	consumes_resource = "Food",
	consumption_rate = 1.5, -- Consumes 1.5 Food (grain) to make ale
	popularity_impact = 5, -- Irish folk love their ale!
	maintenance_cost = { Wood = 1 }, -- Fuel and barrels
} :: BuildingData

-- TRADE & COMMERCE

BuildingsData.Market = {
	model_asset_name = nil,
	type = "Building",
	subtype = "Commerce",
	cost = { Wood = 40, Stone = 30, Gold = 20 },
	construction = { build_time_seconds = 20 },
	size = Vector3.new(16, 12, 16),
	storage_capacity = {
		-- Market can store all resource types for trading
		Wood = 200,
		Stone = 200,
		Gold = 500,
		Food = 200,
		Iron_Ore = 100,
		Iron_Bars = 100,
		Weapons = 50,
		Bread = 150,
		Ale = 150,
	},
	components = {},
	popularity_impact = 10, -- Markets bring prosperity!
	requires_worker = true,
	maintenance_cost = { Gold = 3 }, -- Expensive to run a market
} :: BuildingData

BuildingsData.Trading_Post = {
	model_asset_name = nil,
	type = "Building",
	subtype = "Commerce",
	cost = { Wood = 50, Stone = 40, Gold = 30 },
	construction = { build_time_seconds = 25 },
	size = Vector3.new(18, 14, 18),
	storage_capacity = {
		Wood = 300,
		Stone = 300,
		Gold = 1000,
		Food = 300,
		Iron_Ore = 200,
		Iron_Bars = 200,
		Weapons = 100,
		Bread = 200,
		Ale = 200,
	},
	components = {},
	popularity_impact = 15, -- Major trade hub!
	requires_worker = true,
	maintenance_cost = { Gold = 5 }, -- Very expensive
} :: BuildingData

return BuildingsData
