--!strict
-- MapData: Configuration for different maps/arenas

export type MapConfig = {
	Name: string,
	Description: string,
	-- Map size in studs
	Size: number,
	-- Terrain type (affects visuals and potentially gameplay)
	TerrainType: string,
	-- Number of player spawn quadrants
	MaxPlayers: number,
	-- Quadrant configuration
	QuadrantSize: number,
	NeutralZoneWidth: number,
	SpawnHeight: number,
	-- Resource distribution
	ResourceDensity: {
		Wood: number,
		Stone: number,
		Food: number,
		Iron_Ore: number,
	},
	-- Special features
	Features: {
		HasCentralLake: boolean?,
		HasMountains: boolean?,
		HasForests: boolean?,
		HasRivers: boolean?,
	},
}

local MapData = {}

-- Standard 4-player maps
MapData.Maps = {
	-- Classic balanced map
	["ClassicPlains"] = {
		Name = "Classic Plains",
		Description = "A balanced 4-player map with open plains and scattered resources.",
		Size = 1000,
		TerrainType = "Plains",
		MaxPlayers = 4,
		QuadrantSize = 400,
		NeutralZoneWidth = 100,
		SpawnHeight = 10,
		ResourceDensity = {
			Wood = 20, -- Number of wood nodes per estate
			Stone = 15,
			Food = 10,
			Iron_Ore = 8,
		},
		Features = {
			HasCentralLake = false,
			HasMountains = false,
			HasForests = true,
			HasRivers = false,
		},
	} :: MapConfig,

	-- Larger map for more strategic gameplay
	["LargeContinent"] = {
		Name = "Large Continent",
		Description = "A vast 4-player map with diverse terrain and abundant resources.",
		Size = 1500,
		TerrainType = "Mixed",
		MaxPlayers = 4,
		QuadrantSize = 600,
		NeutralZoneWidth = 150,
		SpawnHeight = 10,
		ResourceDensity = {
			Wood = 30,
			Stone = 25,
			Food = 15,
			Iron_Ore = 12,
		},
		Features = {
			HasCentralLake = true,
			HasMountains = true,
			HasForests = true,
			HasRivers = true,
		},
	} :: MapConfig,

	-- Smaller, faster-paced map
	["SmallIsland"] = {
		Name = "Small Island",
		Description = "A compact 4-player island for quick, intense matches.",
		Size = 700,
		TerrainType = "Island",
		MaxPlayers = 4,
		QuadrantSize = 280,
		NeutralZoneWidth = 70,
		SpawnHeight = 10,
		ResourceDensity = {
			Wood = 15,
			Stone = 10,
			Food = 8,
			Iron_Ore = 5,
		},
		Features = {
			HasCentralLake = true,
			HasMountains = false,
			HasForests = true,
			HasRivers = false,
		},
	} :: MapConfig,

	-- Resource-scarce map for challenging gameplay
	["BarrenWasteland"] = {
		Name = "Barren Wasteland",
		Description = "A harsh desert map with limited resources - fight for survival!",
		Size = 1000,
		TerrainType = "Desert",
		MaxPlayers = 4,
		QuadrantSize = 400,
		NeutralZoneWidth = 100,
		SpawnHeight = 10,
		ResourceDensity = {
			Wood = 8, -- Very scarce wood
			Stone = 20, -- Plenty of stone
			Food = 5, -- Limited food
			Iron_Ore = 12, -- More iron to compensate
		},
		Features = {
			HasCentralLake = true, -- Only water source
			HasMountains = true,
			HasForests = false, -- No forests
			HasRivers = false,
		},
	} :: MapConfig,

	-- 2-player duel map
	["DuelArena"] = {
		Name = "Duel Arena",
		Description = "A focused 2-player map for head-to-head competition.",
		Size = 600,
		TerrainType = "Arena",
		MaxPlayers = 2,
		QuadrantSize = 250,
		NeutralZoneWidth = 50,
		SpawnHeight = 10,
		ResourceDensity = {
			Wood = 15,
			Stone = 12,
			Food = 10,
			Iron_Ore = 8,
		},
		Features = {
			HasCentralLake = false,
			HasMountains = false,
			HasForests = true,
			HasRivers = false,
		},
	} :: MapConfig,

	-- Highland fortress map with strategic positions
	["HighlandFortress"] = {
		Name = "Highland Fortress",
		Description = "Mountainous terrain with elevated strategic positions.",
		Size = 1200,
		TerrainType = "Mountains",
		MaxPlayers = 4,
		QuadrantSize = 480,
		NeutralZoneWidth = 120,
		SpawnHeight = 10,
		ResourceDensity = {
			Wood = 12, -- Less wood in mountains
			Stone = 30, -- Abundant stone
			Food = 8,
			Iron_Ore = 15, -- Rich in iron
		},
		Features = {
			HasCentralLake = false,
			HasMountains = true,
			HasForests = false,
			HasRivers = true,
		},
	} :: MapConfig,
}

-- Default map for new games
MapData.DefaultMap = "ClassicPlains"

-- Get map configuration by name
function MapData.getMap(mapName: string): MapConfig?
	return MapData.Maps[mapName]
end

-- Get list of available maps
function MapData.getMapList(): { string }
	local mapList = {}
	for mapName, _ in pairs(MapData.Maps) do
		table.insert(mapList, mapName)
	end
	table.sort(mapList)
	return mapList
end

return MapData
