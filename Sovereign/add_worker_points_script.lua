-- Script to add worker_points and storage_points to BuildingsData.luau
-- This is a helper script to batch-add configurations

-- Buildings that need worker_points (production buildings)
local production_buildings = {
	"Arrow Tower",
	"Smelter",
	"Weaponsmith",
	"Siege Workshop",
	"Market",
	"Trading Post",
	"Tannery",
	"Carpenter",
	"Coal Mine",
	"Potato Farm",
	"Sheep Farm",
	"Cow Farm",
	"Fishermans Hut",
	"Windmill",
	"Water Mill",
	"Bakery",
	"Brewery",
	"Tavern",
	"Mead Hall",
	"Inn",
	"Monastery",
	"Chapel",
	"Church",
	"Town Hall",
	"Scriptorium",
}

-- Worker points template
local worker_points_template = [[
	worker_points = {
		entrance_point = "BuildingEntrance",
		rest_point = "WorkerRestPosition",
		production_point = "ProductionStation",
		dropoff_point = "ResourceDropoff",
		pickup_point = "ResourcePickup",
	},]]

-- Buildings that need storage_points (storage buildings)
local storage_buildings = {
	{
		name = "Armory",
		points = {
			Weapons = "StorageAreaWeapons",
			Iron_Bars = "StorageAreaIron",
			default = "StorageAreaGeneral",
		}
	},
	{
		name = "Granary",
		points = {
			Food = "StorageAreaFood",
			default = "StorageAreaGeneral",
		}
	},
}

print("Production buildings that need worker_points:", table.concat(production_buildings, ", "))
print("\nStorage buildings that need storage_points:")
for _, building in ipairs(storage_buildings) do
	print("  -", building.name)
end

print("\n\nFor each production building, add this before '} :: BuildingData':")
print(worker_points_template)
