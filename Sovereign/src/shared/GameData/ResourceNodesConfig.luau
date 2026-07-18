--!strict
-- ResourceNodesConfig: Production configuration for gatherable resource nodes.
-- Single source of truth for how each node type looks (which asset models it
-- uses), how much it yields, how it is laid out inside a resource patch, and
-- how it visually depletes.
--
-- Asset resolution: each entry in AssetFolders is a path (relative to
-- ReplicatedStorage.Assets) tried in order at runtime. The first folder that
-- exists and contains at least one usable template wins. If none resolve,
-- ResourceNodeFactory builds an improved procedural fallback so the game never
-- shows grey boxes.

export type DepletionStage = {
	-- Node enters this stage when ResourcesRemaining / MaxResources <= Threshold
	Threshold: number,
	-- Uniform model scale applied at this stage (relative to spawn scale)
	Scale: number,
	-- Transparency applied to all visual parts at this stage (0 = opaque)
	Transparency: number,
}

export type NodeTypeConfig = {
	-- Asset folder paths under ReplicatedStorage.Assets, tried in order.
	AssetFolders: { string },
	-- Template names to never use (unnamed placeholders, floor pieces, etc.)
	SkipTemplateNames: { [string]: boolean }?,

	-- Economy
	MaxResources: number,

	-- Placement inside a patch circle
	-- One node per this many square studs at Density = 5 (editor baseline).
	AreaPerNode: number,
	-- Hard limits per patch regardless of area/density
	MinPerPatch: number,
	MaxPerPatch: number,
	-- Minimum spacing between node origins (studs); prevents overlapping clones
	MinSpacing: number,

	-- Visuals
	-- Absolute world height (studs) nodes are normalised to, regardless of the
	-- source mesh's native size. Prevents oversized asset meshes from eating
	-- buildable space.
	TargetHeight: number,
	-- Random height variation as a fraction (0.25 = ±25%)
	HeightJitter: number,
	-- Whether the node's hitbox blocks movement (trunks yes, wheat no)
	Collides: boolean,
	-- Approximate hitbox footprint (studs) when the template bounding box is
	-- unreasonably large (wide canopies etc.). nil = use bounding box as-is.
	HitboxFootprint: number?,

	-- Depletion presentation, evaluated in order. Node is destroyed at 0.
	DepletionStages: { DepletionStage },

	-- Optional respawn: seconds after depletion before the node regrows in
	-- place. nil = finite node (standard RTS behaviour).
	RespawnSeconds: number?,
}

local ResourceNodesConfig: { [string]: NodeTypeConfig } = {
	Wood = {
		AssetFolders = { "DetailProps/Trees" },
		SkipTemplateNames = { ["MeshPart"] = true },
		MaxResources = 150,
		AreaPerNode = 100, -- matches the map-editor overlay tree density
		MinPerPatch = 2,
		MaxPerPatch = 160,
		MinSpacing = 7,
		TargetHeight = 15, -- roughly 1.5x a house; reads as a tree, doesn't dominate
		HeightJitter = 0.25,
		Collides = true,
		HitboxFootprint = 4, -- collide on the trunk, not the canopy
		DepletionStages = {
			{ Threshold = 0.66, Scale = 0.92, Transparency = 0 },
			{ Threshold = 0.33, Scale = 0.8, Transparency = 0.15 },
			{ Threshold = 0.1, Scale = 0.65, Transparency = 0.4 },
		},
		RespawnSeconds = nil,
	},

	Stone = {
		AssetFolders = { "DetailProps/Rocks" },
		-- RockBridge is a quarry floor tile, not a gatherable boulder
		SkipTemplateNames = { ["MeshPart"] = true, ["RockBridge"] = true },
		MaxResources = 250,
		AreaPerNode = 300,
		MinPerPatch = 1,
		MaxPerPatch = 24,
		MinSpacing = 8,
		TargetHeight = 6, -- matches the map-editor scatter rock size
		HeightJitter = 0.3,
		Collides = true,
		HitboxFootprint = nil,
		DepletionStages = {
			{ Threshold = 0.66, Scale = 0.85, Transparency = 0 },
			{ Threshold = 0.33, Scale = 0.65, Transparency = 0.1 },
			{ Threshold = 0.1, Scale = 0.5, Transparency = 0.35 },
		},
		RespawnSeconds = nil,
	},

	Iron_Ore = {
		-- No dedicated folder confirmed yet — resolver tries these, then falls
		-- back to procedural ore boulders (rock mesh tinted rust, if available).
		AssetFolders = { "DetailProps/IronOre", "DetailProps/Ore", "DetailProps/Rocks" },
		SkipTemplateNames = { ["MeshPart"] = true, ["RockBridge"] = true },
		MaxResources = 200,
		AreaPerNode = 300,
		MinPerPatch = 1,
		MaxPerPatch = 30,
		MinSpacing = 7,
		TargetHeight = 4.5,
		HeightJitter = 0.3,
		Collides = true,
		HitboxFootprint = nil,
		DepletionStages = {
			{ Threshold = 0.66, Scale = 0.85, Transparency = 0 },
			{ Threshold = 0.33, Scale = 0.65, Transparency = 0.1 },
			{ Threshold = 0.1, Scale = 0.5, Transparency = 0.35 },
		},
		RespawnSeconds = nil,
	},

	Food = {
		AssetFolders = { "DetailProps/Food", "DetailProps/Crops", "DetailProps/Farm" },
		SkipTemplateNames = { ["MeshPart"] = true },
		MaxResources = 120,
		AreaPerNode = 200,
		MinPerPatch = 1,
		MaxPerPatch = 40,
		MinSpacing = 8,
		TargetHeight = 2.5,
		HeightJitter = 0.15,
		Collides = false, -- units walk through crops
		HitboxFootprint = nil,
		DepletionStages = {
			{ Threshold = 0.66, Scale = 0.9, Transparency = 0 },
			{ Threshold = 0.33, Scale = 0.75, Transparency = 0.2 },
			{ Threshold = 0.1, Scale = 0.6, Transparency = 0.45 },
		},
		-- Food regrows: fields replenish 2 minutes after depletion
		RespawnSeconds = 120,
	},
}

local module = {}

module.Types = ResourceNodesConfig

-- Global multiplier applied on top of every TargetHeight. Drop to 0.8 to
-- miniaturise the whole prop layer at once if buildable space feels tight.
module.GlobalSizeMultiplier = 1.0

-- Fallback used for unknown node types so a bad string never hard-crashes spawning
module.Default = ResourceNodesConfig.Wood

function module.get(nodeType: string): NodeTypeConfig
	return ResourceNodesConfig[nodeType] or module.Default
end

return module
