--!strict
-- MapEditorTypes: Shared type definitions for the in-game map editor

local MapEditorTypes = {}

-- Legacy brush stroke (kept for backward compatibility with saved maps)
export type BrushStroke = {
	Position: { X: number, Z: number },
	Radius: number,
	Material: string, -- Enum.Material name as string (e.g. "Grass")
	Shape: string, -- "Block" or "Ball"
	SizeY: number, -- Height of the fill
}

-- New sculpt stroke for terrain height editing
export type SculptStroke = {
	Position: { X: number, Y: number, Z: number }, -- 3D hit position on terrain
	Radius: number, -- Brush radius in studs
	Strength: number, -- 0.1 to 1.0: how much occupancy to change per stroke
	Hardness: number, -- 0.0 to 1.0: 0=soft Gaussian falloff, 1=hard flat edge
	Mode: string, -- "Raise" | "Lower" | "Flatten" | "Paint"
	Shape: string, -- "Circle" | "Square"
	Material: string, -- Material name (used in Paint mode, and as fill material for Raise)
}

export type PlacedFeature = {
	Id: string, -- Unique ID
	FeatureType: string, -- "Mountain", "Lake", "River", "Forest", "Hill", "Rock"
	Position: { X: number, Y: number, Z: number },
	Scale: number, -- 0.5 to 2.0 multiplier
	Rotation: number, -- Y-axis rotation in degrees
}

-- A painted resource patch on the map (XZ plane only)
export type ResourcePatch = {
	Id: string, -- Unique ID
	ResourceType: string, -- "Wood" | "Stone" | "Food" | "Iron_Ore"
	ZoneOwner: number?, -- 0=Neutral, 1=P1, 2=P2, 3=P3, 4=P4
	Position: { X: number, Z: number }, -- Center of the patch
	Radius: number, -- Patch radius in studs
	Density: number?, -- Spawn density hint (1-10)
}

-- A painted zone stroke (player territory, neutral, or map-feature zone)
export type ZonePaintStroke = {
	-- 0=Neutral, 1-4=Player zones, 5=Impassable, 6=No Build
	Zone: number,
	Position: { X: number, Z: number }, -- Center of stroke
	Radius: number, -- Brush radius in studs
	Shape: string, -- "Circle" | "Square"
}

-- A polygon zone region defined by a list of vertices (XZ plane)
export type ZonePolygon = {
	-- 0=Neutral, 1-4=Player zones, 5=Impassable, 6=No Build
	Zone: number,
	Vertices: { { X: number, Z: number } },   -- Ordered vertex list, at least 3
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
	BrushStrokes: { BrushStroke }, -- Legacy paint strokes
	SculptStrokes: { SculptStroke }, -- Sculpt strokes (raise/lower/flatten/paint)
	Features: { PlacedFeature },
	SpawnZones: { SpawnZoneConfig },
	ResourcePatches: { ResourcePatch }?, -- Placed resource patches
	ZonePaintStrokes: { ZonePaintStroke }?, -- Zone territory paint strokes (brush + rasterized polygons)
	ZonePolygons: { ZonePolygon }?, -- Zone polygon regions (raw vertices for re-editing)

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

-- Sculpt brush modes
MapEditorTypes.BrushModes = { "Raise", "Lower", "Flatten", "Paint" }

-- Sculpt brush shapes
MapEditorTypes.BrushShapes = { "Circle", "Square" }

-- Resource types for placement tool
MapEditorTypes.RESOURCE_TYPES = {
	{ name = "Wood",     resourceType = "Wood",     color = { 60, 140, 40 } },
	{ name = "Stone",    resourceType = "Stone",    color = { 160, 155, 150 } },
	{ name = "Food",     resourceType = "Food",     color = { 200, 180, 50 } },
	{ name = "Iron Ore", resourceType = "Iron_Ore", color = { 110, 80, 70 } },
}

-- Zone paint zones.
-- Zone IDs 0-4 are territory zones (Neutral + 4 players).
-- Zone IDs 5-6 are map-feature zones that affect gameplay rules but are
-- NOT included in the equal-balance budget check:
--   5 = Impassable  — mountains / deep water / cliffs (no units, no building)
--   6 = No Build    — traversable terrain where construction is blocked
--                     (narrow passes, shorelines, bridge approaches)
MapEditorTypes.ZONE_TYPES = {
	{ name = "Neutral",    zone = 0, color = { 140, 120, 80 } },
	{ name = "Player 1",  zone = 1, color = { 80, 120, 200 } },
	{ name = "Player 2",  zone = 2, color = { 200, 80, 80 } },
	{ name = "Player 3",  zone = 3, color = { 80, 180, 80 } },
	{ name = "Player 4",  zone = 4, color = { 200, 160, 40 } },
	{ name = "Impassable", zone = 5, color = { 60, 55, 65 } },   -- dark slate
	{ name = "No Build",   zone = 6, color = { 190, 110, 40 } }, -- warm amber
}

-- Convenience set: zone IDs that are territory (participate in balance budget).
MapEditorTypes.TERRITORY_ZONE_IDS = { 0, 1, 2, 3, 4 }
-- Zone IDs that are map-feature overlays (do not participate in balance).
MapEditorTypes.FEATURE_ZONE_IDS = { 5, 6 }

-- Editor tool enum
MapEditorTypes.Tools = {
	Select = "Select",
	TerrainBrush = "TerrainBrush",
	Eraser = "Eraser",
	FeaturePlace = "FeaturePlace",
	Resources = "Resources",
	ZonePaint = "ZonePaint",
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
		SculptStrokes = {},
		Features = {},
		ResourcePatches = {},
		ZonePaintStrokes = {},
		ZonePolygons = {},
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
