--!strict
-- MapEditorTypes: Shared type definitions for the in-game map editor

local MapEditorTypes = {}

export type BrushStroke = {
	Position: { X: number, Z: number },
	Radius: number,
	Material: string, -- Enum.Material name as string (e.g. "Grass")
	Shape: string, -- "Block" or "Ball"
	SizeY: number, -- Height of the fill
}

export type PlacedFeature = {
	Id: string, -- Unique ID
	FeatureType: string, -- "Mountain", "Lake", "River", "Forest", "Hill", "Rock"
	Position: { X: number, Y: number, Z: number },
	Scale: number, -- 0.5 to 2.0 multiplier
	Rotation: number, -- Y-axis rotation in degrees
}

export type SpawnZoneConfig = {
	SpawnNumber: number, -- 1-4
	Center: { X: number, Z: number },
	HalfSize: number, -- Half the quadrant side length
}

export type CustomMapData = {
	-- Metadata
	MapId: string, -- "UserId_timestamp"
	AuthorId: number,
	AuthorName: string,
	Name: string,
	Description: string,
	CreatedAt: number,
	UpdatedAt: number,

	-- Base config
	Size: number, -- 600-1500 studs
	MaxPlayers: number, -- 2 or 4
	SpawnHeight: number,
	BaseMaterial: string, -- e.g. "Grass"
	NeutralZoneWidth: number,

	-- Editor data
	BrushStrokes: { BrushStroke },
	Features: { PlacedFeature },
	SpawnZones: { SpawnZoneConfig },

	-- Game config
	ResourceDensity: {
		Wood: number,
		Stone: number,
		Food: number,
		Iron_Ore: number,
	},

	-- Preview (for lobby minimap)
	PreviewColors: {
		Base: { number },
		Water: { number }?,
		Mountain: { number }?,
		Forest: { number }?,
	},
}

-- Available terrain materials for the brush
MapEditorTypes.TERRAIN_MATERIALS = {
	{ name = "Grass", material = "Grass", color = { 100, 180, 70 } },
	{ name = "Sand", material = "Sand", color = { 220, 200, 140 } },
	{ name = "Rock", material = "Rock", color = { 140, 130, 120 } },
	{ name = "Water", material = "Water", color = { 50, 120, 200 } },
	{ name = "Snow", material = "Snow", color = { 240, 245, 255 } },
	{ name = "Leafy Grass", material = "LeafyGrass", color = { 40, 120, 30 } },
	{ name = "Slate", material = "Slate", color = { 100, 100, 110 } },
	{ name = "Sandstone", material = "Sandstone", color = { 180, 160, 100 } },
	{ name = "Ground", material = "Ground", color = { 130, 110, 80 } },
}

-- Available feature types
MapEditorTypes.FEATURE_TYPES = {
	{ name = "Mountain", icon = "M" },
	{ name = "Lake", icon = "L" },
	{ name = "River", icon = "R" },
	{ name = "Forest", icon = "F" },
	{ name = "Hill", icon = "H" },
	{ name = "Rock", icon = "K" },
}

-- Editor tool enum
MapEditorTypes.Tools = {
	Select = "Select",
	TerrainBrush = "TerrainBrush",
	Eraser = "Eraser",
	FeaturePlace = "FeaturePlace",
	SpawnZones = "SpawnZones",
	Settings = "Settings",
}

-- Default new map config
function MapEditorTypes.createDefaultMap(authorId: number, authorName: string): CustomMapData
	return {
		MapId = tostring(authorId) .. "_" .. tostring(os.time()),
		AuthorId = authorId,
		AuthorName = authorName,
		Name = "Untitled Map",
		Description = "",
		CreatedAt = os.time(),
		UpdatedAt = os.time(),
		Size = 1000,
		MaxPlayers = 4,
		SpawnHeight = 10,
		BaseMaterial = "Grass",
		NeutralZoneWidth = 100,
		BrushStrokes = {},
		Features = {},
		SpawnZones = {
			{ SpawnNumber = 1, Center = { X = -275, Z = 275 }, HalfSize = 200 },
			{ SpawnNumber = 2, Center = { X = 275, Z = 275 }, HalfSize = 200 },
			{ SpawnNumber = 3, Center = { X = -275, Z = -275 }, HalfSize = 200 },
			{ SpawnNumber = 4, Center = { X = 275, Z = -275 }, HalfSize = 200 },
		},
		ResourceDensity = {
			Wood = 20,
			Stone = 15,
			Food = 10,
			Iron_Ore = 8,
		},
		PreviewColors = {
			Base = { 100, 180, 70 },
		},
	}
end

return MapEditorTypes
