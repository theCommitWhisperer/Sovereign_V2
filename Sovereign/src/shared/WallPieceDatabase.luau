--!strict
--[[
	WallPieceDatabase - Configuration for all wall piece types

	This module defines the properties of each wall model type:
	- Asset names in ReplicatedStorage/Assets/Buildings/
	- Dimensions and connection points
	- Bitmasking patterns for auto-selection
]]

export type WallPieceConfig = {
	assetName: string, -- Name in ReplicatedStorage.Assets.Buildings
	width: number, -- Width in studs (X or Z depending on rotation)
	height: number, -- Height in studs (Y)
	depth: number, -- Depth in studs
	connectionPoints: number, -- How many connection points (2 for straight/ladder, 4 for towers, etc)
	category: string, -- "straight" | "corner" | "tower" | "gate" | "ladder"
	isLargePiece: boolean?, -- True if piece occupies multiple grid cells (like 2x2 corners)
}

local WallPieceDatabase = {}

-- Grid size: 16 studs (matches your Straight_Stone_Wall and Ladder_Stone_Wall dimensions)
WallPieceDatabase.GRID_SIZE = 16

-- Snap radius for connection detection
WallPieceDatabase.SNAP_RADIUS = 8

-- Tower spacing configuration
-- When dragging towers, insert this many straight wall segments between each tower
WallPieceDatabase.TOWER_SPACING = 3 -- 3 straight walls between towers (configurable)

-- All available wall pieces
WallPieceDatabase.PIECES = {
	["Straight_Stone_Wall"] = {
		assetName = "Straight_Stone_Wall",
		width = 16,
		height = 36,
		depth = 14,
		connectionPoints = 2,
		category = "straight",
	},

	["Short_Straight_Stone_Wall"] = {
		assetName = "Short_Straight_Stone_Wall",
		width = 10,
		height = 35,
		depth = 14,
		connectionPoints = 2,
		category = "straight",
	},

	["Ladder_Stone_Wall"] = {
		assetName = "Ladder_Stone_Wall",
		width = 16,
		height = 36,
		depth = 14,
		connectionPoints = 2,
		category = "ladder",
	},

	["Corner_Stone_Wall"] = {
		assetName = "Corner_Stone_Wall",
		width = 32, -- Corner piece is 2x grid size (31 studs actual)
		height = 37, -- Actual measured height
		depth = 32, -- Corner piece is 2x grid size (31 studs actual)
		connectionPoints = 2,
		category = "corner",
		isLargePiece = true, -- Occupies 2x2 grid cells
	},

	["Small_Tower_Stone_Wall"] = {
		assetName = "Small_Tower_Stone_Wall",
		width = 24,
		height = 48,
		depth = 24,
		connectionPoints = 4,
		category = "tower",
	},

	["Large_Tower_Stone_Wall"] = {
		assetName = "Large_Tower_Stone_Wall",
		width = 23,
		height = 74,
		depth = 23,
		connectionPoints = 4,
		category = "tower",
	},

	["Large_Keep_Stone"] = {
		assetName = "Large_Keep_Stone",
		width = 94,
		height = 76,
		depth = 110,
		connectionPoints = 4,
		category = "tower",
	},

	["Gatehouse_Stone_Wall"] = {
		assetName = "Gatehouse_Stone_Wall",
		width = 40,
		height = 49,
		depth = 59,
		connectionPoints = 2,
		category = "gate",
	},
}

-- Bitmasking lookup table (4-direction)
-- Directions: North=1, East=2, South=4, West=8
-- This determines which wall piece to use based on neighbors
WallPieceDatabase.BITMASK_LOOKUP = {
	-- No neighbors = isolated straight wall
	[0] = { pieceType = "Straight_Stone_Wall", rotation = 0 },

	-- One neighbor
	[1] = { pieceType = "Straight_Stone_Wall", rotation = 90 }, -- North
	[2] = { pieceType = "Straight_Stone_Wall", rotation = 0 }, -- East
	[4] = { pieceType = "Straight_Stone_Wall", rotation = 90 }, -- South
	[8] = { pieceType = "Straight_Stone_Wall", rotation = 0 }, -- West

	-- Two neighbors - straight line or corner
	[5] = { pieceType = "Straight_Stone_Wall", rotation = 90 }, -- North + South (vertical line)
	[10] = { pieceType = "Straight_Stone_Wall", rotation = 0 }, -- East + West (horizontal line)
	[3] = { pieceType = "Corner_Stone_Wall", rotation = 90 }, -- North + East (corner)
	[6] = { pieceType = "Corner_Stone_Wall", rotation = 180 }, -- East + South (corner)
	[12] = { pieceType = "Corner_Stone_Wall", rotation = 270 }, -- South + West (corner)
	[9] = { pieceType = "Corner_Stone_Wall", rotation = 0 }, -- West + North (corner)

	-- Three neighbors - T-junction (use tower)
	[7] = { pieceType = "Small_Tower_Stone_Wall", rotation = 90 }, -- N + E + S
	[14] = { pieceType = "Small_Tower_Stone_Wall", rotation = 180 }, -- E + S + W
	[13] = { pieceType = "Small_Tower_Stone_Wall", rotation = 270 }, -- S + W + N
	[11] = { pieceType = "Small_Tower_Stone_Wall", rotation = 0 }, -- W + N + E

	-- Four neighbors - cross junction (use large tower)
	[15] = { pieceType = "Large_Tower_Stone_Wall", rotation = 0 },
}

-- Cardinal directions for neighbor checking
-- Each direction has grid offset (x, z) and bit value for bitmask
WallPieceDatabase.DIRECTIONS = {
	{ x = 0, z = -1, bit = 1, name = "North" }, -- North (-Z)
	{ x = 1, z = 0, bit = 2, name = "East" }, -- East (+X)
	{ x = 0, z = 1, bit = 4, name = "South" }, -- South (+Z)
	{ x = -1, z = 0, bit = 8, name = "West" }, -- West (-X)
}

-- Convert world position to grid coordinates
function WallPieceDatabase.worldToGrid(position: Vector3): (number, number)
	local gridX = math.floor(position.X / WallPieceDatabase.GRID_SIZE + 0.5)
	local gridZ = math.floor(position.Z / WallPieceDatabase.GRID_SIZE + 0.5)
	return gridX, gridZ
end

-- Convert grid coordinates to world position
-- Optional pieceType parameter for special positioning (e.g., large corner pieces)
function WallPieceDatabase.gridToWorld(gridX: number, gridZ: number, yLevel: number?, pieceType: string?): Vector3
	local y = yLevel or 0
	local x = gridX * WallPieceDatabase.GRID_SIZE
	local z = gridZ * WallPieceDatabase.GRID_SIZE

	-- Special handling for large pieces (2x2 grid cells)
	-- Corner pieces need to be offset by half a grid cell to center on intersection
	if pieceType then
		local config = WallPieceDatabase.PIECES[pieceType]
		if config and config.isLargePiece then
			-- Offset by half grid size so the 32-stud piece centers on grid intersection
			x = x + (WallPieceDatabase.GRID_SIZE / 2)
			z = z + (WallPieceDatabase.GRID_SIZE / 2)
		end
	end

	return Vector3.new(x, y, z)
end

-- Get wall piece configuration by name
function WallPieceDatabase.getPieceConfig(pieceName: string): WallPieceConfig?
	return WallPieceDatabase.PIECES[pieceName]
end

-- Get wall piece to use based on neighbor bitmask
function WallPieceDatabase.getPieceFromBitmask(bitmask: number, manualOverride: string?): (string, number)
	-- If manual override specified, use that
	if manualOverride and WallPieceDatabase.PIECES[manualOverride] then
		return manualOverride, 0
	end

	-- Look up in bitmask table
	local config = WallPieceDatabase.BITMASK_LOOKUP[bitmask]
	if config then
		return config.pieceType, config.rotation
	end

	-- Default fallback
	return "Straight_Stone_Wall", 0
end

-- Check if a piece type is a tower or keep
function WallPieceDatabase.isTowerPiece(pieceType: string): boolean
	local config = WallPieceDatabase.PIECES[pieceType]
	if not config then
		return false
	end
	return config.category == "tower"
end

return WallPieceDatabase
