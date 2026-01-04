--!strict
-- BuildingsData: Definitions for all buildings

local WorkerPointsConfig = require(script.Parent.WorkerPointsConfig)

local BuildingsData = {}

-- Worker point configuration for production buildings
export type WorkerPointConfig = {
	entrance_point: string?, -- Name of the BuildingEntrance part (default: "BuildingEntrance")
	rest_point: string?, -- Name of the WorkerRestPosition part (default: "WorkerRestPosition")
	production_point: string?, -- Name of the ProductionStation part (default: "ProductionStation")
	dropoff_point: string?, -- Name of the ResourceDropoff part (default: "ResourceDropoff")
	pickup_point: string?, -- Name of the ResourcePickup part (default: "ResourcePickup")
}

-- Storage point configuration for storage buildings
export type StoragePointConfig = {
	Wood: string?, -- Name of the wood storage point (default: "StorageAreaWood")
	Stone: string?, -- Name of the stone storage point (default: "StorageAreaStone")
	Food: string?, -- Name of the food storage point (default: "StorageAreaFood")
	Iron_Ore: string?, -- Name of the iron storage point (default: "StorageAreaIron")
	Iron_Bars: string?, -- Name of the iron bars storage point (default: "StorageAreaIron")
	Gold: string?, -- Name of the gold storage point (default: "StorageAreaGold")
	Weapons: string?, -- Name of the weapons storage point (default: "StorageAreaWeapons")
	default: string?, -- Name of the general storage point (default: "StorageAreaGeneral")
}

export type BuildingData = {
	model_asset_name: string?,
	icon_asset_id: string?,
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
	worker_job_type: string?,
	consumes_resource: string?,
	consumption_rate: number?,
	housing_capacity: number?,
	maintenance_cost: { [string]: number }?,
	can_train_units: { string }?,
	max_queue_size: number?,
	defense_value: number?,
	attack_range: number?,
	attack_damage: number?,
	worker_points: WorkerPointConfig?, -- NEW: Configuration for worker navigation points
	storage_points: StoragePointConfig?, -- NEW: Configuration for storage area points
}

-- ========================================
-- KEEP (Main Building)
-- ========================================

BuildingsData.Keep = {
	model_asset_name = "Stone_Wall_Large_Keep",
	type = "Building",
	subtype = "Main Building",
	description = "The heart of your settlement. If it's destroyed, you are defeated.",
	cost = { Wood = 0 },
	construction = { build_time_seconds = 0 },
	size = Vector3.new(94, 76, 110),
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
	storage_points = {
		Wood = "StorageAreaWood",
		Stone = "StorageAreaStone",
		Gold = "StorageAreaGold",
		Food = "StorageAreaFood",
		Iron_Bars = "StorageAreaIron",
		Weapons = "StorageAreaWeapons",
		default = "StorageAreaGeneral",
	},
} :: BuildingData

-- ========================================
-- DEFENSE CATEGORY (9 buildings)
-- ========================================

BuildingsData["Stone Wall"] = {
	model_asset_name = "Stone_Wall_Straight",
	icon_asset_id = "rbxassetid://80737072171362",
	type = "Building",
	subtype = "Fortification",
	description = "Build stone walls by clicking and dragging. Press R to rotate, C to continue from last wall.",
	cost = { Stone = 2 },
	construction = { build_time_seconds = 3 },
	size = Vector3.new(16, 8, 2),
	storage_capacity = {},
	components = {},
	defense_value = 30,
	deletion_confirmation_required = false,
} :: BuildingData

BuildingsData["Short Tower"] = {
	model_asset_name = "Stone_Wall_Small_Tower",
	icon_asset_id = "rbxassetid://138869266728745",
	type = "Building",
	subtype = "Defensive Tower",
	description = "Fortified tower for wall corners and defensive positions.",
	cost = { Stone = 15 },
	construction = { build_time_seconds = 10 },
	size = Vector3.new(24, 24, 24),
	storage_capacity = {},
	components = {},
	defense_value = 100,
	attack_damage = 10,
	deletion_confirmation_required = false,
} :: BuildingData

BuildingsData["Wall Gatehouse"] = {
	model_asset_name = "Stone_Wall_Gatehouse",
	icon_asset_id = "rbxassetid://103326690343187",
	type = "Building",
	subtype = "Fortification",
	description = "Grand gatehouse entrance for your walls. Snaps automatically to existing walls.",
	cost = { Stone = 50, Wood = 20 },
	construction = { build_time_seconds = 20 },
	size = Vector3.new(58, 20, 16),
	storage_capacity = {},
	components = {},
	defense_value = 150,
	deletion_confirmation_required = false,
} :: BuildingData

BuildingsData["Wall Ladder"] = {
	model_asset_name = "Stone_Wall_Ladder",
	icon_asset_id = "rbxassetid://115999096146008",
	type = "Building",
	subtype = "Fortification",
	description = "Wall segment with ladder for defenders to reach the top.",
	cost = { Stone = 5, Wood = 3 },
	construction = { build_time_seconds = 5 },
	size = Vector3.new(16, 8, 2),
	storage_capacity = {},
	components = {},
	defense_value = 30,
	deletion_confirmation_required = false,
} :: BuildingData

BuildingsData["Round Tower"] = {
	model_asset_name = "Large_Tower_Stone_Wall",
	icon_asset_id = "rbxassetid://104692244573741",
	type = "Building",
	subtype = "Defensive Tower",
	description = "Iconic Irish round tower serving as both refuge and lookout.",
	cost = { Stone = 100, Gold = 50 },
	construction = { build_time_seconds = 40 },
	size = Vector3.new(8, 30, 8),
	storage_capacity = {
		Gold = 300,
	},
	components = {},
	popularity_impact = 25,
	defense_value = 80,
	attack_range = 60,
	maintenance_cost = { Gold = 3 },
	deletion_confirmation_required = true,
} :: BuildingData

BuildingsData["Wooden Palisade"] = {
	model_asset_name = nil,
	icon_asset_id = "rbxassetid://81605593632271",
	type = "Building",
	subtype = "Fortification",
	description = "A simple wooden fence providing basic protection.",
	cost = { Wood = 5 },
	construction = { build_time_seconds = 5 },
	size = Vector3.new(8, 4, 2),
	storage_capacity = {},
	components = {},
	defense_value = 20,
	deletion_confirmation_required = false,
} :: BuildingData

BuildingsData["Arrow Tower"] = {
	model_asset_name = "Large_Tower_Stone_Wall",
	icon_asset_id = "rbxassetid://123268723874601",
	type = "Building",
	subtype = "Defensive Tower",
	description = "Fortified tower with archers providing long-range defense.",
	cost = { Wood = 15, Stone = 25 },
	construction = { build_time_seconds = 15 },
	size = Vector3.new(10, 18, 10),
	storage_capacity = {},
	components = {},
	defense_value = 60,
	attack_range = 70,
	attack_damage = 15,
	requires_worker = true,
	worker_job_type = "Archer",
	maintenance_cost = { Weapons = 0.5 },
} :: BuildingData

BuildingsData["Moat"] = {
	model_asset_name = nil,
	icon_asset_id = "rbxassetid://138157416171685",
	type = "Building",
	subtype = "Fortification",
	description = "A defensive ditch. Slows down enemies who try to cross.",
	cost = { Stone = 1 },
	construction = { build_time_seconds = 2 },
	size = Vector3.new(16, 2, 8),
	storage_capacity = {},
	components = {},
	defense_value = 10,
	deletion_confirmation_required = false,
} :: BuildingData

BuildingsData["Fire Pit"] = {
	model_asset_name = nil,
	icon_asset_id = "rbxassetid://122281250220127",
	type = "Building",
	subtype = "Support",
	description = "Allows archers to light their arrows for extra damage.",
	cost = { Wood = 15, Stone = 5 },
	construction = { build_time_seconds = 8 },
	size = Vector3.new(6, 4, 6),
	storage_capacity = {},
	components = {},
	defense_value = 5,
	popularity_impact = 1,
} :: BuildingData

-- ========================================
-- MILITARY CATEGORY (9 buildings)
-- ========================================

BuildingsData["Barracks"] = {
	model_asset_name = "Siege_Camps/Red_Siege_Camp",
	icon_asset_id = "rbxassetid://95490961977143",
	type = "Building",
	subtype = "Military Training",
	description = "Train infantry units to defend your settlement and wage war.",
	cost = { Wood = 30, Stone = 20 },
	construction = { build_time_seconds = 15 },
	size = Vector3.new(16, 12, 16),
	storage_capacity = { Weapons = 50 },
	components = {},
	can_train_units = { "Spearman", "Archer", "Knight" },
	max_queue_size = 10,
	popularity_impact = 2,
	maintenance_cost = { Gold = 2 },
} :: BuildingData

BuildingsData["Guard House"] = {
	model_asset_name = "Siege_Camps/Blue_Siege_Camp",
	icon_asset_id = "rbxassetid://130189590326032",
	type = "Building",
	subtype = "Military",
	description = "Houses guards to patrol and protect your settlement.",
	cost = { Wood = 25, Stone = 15 },
	construction = { build_time_seconds = 12 },
	size = Vector3.new(10, 8, 10),
	storage_capacity = { Weapons = 20 },
	components = {},
	can_train_units = { "Guard" },
	max_queue_size = 5,
	maintenance_cost = { Gold = 1 },
} :: BuildingData

BuildingsData["Smelter"] = {
	model_asset_name = "Weapon_Smith",
	icon_asset_id = "rbxassetid://70860391344001",
	type = "Building",
	subtype = "Production",
	description = "Smelts iron ore into iron bars for crafting.",
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
	worker_job_type = "Smelter",
	consumes_resource = "Iron_Ore",
	consumption_rate = 2.0,
	maintenance_cost = { Wood = 1 },
	worker_points = {
		entrance_point = "BuildingEntrance",
		rest_point = "WorkerRestPosition",
		production_point = "ProductionStation",
		dropoff_point = "ResourceDropoff",
		pickup_point = "ResourcePickup",
	},
} :: BuildingData

BuildingsData["Weaponsmith"] = {
	model_asset_name = "Weapon_Smith",
	icon_asset_id = "rbxassetid://131338540215149",
	type = "Building",
	subtype = "Production",
	description = "Forges weapons from iron bars for your military.",
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
	worker_job_type = "Blacksmith",
	consumes_resource = "Iron_Bars",
	consumption_rate = 3.0,
	maintenance_cost = { Wood = 1, Gold = 1 },
	worker_points = WorkerPointsConfig.STANDARD_PRODUCTION,
} :: BuildingData

BuildingsData["Armory"] = {
	model_asset_name = "Storehouse",
	icon_asset_id = "rbxassetid://100389544948531",
	type = "Building",
	subtype = "Military Storage",
	description = "Stores weapons and armor for your military forces.",
	cost = { Wood = 25, Stone = 20, Iron_Bars = 10 },
	construction = { build_time_seconds = 15 },
	size = Vector3.new(12, 10, 12),
	storage_capacity = { Weapons = 200, Iron_Bars = 100 },
	components = {},
	popularity_impact = 1,
	storage_points = WorkerPointsConfig.STORAGE_MILITARY,
} :: BuildingData

BuildingsData["Training Ground"] = {
	model_asset_name = "Siege_Camps/Red_Siege_Camp",
	icon_asset_id = "rbxassetid://77987612212831",
	type = "Building",
	subtype = "Military Training",
	description = "A field for training soldiers in combat techniques.",
	cost = { Wood = 35, Stone = 10 },
	construction = { build_time_seconds = 12 },
	size = Vector3.new(20, 2, 20),
	storage_capacity = {},
	components = {},
	can_train_units = { "Swordsman", "Archer" },
	max_queue_size = 8,
	maintenance_cost = { Gold = 1 },
} :: BuildingData

BuildingsData["Siege Workshop"] = {
	model_asset_name = "Carpenter",
	icon_asset_id = "rbxassetid://73332606434180",
	type = "Building",
	subtype = "Military Production",
	description = "Constructs siege equipment like catapults and rams.",
	cost = { Wood = 50, Stone = 30, Iron_Bars = 20 },
	construction = { build_time_seconds = 25 },
	size = Vector3.new(16, 10, 16),
	storage_capacity = { Wood = 200, Iron_Bars = 100 },
	components = {},
	produces_resource = "Siege_Equipment",
	production_rate = 0.3,
	requires_worker = true,
	worker_job_type = "Carpenter",
	consumes_resource = "Wood",
	consumption_rate = 5.0,
	maintenance_cost = { Gold = 3 },
} :: BuildingData

BuildingsData["Stables"] = {
	icon_asset_id = "rbxassetid://110188781053984",
	model_asset_name = "Storehouse",
	type = "Building",
	subtype = "Military Training",
	description = "Breeds and trains horses for cavalry units.",
	cost = { Wood = 40, Stone = 20 },
	construction = { build_time_seconds = 20 },
	size = Vector3.new(18, 10, 18),
	storage_capacity = { Food = 150 },
	components = {},
	can_train_units = { "Knight", "Cavalry" },
	max_queue_size = 5,
	maintenance_cost = { Food = 2, Gold = 2 },
} :: BuildingData

BuildingsData["Archery Range"] = {
	icon_asset_id = "rbxassetid://86272485851338",
	model_asset_name = "Watch_Tower",
	type = "Building",
	subtype = "Military Training",
	description = "Trains skilled archers for ranged combat.",
	cost = { Wood = 30, Stone = 15 },
	construction = { build_time_seconds = 15 },
	size = Vector3.new(16, 8, 16),
	storage_capacity = { Weapons = 30 },
	components = {},
	can_train_units = { "Archer", "Longbowman" },
	max_queue_size = 8,
	maintenance_cost = { Weapons = 1 },
} :: BuildingData

-- ========================================
-- INDUSTRY CATEGORY (9 buildings)
-- ========================================

BuildingsData["Lumberjack"] = {
	model_asset_name = "Lumberjack",
	icon_asset_id = "rbxassetid://140380384038217",
	type = "Building",
	subtype = "Resource Gathering",
	description = "Chops wood from nearby trees.",
	cost = { Wood = 5 },
	construction = { build_time_seconds = 7 },
	size = Vector3.new(10, 8, 10),
	storage_capacity = { Wood = 30 },
	components = {},
	produces_resource = "Wood",
	production_rate = 1,
	requires_worker = true,
	worker_job_type = "Woodcutter",
	worker_points = {
		entrance_point = "BuildingEntrance",
		rest_point = "WorkerRestPosition",
		production_point = "ProductionStation",
		dropoff_point = "ResourceDropoff",
		pickup_point = "ResourcePickup",
	},
} :: BuildingData

BuildingsData["Stone Quarry"] = {
	icon_asset_id = "rbxassetid://98679684747169",
	model_asset_name = nil,
	type = "Building",
	subtype = "Resource Gathering",
	description = "Extracts stone from the ground for construction.",
	cost = { Wood = 10 },
	construction = { build_time_seconds = 10 },
	size = Vector3.new(12, 8, 12),
	storage_capacity = { Stone = 100 },
	components = {},
	produces_resource = "Stone",
	production_rate = 0.8,
	requires_worker = true,
	worker_job_type = "Stonemason",
	worker_points = {
		entrance_point = "BuildingEntrance",
		rest_point = "WorkerRestPosition",
		production_point = "ProductionStation",
		dropoff_point = "ResourceDropoff",
		pickup_point = "ResourcePickup",
	},
} :: BuildingData

BuildingsData["Iron Mine"] = {
	model_asset_name = nil,
	icon_asset_id = "rbxassetid://139798646970990",
	type = "Building",
	subtype = "Resource Gathering",
	description = "Extracts iron ore from the ground for smelting into bars.",
	cost = { Wood = 20, Stone = 15 },
	construction = { build_time_seconds = 12 },
	size = Vector3.new(14, 10, 14),
	storage_capacity = { Iron_Ore = 100 },
	components = {},
	produces_resource = "Iron_Ore",
	production_rate = 0.6,
	requires_worker = true,
	worker_job_type = "Miner",
	maintenance_cost = { Wood = 1 },
	worker_points = {
		entrance_point = "BuildingEntrance",
		rest_point = "WorkerRestPosition",
		production_point = "ProductionStation",
		dropoff_point = "ResourceDropoff",
		pickup_point = "ResourcePickup",
	},
} :: BuildingData

BuildingsData["Storehouse"] = {
	model_asset_name = "Storehouse",
	icon_asset_id = "rbxassetid://107764241553638",
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
	storage_points = {
		Wood = "StorageAreaWood",
		Stone = "StorageAreaStone",
		Iron_Bars = "StorageAreaIron",
		Weapons = "StorageAreaWeapons",
		default = "StorageAreaGeneral",
	},
} :: BuildingData

BuildingsData["Market"] = {
	model_asset_name = nil,
	icon_asset_id = "rbxassetid://84787173399607",
	type = "Building",
	subtype = "Commerce",
	description = "A marketplace for trading goods and boosting your economy.",
	cost = { Wood = 40, Stone = 30, Gold = 20 },
	construction = { build_time_seconds = 20 },
	size = Vector3.new(16, 12, 16),
	storage_capacity = {
		Wood = 200,
		Stone = 200,
		Gold = 500,
		Food = 200,
		Iron_Ore = 100,
		Iron_Bars = 100,
		Weapons = 50,
	},
	components = {},
	popularity_impact = 10,
	requires_worker = true,
	worker_job_type = "Merchant",
	maintenance_cost = { Gold = 3 },
} :: BuildingData

BuildingsData["Trading Post"] = {
	model_asset_name = nil,
	icon_asset_id = "rbxassetid://139451405967316",
	type = "Building",
	subtype = "Commerce",
	description = "A major trading hub for international commerce.",
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
	},
	components = {},
	popularity_impact = 15,
	requires_worker = true,
	worker_job_type = "Trader",
	maintenance_cost = { Gold = 5 },
} :: BuildingData

BuildingsData["Tannery"] = {
	model_asset_name = "Tannery",
	icon_asset_id = "rbxassetid://120102902002796",
	type = "Building",
	subtype = "Production",
	description = "Processes hides into leather for armor and goods.",
	cost = { Wood = 20, Stone = 10 },
	construction = { build_time_seconds = 12 },
	size = Vector3.new(12, 8, 12),
	storage_capacity = { Leather = 100 },
	components = {},
	produces_resource = "Leather",
	production_rate = 0.8,
	requires_worker = true,
	worker_job_type = "Tanner",
	popularity_impact = -2,
	maintenance_cost = { Wood = 0.5 },
} :: BuildingData

BuildingsData["Carpenter"] = {
	model_asset_name = "Carpenter",
	icon_asset_id = "rbxassetid://126936515262150",
	type = "Building",
	subtype = "Production",
	description = "Crafts furniture and wooden goods from lumber.",
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
	worker_job_type = "Carpenter",
	consumes_resource = "Wood",
	consumption_rate = 2.5,
	popularity_impact = 2,
} :: BuildingData

BuildingsData["Coal Mine"] = {
	icon_asset_id = "rbxassetid://133760178879723",
	model_asset_name = nil,
	type = "Building",
	subtype = "Resource Gathering",
	description = "Extracts coal for fuel and smelting operations.",
	cost = { Wood = 25, Stone = 20 },
	construction = { build_time_seconds = 15 },
	size = Vector3.new(14, 10, 14),
	storage_capacity = { Coal = 150 },
	components = {},
	produces_resource = "Coal",
	production_rate = 0.7,
	requires_worker = true,
	worker_job_type = "Miner",
	maintenance_cost = { Wood = 1 },
} :: BuildingData

-- ========================================
-- FOOD CATEGORY (9 buildings)
-- ========================================

BuildingsData["Potato Farm"] = {
	model_asset_name = "Pig_Farm",
	icon_asset_id = "rbxassetid://121788531004289",
	type = "Building",
	subtype = "Food Production",
	description = "Grows potatoes to feed your people.",
	cost = { Wood = 15 },
	construction = { build_time_seconds = 10 },
	size = Vector3.new(16, 6, 16),
	storage_capacity = { Food = 150 },
	components = {},
	produces_resource = "Food",
	production_rate = 2,
	production_time = 5, -- 5 seconds per food unit
	production_output = 1, -- Produces 1 food per cycle
	requires_worker = true,
	worker_job_type = "Farmer",
	worker_points = {
		entrance_point = "BuildingEntrance",
		production_point = "ProductionStation",
		dropoff_point = "ResourceDropoff",
		pickup_point = "ResourcePickup",
	},
	maintenance_cost = { Wood = 0.5 },
} :: BuildingData

BuildingsData["Sheep Farm"] = {
	model_asset_name = "Sheep_Farm",
	icon_asset_id = "rbxassetid://137615559583462",
	type = "Building",
	subtype = "Food Production",
	description = "Raises sheep for wool and mutton.",
	cost = { Wood = 15 },
	construction = { build_time_seconds = 10 },
	size = Vector3.new(16, 6, 16),
	storage_capacity = { Food = 150 },
	components = {},
	produces_resource = "Food",
	production_rate = 2,
	production_time = 5, -- 5 seconds per food unit
	production_output = 1, -- Produces 1 food per cycle
	requires_worker = true,
	worker_job_type = "Farmer",
	worker_points = {
		entrance_point = "BuildingEntrance",
		production_point = "ProductionStation",
		dropoff_point = "ResourceDropoff",
		pickup_point = "ResourcePickup",
	},
	maintenance_cost = { Wood = 0.5 },
} :: BuildingData

BuildingsData["Cow Farm"] = {
	model_asset_name = "Cow_Farm",
	icon_asset_id = "rbxassetid://107699847865234",
	type = "Building",
	subtype = "Food Production",
	description = "Raises cattle for milk and beef.",
	cost = { Wood = 15 },
	construction = { build_time_seconds = 10 },
	size = Vector3.new(16, 6, 16),
	storage_capacity = { Food = 150 },
	components = {},
	produces_resource = "Food",
	production_rate = 2,
	production_time = 5, -- 5 seconds per food unit
	production_output = 1, -- Produces 1 food per cycle
	requires_worker = true,
	worker_job_type = "Farmer",
	worker_points = {
		entrance_point = "BuildingEntrance",
		production_point = "ProductionStation",
		dropoff_point = "ResourceDropoff",
		pickup_point = "ResourcePickup",
	},
	maintenance_cost = { Wood = 0.5 },
} :: BuildingData

BuildingsData["Fishermans Hut"] = {
	model_asset_name = "Fisherman_Shop",
	icon_asset_id = "rbxassetid://95096184225268",
	type = "Building",
	subtype = "Food Production",
	description = "Catches fish from nearby waters.",
	cost = { Wood = 10 },
	construction = { build_time_seconds = 7 },
	size = Vector3.new(8, 6, 8),
	storage_capacity = { Food = 80 },
	components = {},
	produces_resource = "Food",
	production_rate = 1.5,
	requires_worker = true,
	worker_job_type = "Fisherman",
} :: BuildingData

BuildingsData["Windmill"] = {
	model_asset_name = "Windmill",
	icon_asset_id = "rbxassetid://107124802842878",
	type = "Building",
	subtype = "Food Processing",
	description = "Grinds grain into flour, increasing food production efficiency.",
	cost = { Wood = 30, Stone = 20 },
	construction = { build_time_seconds = 15 },
	size = Vector3.new(12, 18, 12),
	storage_capacity = {
		Food = 200,
		Flour = 250,
	},
	components = {},
	produces_resource = "Flour",
	production_rate = 2.0,
	requires_worker = true,
	worker_job_type = "Miller",
	consumes_resource = "Food",
	consumption_rate = 2.5,
	popularity_impact = 3,
	maintenance_cost = { Wood = 1.5 },
} :: BuildingData

BuildingsData["Water Mill"] = {
	model_asset_name = "Windmill",
	icon_asset_id = "rbxassetid://135120458084588",
	type = "Building",
	subtype = "Food Processing",
	description = "Water-powered mill that grinds grain more efficiently than windmills.",
	cost = { Wood = 40, Stone = 30 },
	construction = { build_time_seconds = 18 },
	size = Vector3.new(14, 12, 14),
	storage_capacity = {
		Food = 250,
		Flour = 300,
	},
	components = {},
	produces_resource = "Flour",
	production_rate = 2.5,
	requires_worker = true,
	worker_job_type = "Miller",
	consumes_resource = "Food",
	consumption_rate = 3.0,
	popularity_impact = 4,
} :: BuildingData

BuildingsData["Bakery"] = {
	icon_asset_id = "rbxassetid://94032723454113",
	model_asset_name = "Bakery",
	type = "Building",
	subtype = "Food Processing",
	description = "Bakes bread from flour to feed your people.",
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
	worker_job_type = "Baker",
	consumes_resource = "Food",
	consumption_rate = 2.0,
	popularity_impact = 2,
	maintenance_cost = { Wood = 1 },
} :: BuildingData

BuildingsData["Brewery"] = {
	model_asset_name = "Brewery",
	icon_asset_id = "rbxassetid://112274545445247",
	type = "Building",
	subtype = "Food Processing",
	description = "Brews ale from grain to boost morale.",
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
	worker_job_type = "Brewer",
	consumes_resource = "Food",
	consumption_rate = 1.5,
	popularity_impact = 5,
	maintenance_cost = { Wood = 1 },
} :: BuildingData

BuildingsData["Granary"] = {
	model_asset_name = "Granary",
	icon_asset_id = "rbxassetid://89283451013010",
	type = "Building",
	subtype = "Storage",
	description = "Stores large quantities of food to prevent famine.",
	cost = { Wood = 15, Stone = 5 },
	construction = { build_time_seconds = 8 },
	size = Vector3.new(10, 12, 10),
	storage_capacity = { Food = 1000 },
	components = {},
} :: BuildingData

BuildingsData["Tavern"] = {
	model_asset_name = "Tavern",
	icon_asset_id = "rbxassetid://117430433542766",
	type = "Building",
	subtype = "Food & Entertainment",
	description = "Serves food and drink, boosting morale and happiness.",
	cost = { Wood = 25, Stone = 15 },
	construction = { build_time_seconds = 12 },
	size = Vector3.new(14, 10, 14),
	storage_capacity = {
		Ale = 100,
		Food = 50,
	},
	components = {},
	popularity_impact = 8,
	requires_worker = true,
	worker_job_type = "Innkeeper",
	consumes_resource = "Ale",
	consumption_rate = 1.5,
	maintenance_cost = { Gold = 2 },
} :: BuildingData

BuildingsData["Mead Hall"] = {
	model_asset_name = "Mead_Hall",
	type = "Building",
	subtype = "Food & Entertainment",
	description = "A grand feasting hall where warriors gather and celebrate.",
	cost = { Wood = 60, Stone = 40, Gold = 30 },
	construction = { build_time_seconds = 25 },
	size = Vector3.new(24, 14, 16),
	storage_capacity = {
		Ale = 300,
		Food = 200,
		Bread = 150,
	},
	components = {},
	popularity_impact = 20,
	requires_worker = true,
	worker_job_type = "Innkeeper",
	consumes_resource = "Ale",
	consumption_rate = 2.5,
	can_train_units = { "Warrior" },
	max_queue_size = 5,
	maintenance_cost = { Gold = 5, Food = 2 },
} :: BuildingData

-- ========================================
-- HOUSING CATEGORY (9 buildings)
-- ========================================

BuildingsData["Hovel"] = {
	model_asset_name = "Houses/House",
	icon_asset_id = "rbxassetid://75687515930735",
	type = "Building",
	subtype = "Housing",
	description = "Basic housing for peasants and workers.",
	cost = { Wood = 10 },
	construction = { build_time_seconds = 5 },
	size = Vector3.new(8, 6, 8),
	storage_capacity = {},
	components = {},
	housing_capacity = 5,
} :: BuildingData

BuildingsData["Clachan"] = {
	model_asset_name = "Houses/House",
	icon_asset_id = "rbxassetid://77258138200424",
	type = "Building",
	subtype = "Housing",
	description = "A traditional Irish hamlet providing housing for multiple families.",
	cost = { Wood = 15, Stone = 10 },
	construction = { build_time_seconds = 8 },
	size = Vector3.new(12, 8, 12),
	storage_capacity = {},
	components = {},
	housing_capacity = 8,
	popularity_impact = 3,
} :: BuildingData

BuildingsData["Inn"] = {
	model_asset_name = "Inn",
	icon_asset_id = "rbxassetid://129541712931688",
	type = "Building",
	subtype = "Housing & Entertainment",
	description = "Provides lodging for travelers and boosts town prosperity.",
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
	housing_capacity = 3,
	requires_worker = true,
	worker_job_type = "Innkeeper",
	consumes_resource = "Bread",
	consumption_rate = 1.0,
	maintenance_cost = { Gold = 3 },
} :: BuildingData

BuildingsData["Monastery"] = {
	model_asset_name = "Scriptorium",
	icon_asset_id = "rbxassetid://71819233212880",
	type = "Building",
	subtype = "Religious Housing",
	description = "A religious community where monks live, pray, and create manuscripts.",
	cost = { Wood = 50, Stone = 80, Gold = 50 },
	construction = { build_time_seconds = 40 },
	size = Vector3.new(24, 16, 24),
	storage_capacity = {
		Gold = 300,
		Food = 200,
	},
	components = {},
	popularity_impact = 20,
	housing_capacity = 10,
	requires_worker = true,
	worker_job_type = "Monk",
	produces_resource = "Manuscripts",
	production_rate = 0.5,
	maintenance_cost = { Gold = 5, Food = 3 },
} :: BuildingData

BuildingsData["Chapel"] = {
	model_asset_name = "Church",
	type = "Building",
	subtype = "Religious",
	description = "A small place of worship that boosts happiness and faith.",
	cost = { Wood = 20, Stone = 30 },
	construction = { build_time_seconds = 15 },
	size = Vector3.new(12, 14, 14),
	storage_capacity = {},
	components = {},
	popularity_impact = 6,
	requires_worker = true,
	worker_job_type = "Priest",
	housing_capacity = 2,
	maintenance_cost = { Gold = 1 },
} :: BuildingData

BuildingsData["Church"] = {
	model_asset_name = "Church",
	icon_asset_id = "rbxassetid://78616440553125",
	type = "Building",
	subtype = "Religious",
	description = "A grand cathedral that serves as the spiritual center of your settlement.",
	cost = { Wood = 40, Stone = 60, Gold = 30 },
	construction = { build_time_seconds = 30 },
	size = Vector3.new(18, 20, 24),
	storage_capacity = { Gold = 200 },
	components = {},
	popularity_impact = 15,
	requires_worker = true,
	worker_job_type = "Priest",
	maintenance_cost = { Gold = 4 },
} :: BuildingData

BuildingsData["Town Hall"] = {
	model_asset_name = "Mead_Hall",
	icon_asset_id = "rbxassetid://86049079133631",
	type = "Building",
	subtype = "Administrative",
	description = "The administrative center where town leaders meet and make decisions.",
	cost = { Wood = 60, Stone = 80, Gold = 40 },
	construction = { build_time_seconds = 35 },
	size = Vector3.new(20, 16, 20),
	storage_capacity = { Gold = 500 },
	components = {},
	popularity_impact = 10,
	requires_worker = true,
	worker_job_type = "Administrator",
	maintenance_cost = { Gold = 6 },
	deletion_confirmation_required = true,
} :: BuildingData

BuildingsData["Scriptorium"] = {
	icon_asset_id = "rbxassetid://111961701907261",
	model_asset_name = "Scriptorium",
	type = "Building",
	subtype = "Cultural",
	description = "Where scribes copy and illuminate manuscripts, preserving knowledge.",
	cost = { Wood = 30, Stone = 20, Gold = 20 },
	construction = { build_time_seconds = 15 },
	size = Vector3.new(12, 10, 12),
	storage_capacity = {},
	components = {},
	produces_resource = "Manuscripts",
	production_rate = 0.8,
	requires_worker = true,
	worker_job_type = "Scribe",
	popularity_impact = 5,
	maintenance_cost = { Gold = 2 },
} :: BuildingData

BuildingsData["Celtic Cross"] = {
	model_asset_name = "Honor_Statue",
	icon_asset_id = "rbxassetid://103812313156833",
	type = "Building",
	subtype = "Religious Monument",
	description = "An iconic Irish Christian symbol that inspires faith and unity.",
	cost = { Stone = 30, Gold = 15 },
	construction = { build_time_seconds = 12 },
	size = Vector3.new(4, 12, 4),
	storage_capacity = {},
	components = {},
	popularity_impact = 8,
	deletion_confirmation_required = false,
} :: BuildingData

-- ========================================
-- AUTO-POPULATE WORKER POINTS
-- ========================================
-- Automatically add worker_points to all production buildings that don't have them explicitly set
-- This ensures backward compatibility while allowing custom configurations

for buildingName, buildingData in BuildingsData do
	-- Add standard worker points to all buildings that require workers but don't have explicit worker_points
	if buildingData.requires_worker and not buildingData.worker_points then
		buildingData.worker_points = WorkerPointsConfig.STANDARD_PRODUCTION
	end

	-- Add storage points to buildings with storage capacity but no explicit storage_points
	if buildingData.storage_capacity and not buildingData.storage_points then
		local hasMultipleResourceTypes = 0
		for _ in buildingData.storage_capacity do
			hasMultipleResourceTypes = hasMultipleResourceTypes + 1
		end

		-- Only add storage points if building stores multiple resource types
		if hasMultipleResourceTypes >= 3 then
			buildingData.storage_points = WorkerPointsConfig.STANDARD_STORAGE_FULL
		elseif buildingData.storage_capacity.Food and hasMultipleResourceTypes <= 2 then
			buildingData.storage_points = WorkerPointsConfig.STORAGE_FOOD_ONLY
		elseif buildingData.storage_capacity.Weapons then
			buildingData.storage_points = WorkerPointsConfig.STORAGE_MILITARY
		else
			buildingData.storage_points = WorkerPointsConfig.STORAGE_GENERAL
		end
	end
end

return BuildingsData
