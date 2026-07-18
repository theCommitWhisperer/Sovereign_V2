--!strict
-- WorkerPointsConfig: Default worker point configurations
-- This module provides standard worker point configurations that can be used in BuildingsData

local WorkerPointsConfig = {}

-- Standard worker points for production buildings
-- These are the default point names that WorkerPointSystem will look for
WorkerPointsConfig.STANDARD_PRODUCTION = {
	entrance_point = "BuildingEntrance",
	rest_point = "WorkerRestPosition",
	production_point = "ProductionStation",
	dropoff_point = "ResourceDropoff",
	pickup_point = "ResourcePickup",
}

-- Standard storage points for multi-resource storage buildings (Keep, Storehouse, Market, etc.)
WorkerPointsConfig.STANDARD_STORAGE_FULL = {
	Wood = "StorageAreaWood",
	Stone = "StorageAreaStone",
	Food = "StorageAreaFood",
	Iron_Ore = "StorageAreaIron",
	Iron_Bars = "StorageAreaIron",
	Gold = "StorageAreaGold",
	Weapons = "StorageAreaWeapons",
	default = "StorageAreaGeneral",
}

-- Storage points for granaries (food only)
WorkerPointsConfig.STORAGE_FOOD_ONLY = {
	Food = "StorageAreaFood",
	Bread = "StorageAreaFood",
	Flour = "StorageAreaFood",
	Ale = "StorageAreaFood",
	default = "StorageAreaGeneral",
}

-- Storage points for armories (weapons and iron)
WorkerPointsConfig.STORAGE_MILITARY = {
	Weapons = "StorageAreaWeapons",
	Iron_Bars = "StorageAreaIron",
	default = "StorageAreaGeneral",
}

-- Storage points for warehouses (general goods)
WorkerPointsConfig.STORAGE_GENERAL = {
	Wood = "StorageAreaWood",
	Stone = "StorageAreaStone",
	Iron_Bars = "StorageAreaIron",
	Weapons = "StorageAreaWeapons",
	default = "StorageAreaGeneral",
}

return WorkerPointsConfig
