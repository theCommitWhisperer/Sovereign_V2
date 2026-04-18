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

-- Only shipped maps are listed here. Add a new entry when a map is fully built
-- in Studio and has a valid PreviewImage asset ID. Do not add placeholder maps.
MapData.Maps = {
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
MapData.DefaultMap = "TheIslands"

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
