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
	-- Preview colors for lobby minimap rendering
	PreviewColors: {
		Base: { number },       -- RGB for base terrain
		Water: { number }?,     -- RGB for water features
		Mountain: { number }?,  -- RGB for mountains
		Forest: { number }?,    -- RGB for forests
		Accent: { number }?,    -- RGB for accent features
	},
	-- Optional screenshot image shown in lobby map preview (rbxassetid://...)
	-- When set, replaces the procedural terrain rendering.
	PreviewImage: string?,
	-- Optional: hand-placed Keep spawn positions (one per player zone).
	-- When present, overrides the calculated quadrant-corner spawn point.
	-- Players spawn here and this is the suggested Keep placement area.
	KeepSpawnZones: {
		{ Zone: number, X: number, Y: number, Z: number, Radius: number }
	}?,
}

local MapData = {}

-- Standard 4-player maps
MapData.Maps = {
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
		PreviewColors = {
			Base = { 100, 160, 70 },     -- Rich green
			Water = { 50, 120, 200 },
			Mountain = { 140, 130, 120 },
			Forest = { 35, 90, 25 },
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
		PreviewColors = {
			Base = { 90, 160, 90 },      -- Island green
			Water = { 40, 100, 180 },
			Forest = { 30, 80, 20 },
			Accent = { 220, 200, 150 },  -- Sandy beaches
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
		PreviewColors = {
			Base = { 200, 180, 120 },    -- Sandy desert
			Water = { 50, 120, 200 },
			Mountain = { 160, 140, 100 },
			Accent = { 180, 160, 100 },  -- Dunes
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
		PreviewColors = {
			Base = { 110, 140, 80 },     -- Arena green
			Forest = { 40, 100, 30 },
			Accent = { 160, 150, 140 },  -- Stone walls
		},
	} :: MapConfig,

	-- Studio-built archipelago map — terrain is hand-crafted in Roblox Studio.
	-- Spawn zones and resource patches are painted via the in-game map editor.
	-- Requires UseStudioTerrain BoolValue = true in Workspace.
	["TheIslands"] = {
		Name = "The Islands",
		Description = "A hand-crafted archipelago map with rivers, mountains, and flat harbours.",
		Size = 1600,
		TerrainType = "Islands",
		MaxPlayers = 4,
		QuadrantSize = 650,
		NeutralZoneWidth = 150,
		SpawnHeight = 15,
		ResourceDensity = {
			Wood = 20,
			Stone = 15,
			Food = 10,
			Iron_Ore = 8,
		},
		Features = {
			HasCentralLake = false,
			HasMountains = true,
			HasForests = true,
			HasRivers = true,
		},
		PreviewColors = {
			Base = { 90, 160, 90 },
			Water = { 40, 100, 180 },
			Mountain = { 130, 120, 110 },
			Forest = { 35, 95, 25 },
		},
		PreviewImage = "rbxassetid://99833618647614",
		KeepSpawnZones = {
			{ Zone = 1, X = 725.1, Y = 28.0, Z = 790.5, Radius = 400.0 },
			{ Zone = 2, X = -526.0, Y = 29.2, Z = 800.8, Radius = 400.0 },
			{ Zone = 3, X = 235.2, Y = 27.1, Z = -786.6, Radius = 400.0 },
			{ Zone = 4, X = 819.6, Y = 27.4, Z = -158.0, Radius = 400.0 },
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
		PreviewColors = {
			Base = { 130, 140, 120 },    -- Rocky highland
			Water = { 50, 120, 200 },
			Mountain = { 100, 95, 85 },
			Accent = { 80, 75, 65 },     -- Dark rock
		},
	} :: MapConfig,
}

-- Sentinel entry used when a player selects one of their own editor-saved maps in the lobby.
-- GameManager detects this key and loads the real data from DataStore via customMapId/customMapAuthorId.
MapData.Maps["__custom__"] = {
	Name = "Custom Map",
	Description = "A player-created map loaded from the map editor.",
	Size = 1000,
	TerrainType = "Custom",
	MaxPlayers = 4,
	QuadrantSize = 400,
	NeutralZoneWidth = 100,
	SpawnHeight = 10,
	ResourceDensity = { Wood = 20, Stone = 15, Food = 10, Iron_Ore = 8 },
	Features = { HasCentralLake = false, HasMountains = false, HasForests = false, HasRivers = false },
	PreviewColors = { Base = { 100, 160, 100 } },
} :: MapConfig

-- Default map for new games
MapData.DefaultMap = "LargeContinent"

-- Get map configuration by name
function MapData.getMap(mapName: string): MapConfig?
	return MapData.Maps[mapName]
end

-- Get list of available maps (excludes __custom__ sentinel — shown separately in lobby)
function MapData.getMapList(): { string }
	local mapList = {}
	for mapName, _ in pairs(MapData.Maps) do
		if mapName ~= "__custom__" then
			table.insert(mapList, mapName)
		end
	end
	table.sort(mapList)
	return mapList
end

return MapData
