--!strict
-- BuildingsData: Definitions for all buildings

local BuildingsData = {}

export type BuildingData = {
	model_asset_name: string?,
	type: string,
	subtype: string,
	description: string,
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
	defense_value: number?, -- For walls, towers, etc.
	attack_range: number?, -- For defensive towers
	attack_damage: number?, -- For defensive towers
}

BuildingsData.Keep = {
	model_asset_name = nil,
	type = "Building",
	subtype = "Main Building",
	description = "The heart of your settlement. If it's destroyed, you are defeated.",
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
	can_train_units = { "Peasant" },
	max_queue_size = 5,
} :: BuildingData

BuildingsData.Storehouse = {
	model_asset_name = nil,
	type = "Building",
	subtype = "Storage",
	description = "Increases your storage capacity for building materials and weapons.",
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

-- ========================================
-- DEFENSIVE BUILDINGS
-- ========================================

-- ========================================
-- STONE WALL PIECES (Auto-generated variants)
-- ========================================

BuildingsData.Stone_Wall = {
	model_asset_name = "stoneWallStraight",
	type = "Wall",
	subtype = "Defense",
	description = "Strong stone wall for castle defense",
	cost = { Stone = 10 },
	construction = { build_time_seconds = 8 },
	size = Vector3.new(8.5, 6, 2), -- Slightly wider for overlap (0.25 studs on each side)
	storage_capacity = {},
	components = {},
	defense_value = 50,
	deletion_confirmation_required = false,
} :: BuildingData

BuildingsData.Stone_Wall_Straight = {
	model_asset_name = "stoneWallStraight",
	type = "Wall",
	subtype = "Defense",
	description = "Straight stone wall section",
	cost = { Stone = 10 },
	construction = { build_time_seconds = 8 },
	size = Vector3.new(8.5, 6, 2), -- Slightly wider for overlap (0.25 studs on each side)
	storage_capacity = {},
	components = {},
	defense_value = 50,
	deletion_confirmation_required = false,
} :: BuildingData

BuildingsData.Stone_Wall_Corner = {
	model_asset_name = "stoneWall90degreeTurn",
	type = "Wall",
	subtype = "Defense",
	description = "Stone wall corner piece",
	cost = { Stone = 10 },
	construction = { build_time_seconds = 8 },
	size = Vector3.new(6, 6, 6),
	storage_capacity = {},
	components = {},
	defense_value = 50,
	deletion_confirmation_required = false,
} :: BuildingData

BuildingsData.Stone_Wall_T = {
	model_asset_name = "stoneWall3way",
	type = "Wall",
	subtype = "Defense",
	description = "Stone wall T-junction",
	cost = { Stone = 10 },
	construction = { build_time_seconds = 8 },
	size = Vector3.new(8, 6, 8),
	storage_capacity = {},
	components = {},
	defense_value = 50,
	deletion_confirmation_required = false,
} :: BuildingData

BuildingsData.Stone_Wall_Cross = {
	model_asset_name = "stoneWall4way",
	type = "Wall",
	subtype = "Defense",
	description = "Stone wall 4-way intersection",
	cost = { Stone = 10 },
	construction = { build_time_seconds = 8 },
	size = Vector3.new(8, 6, 8),
	storage_capacity = {},
	components = {},
	defense_value = 50,
	deletion_confirmation_required = false,
} :: BuildingData

-- ========================================
-- WOODEN PALISADE PIECES (Auto-generated variants)
-- ========================================

BuildingsData.Wooden_Palisade = {
	model_asset_name = nil,
	type = "Wall",
	subtype = "Defense",
	description = "Wooden palisade wall for early defense",
	cost = { Wood = 5 },
	construction = { build_time_seconds = 5 },
	size = Vector3.new(8, 4, 2),
	storage_capacity = {},
	components = {},
	defense_value = 20,
	deletion_confirmation_required = false,
} :: BuildingData

BuildingsData.Wooden_Palisade_Straight = {
	model_asset_name = nil,
	type = "Wall",
	subtype = "Defense",
	description = "Straight wooden palisade section",
	cost = { Wood = 5 },
	construction = { build_time_seconds = 5 },
	size = Vector3.new(8, 4, 2),
	storage_capacity = {},
	components = {},
	defense_value = 20,
	deletion_confirmation_required = false,
} :: BuildingData

BuildingsData.Wooden_Palisade_Corner = {
	model_asset_name = nil,
	type = "Wall",
	subtype = "Defense",
	description = "Wooden palisade corner piece",
	cost = { Wood = 5 },
	construction = { build_time_seconds = 5 },
	size = Vector3.new(6, 4, 6),
	storage_capacity = {},
	components = {},
	defense_value = 20,
	deletion_confirmation_required = false,
} :: BuildingData

BuildingsData.Wooden_Palisade_T = {
	model_asset_name = nil,
	type = "Wall",
	subtype = "Defense",
	description = "Wooden palisade T-junction",
	cost = { Wood = 5 },
	construction = { build_time_seconds = 5 },
	size = Vector3.new(8, 4, 8),
	storage_capacity = {},
	components = {},
	defense_value = 20,
	deletion_confirmation_required = false,
} :: BuildingData

BuildingsData.Wooden_Palisade_Cross = {
	model_asset_name = nil,
	type = "Wall",
	subtype = "Defense",
	description = "Wooden palisade 4-way intersection",
	cost = { Wood = 5 },
	construction = { build_time_seconds = 5 },
	size = Vector3.new(8, 4, 8),
	storage_capacity = {},
	components = {},
	defense_value = 20,
	deletion_confirmation_required = false,
} :: BuildingData

BuildingsData.Gatehouse = {
	model_asset_name = nil,
	type = "Building",
	subtype = "Defense",
	cost = { Wood = 30, Stone = 40 },
	construction = { build_time_seconds = 20 },
	size = Vector3.new(12, 14, 8),
	storage_capacity = {},
	components = {},
	defense_value = 100,
	can_train_units = { "Guard" }, -- Can station guards
	max_queue_size = 3,
	deletion_confirmation_required = true,
} :: BuildingData

BuildingsData.Watch_Tower = {
	model_asset_name = nil,
	type = "Building",
	subtype = "Defense",
	cost = { Wood = 20, Stone = 15 },
	construction = { build_time_seconds = 12 },
	size = Vector3.new(8, 16, 8), -- Tall and narrow
	storage_capacity = {},
	components = {},
	defense_value = 40,
	attack_range = 50, -- Can attack enemies within range
	attack_damage = 10,
	requires_worker = true, -- Needs guard to man it
} :: BuildingData

BuildingsData.Arrow_Tower = {
	model_asset_name = nil,
	type = "Building",
	subtype = "Defense",
	cost = { Wood = 15, Stone = 25 },
	construction = { build_time_seconds = 15 },
	size = Vector3.new(10, 18, 10),
	storage_capacity = {},
	components = {},
	defense_value = 60,
	attack_range = 70,
	attack_damage = 15,
	requires_worker = true,
	maintenance_cost = { Weapons = 0.5 }, -- Uses arrows
} :: BuildingData

BuildingsData.Guard_House = {
	model_asset_name = nil,
	type = "Building",
	subtype = "Military",
	cost = { Wood = 25, Stone = 15 },
	construction = { build_time_seconds = 12 },
	size = Vector3.new(10, 8, 10),
	storage_capacity = {
		Weapons = 20,
	},
	components = {},
	can_train_units = { "Guard" },
	max_queue_size = 5,
	maintenance_cost = { Gold = 1 },
} :: BuildingData

-- ========================================
-- ECONOMIC & CRAFTING BUILDINGS
-- ========================================

BuildingsData.Tavern = {
	model_asset_name = nil,
	type = "Building",
	subtype = "Entertainment",
	cost = { Wood = 25, Stone = 15 },
	construction = { build_time_seconds = 12 },
	size = Vector3.new(14, 10, 14),
	storage_capacity = {
		Ale = 100,
		Food = 50,
	},
	components = {},
	popularity_impact = 8, -- People love taverns!
	requires_worker = true,
	consumes_resource = "Ale",
	consumption_rate = 1.5, -- Serves ale to patrons
	maintenance_cost = { Gold = 2 },
} :: BuildingData

BuildingsData.Inn = {
	model_asset_name = nil,
	type = "Building",
	subtype = "Entertainment",
	cost = { Wood = 35, Stone = 25 },
	construction = { build_time_seconds = 15 },
	size = Vector3.new(16, 12, 16),
	storage_capacity = {
		Ale = 80,
		Food = 80,
		Bread = 60,
	},
	components = {},
	popularity_impact = 12,
	housing_capacity = 3, -- Can house travelers
	requires_worker = true,
	consumes_resource = "Bread",
	consumption_rate = 1.0,
	maintenance_cost = { Gold = 3 },
} :: BuildingData

BuildingsData.Windmill = {
	model_asset_name = nil,
	type = "Building",
	subtype = "Food Processing",
	cost = { Wood = 30, Stone = 20 },
	construction = { build_time_seconds = 15 },
	size = Vector3.new(12, 18, 12), -- Tall with windmill
	storage_capacity = {
		Food = 200,
		Flour = 250,
	},
	components = {},
	produces_resource = "Flour",
	production_rate = 2.0,
	requires_worker = true,
	consumes_resource = "Food",
	consumption_rate = 2.5, -- Grinds grain to flour
	popularity_impact = 3,
	maintenance_cost = { Wood = 1.5 },
} :: BuildingData

BuildingsData.Water_Mill = {
	model_asset_name = nil,
	type = "Building",
	subtype = "Food Processing",
	cost = { Wood = 40, Stone = 30 },
	construction = { build_time_seconds = 18 },
	size = Vector3.new(14, 12, 14),
	storage_capacity = {
		Food = 250,
		Flour = 300,
	},
	components = {},
	produces_resource = "Flour",
	production_rate = 2.5, -- More efficient than windmill
	requires_worker = true,
	consumes_resource = "Food",
	consumption_rate = 3.0,
	popularity_impact = 4,
} :: BuildingData

BuildingsData.Tannery = {
	model_asset_name = nil,
	type = "Building",
	subtype = "Production",
	cost = { Wood = 20, Stone = 10 },
	construction = { build_time_seconds = 12 },
	size = Vector3.new(12, 8, 12),
	storage_capacity = {
		Leather = 100,
	},
	components = {},
	produces_resource = "Leather",
	production_rate = 0.8,
	requires_worker = true,
	popularity_impact = -2, -- Smells bad!
	maintenance_cost = { Wood = 0.5 },
} :: BuildingData

BuildingsData.Carpenter = {
	model_asset_name = nil,
	type = "Building",
	subtype = "Production",
	cost = { Wood = 15, Stone = 5 },
	construction = { build_time_seconds = 10 },
	size = Vector3.new(10, 8, 10),
	storage_capacity = {
		Wood = 100,
		Furniture = 50,
	},
	components = {},
	produces_resource = "Furniture",
	production_rate = 1.2,
	requires_worker = true,
	consumes_resource = "Wood",
	consumption_rate = 2.5,
	popularity_impact = 2,
} :: BuildingData

BuildingsData.Fishermans_Hut = {
	model_asset_name = nil,
	type = "Building",
	subtype = "Food Production",
	cost = { Wood = 10 },
	construction = { build_time_seconds = 7 },
	size = Vector3.new(8, 6, 8),
	storage_capacity = {
		Food = 80,
	},
	components = {},
	produces_resource = "Food",
	production_rate = 1.5, -- Fish!
	requires_worker = true,
} :: BuildingData

-- ========================================
-- CULTURAL & RELIGIOUS BUILDINGS
-- ========================================

BuildingsData.Church = {
	model_asset_name = nil,
	type = "Building",
	subtype = "Religious",
	cost = { Wood = 40, Stone = 60, Gold = 30 },
	construction = { build_time_seconds = 30 },
	size = Vector3.new(18, 20, 24), -- Large cathedral-style
	storage_capacity = {
		Gold = 200, -- Tithes and donations
	},
	components = {},
	popularity_impact = 15, -- Major morale boost
	requires_worker = true, -- Priest
	maintenance_cost = { Gold = 4 },
} :: BuildingData

BuildingsData.Chapel = {
	model_asset_name = nil,
	type = "Building",
	subtype = "Religious",
	cost = { Wood = 20, Stone = 30 },
	construction = { build_time_seconds = 15 },
	size = Vector3.new(12, 14, 14),
	storage_capacity = {},
	components = {},
	popularity_impact = 6,
	requires_worker = true,
	maintenance_cost = { Gold = 1 },
} :: BuildingData

BuildingsData.Monastery = {
	model_asset_name = nil,
	type = "Building",
	subtype = "Religious",
	cost = { Wood = 50, Stone = 80, Gold = 50 },
	construction = { build_time_seconds = 40 },
	size = Vector3.new(24, 16, 24),
	storage_capacity = {
		Gold = 300,
		Food = 200,
		Manuscripts = 100,
	},
	components = {},
	popularity_impact = 20, -- Major religious center
	housing_capacity = 10, -- Houses monks
	requires_worker = true, -- Monks work here
	produces_resource = "Manuscripts",
	production_rate = 0.5, -- Monks copy manuscripts
	maintenance_cost = { Gold = 5, Food = 3 },
} :: BuildingData

BuildingsData.Scriptorium = {
	model_asset_name = nil,
	type = "Building",
	subtype = "Cultural",
	cost = { Wood = 30, Stone = 20, Gold = 20 },
	construction = { build_time_seconds = 15 },
	size = Vector3.new(12, 10, 12),
	storage_capacity = {
		Manuscripts = 200,
	},
	components = {},
	produces_resource = "Manuscripts",
	production_rate = 0.8,
	requires_worker = true, -- Scribes
	popularity_impact = 5,
	maintenance_cost = { Gold = 2 },
} :: BuildingData

BuildingsData.Town_Hall = {
	model_asset_name = nil,
	type = "Building",
	subtype = "Administrative",
	cost = { Wood = 60, Stone = 80, Gold = 40 },
	construction = { build_time_seconds = 35 },
	size = Vector3.new(20, 16, 20),
	storage_capacity = {
		Gold = 500,
	},
	components = {},
	popularity_impact = 10,
	requires_worker = true, -- Administrator
	maintenance_cost = { Gold = 6 },
	deletion_confirmation_required = true,
} :: BuildingData

-- ========================================
-- IRISH-THEMED SPECIAL BUILDINGS
-- ========================================

BuildingsData.Round_Tower = {
	model_asset_name = nil,
	type = "Building",
	subtype = "Cultural",
	cost = { Stone = 100, Gold = 50 },
	construction = { build_time_seconds = 40 },
	size = Vector3.new(8, 30, 8), -- Very tall, narrow Irish round tower
	storage_capacity = {
		Gold = 300,
		Manuscripts = 150,
	},
	components = {},
	popularity_impact = 25, -- Iconic Irish landmark
	defense_value = 80, -- Can be used as refuge
	attack_range = 60, -- Bell tower can spot enemies
	maintenance_cost = { Gold = 3 },
	deletion_confirmation_required = true,
} :: BuildingData

BuildingsData.Crannog = {
	model_asset_name = nil,
	type = "Building",
	subtype = "Defense",
	cost = { Wood = 50, Stone = 20 },
	construction = { build_time_seconds = 25 },
	size = Vector3.new(16, 8, 16), -- Artificial island dwelling
	storage_capacity = {
		Wood = 200,
		Stone = 100,
		Food = 200,
	},
	components = {},
	housing_capacity = 8, -- Fortified dwelling
	defense_value = 120, -- Very defensible, surrounded by water
	popularity_impact = 8,
	maintenance_cost = { Wood = 2 },
} :: BuildingData

BuildingsData.Brehon_Court = {
	model_asset_name = nil,
	type = "Building",
	subtype = "Administrative",
	cost = { Wood = 40, Stone = 50, Gold = 30 },
	construction = { build_time_seconds = 25 },
	size = Vector3.new(16, 12, 16),
	storage_capacity = {
		Gold = 300,
	},
	components = {},
	popularity_impact = 12, -- Ancient Irish law system
	requires_worker = true, -- Brehon judge
	maintenance_cost = { Gold = 4 },
} :: BuildingData

BuildingsData.Clachan = {
	model_asset_name = nil,
	type = "Building",
	subtype = "Housing",
	cost = { Wood = 15, Stone = 10 },
	construction = { build_time_seconds = 8 },
	size = Vector3.new(12, 8, 12),
	storage_capacity = {},
	components = {},
	housing_capacity = 8, -- Small Irish hamlet/village cluster
	popularity_impact = 3,
} :: BuildingData

BuildingsData.Mead_Hall = {
	model_asset_name = nil,
	type = "Building",
	subtype = "Entertainment",
	cost = { Wood = 60, Stone = 40, Gold = 30 },
	construction = { build_time_seconds = 25 },
	size = Vector3.new(24, 14, 16), -- Large feasting hall
	storage_capacity = {
		Ale = 300,
		Food = 200,
		Bread = 150,
	},
	components = {},
	popularity_impact = 20, -- Major cultural center for feasts
	requires_worker = true,
	consumes_resource = "Ale",
	consumption_rate = 2.5,
	can_train_units = { "Warrior" }, -- Recruit warriors at feast
	max_queue_size = 5,
	maintenance_cost = { Gold = 5, Food = 2 },
} :: BuildingData

BuildingsData.Dolmen = {
	model_asset_name = nil,
	type = "Building",
	subtype = "Cultural",
	cost = { Stone = 80 },
	construction = { build_time_seconds = 30 },
	size = Vector3.new(12, 10, 12),
	storage_capacity = {},
	components = {},
	popularity_impact = 18, -- Ancient megalithic tomb, culturally significant
	deletion_confirmation_required = true,
} :: BuildingData

BuildingsData.Celtic_Cross = {
	model_asset_name = nil,
	type = "Building",
	subtype = "Religious",
	cost = { Stone = 30, Gold = 15 },
	construction = { build_time_seconds = 12 },
	size = Vector3.new(4, 12, 4), -- Tall cross monument
	storage_capacity = {},
	components = {},
	popularity_impact = 8, -- Irish Christian symbol
	deletion_confirmation_required = false,
} :: BuildingData

BuildingsData.Forge_of_the_Tuatha = {
	model_asset_name = nil,
	type = "Building",
	subtype = "Production",
	cost = { Stone = 100, Iron_Bars = 50, Gold = 80 },
	construction = { build_time_seconds = 50 },
	size = Vector3.new(16, 14, 16),
	storage_capacity = {
		Iron_Bars = 200,
		Weapons = 150,
		Legendary_Weapons = 20,
	},
	components = {},
	produces_resource = "Legendary_Weapons", -- Special Irish mythological weapons
	production_rate = 0.3, -- Slow, legendary crafting
	requires_worker = true,
	consumes_resource = "Iron_Bars",
	consumption_rate = 5.0, -- Expensive materials
	popularity_impact = 15, -- Mythological forge
	maintenance_cost = { Gold = 10, Iron_Bars = 2 },
	deletion_confirmation_required = true,
} :: BuildingData

BuildingsData.Stone_Circle = {
	model_asset_name = nil,
	type = "Building",
	subtype = "Cultural",
	cost = { Stone = 120 },
	construction = { build_time_seconds = 45 },
	size = Vector3.new(20, 8, 20), -- Large circular arrangement
	storage_capacity = {},
	components = {},
	popularity_impact = 22, -- Ancient druidic site
	deletion_confirmation_required = true,
} :: BuildingData

return BuildingsData
