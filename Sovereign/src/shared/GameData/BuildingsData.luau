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
}

BuildingsData.Keep = {
	model_asset_name = nil,
	type = "Building",
	subtype = "Castle Core",
	cost = { Wood = 100, Stone = 50 },
	construction = { build_time_seconds = 30 },
	size = Vector3.new(24, 30, 24),
	storage_capacity = {
		Wood = 200,
		Stone = 100,
		Gold = 500,
	},
	components = {},
	popularity_impact = 5,
	deletion_confirmation_required = true,
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
	subtype = "Military Training",
	cost = { Wood = 20, Stone = 10 },
	construction = { build_time_seconds = 15 },
	size = Vector3.new(15, 10, 15),
	storage_capacity = {},
	components = {},
} :: BuildingData

return BuildingsData
