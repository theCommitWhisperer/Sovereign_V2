--!strict
--[[
    WallGridConfig - Normalized configuration data for wall pieces

    This module contains the LOCAL offsets for each wall piece type.
    All measurements are relative to the model's pivot point.

    The "anchor" is the point that should align to the grid.
    For walls, this is the center of all ConnectionPoints at Y=10 (ground level).
]]

export type WallPieceConfig = {
	-- The offset from the model's pivot to its connection point center
	connectionPointOffset: Vector3,
	-- The offset from the model's pivot to its walkway center
	walkwayOffset: Vector3,
	-- How many connection points this piece has
	connectionCount: number,
	-- The standard grid spacing for this piece (usually 16 studs between connections)
	gridSpacing: number,
}

local WallGridConfig = {}

-- Based on ModelInfo.md analysis
-- These offsets are from the MODEL PIVOT to the CONNECTION POINT CENTER
-- All ConnectionPoints should be at world Y=10 (ground level)
-- We use the walkway center as the reference since models are positioned by their walkway
WallGridConfig.PIECES = {
	["Wall Segment"] = {
		-- Walkway at (−187.50, 40.01, −375.50), CP center at (~-187.25, 10.25, -375.95)
		-- Local offset: (0.43, -29.76, -0.05) from walkway to CP center
		connectionPointOffset = Vector3.new(0, -30, 0), -- Simplified: 30 studs below walkway
		walkwayOffset = Vector3.new(0, 0, 0),
		connectionCount = 2,
		gridSpacing = 16,
	} :: WallPieceConfig,

	["Ladder Wall Segment"] = {
		-- Walkway at (−221.60, 40.01, −346.40), CPs at Y=10.25 average
		connectionPointOffset = Vector3.new(0, -30, 0),
		walkwayOffset = Vector3.new(0, 0, 0),
		connectionCount = 2,
		gridSpacing = 16,
	} :: WallPieceConfig,

	["Wall Corner"] = {
		-- Walkway at (−122.36, 39.50, −386.05), CPs at Y=10
		connectionPointOffset = Vector3.new(0, -29.5, 0),
		walkwayOffset = Vector3.new(0, 0, 0),
		connectionCount = 2,
		gridSpacing = 16,
	} :: WallPieceConfig,

	["Wall Corner Reverse"] = {
		-- Walkway at (−158.35, 39.51, −401.59), CPs at Y=10
		connectionPointOffset = Vector3.new(0, -29.5, 0),
		walkwayOffset = Vector3.new(0, 0, 0),
		connectionCount = 2,
		gridSpacing = 16,
	} :: WallPieceConfig,

	["Tower"] = {
		-- Walkway at (−161.43, 44.51, −420.09), CPs at Y=10
		connectionPointOffset = Vector3.new(0, -34.5, 0),
		walkwayOffset = Vector3.new(0, 0, 0),
		connectionCount = 4,
		gridSpacing = 16,
	} :: WallPieceConfig,

	["Gatehouse"] = {
		-- Walkway at (−161.84, 38.38, −315.59), CPs at Y=10
		connectionPointOffset = Vector3.new(0, -28.4, 0),
		walkwayOffset = Vector3.new(0, 0, 0),
		connectionCount = 2,
		gridSpacing = 16,
	} :: WallPieceConfig,
}

-- Grid configuration
WallGridConfig.GRID_SIZE = 16 -- Each grid cell is 16x16 studs
WallGridConfig.SNAP_RADIUS = 20 -- How close connection points must be to snap
WallGridConfig.CONNECTION_TOLERANCE = 4.0 -- Max distance for a valid connection

-- Cardinal directions for grid-based neighbor checking
WallGridConfig.DIRECTIONS = {
	{ x = 0, z = -1, bit = 1 }, -- North
	{ x = 1, z = 0, bit = 2 }, -- East
	{ x = 0, z = 1, bit = 4 }, -- South
	{ x = -1, z = 0, bit = 8 }, -- West
}

-- Converts world position to grid coordinates
function WallGridConfig.toGrid(position: Vector3): (number, number)
	return math.floor(position.X / WallGridConfig.GRID_SIZE + 0.5),
		math.floor(position.Z / WallGridConfig.GRID_SIZE + 0.5)
end

-- Converts grid coordinates to world position
function WallGridConfig.fromGrid(gx: number, gz: number, y: number?): Vector3
	local yPos = y or 10 -- Default to ground level (where ConnectionPoints are)
	return Vector3.new(gx * WallGridConfig.GRID_SIZE, yPos, gz * WallGridConfig.GRID_SIZE)
end

-- Returns the world position where a wall piece's connection points should be
-- given its grid position
function WallGridConfig.getConnectionPointWorldPos(pieceName: string, gridX: number, gridZ: number): Vector3?
	local config = WallGridConfig.PIECES[pieceName]
	if not config then
		return nil
	end

	-- Grid position is where we want the connection point CENTER to be
	return WallGridConfig.fromGrid(gridX, gridZ)
end

-- Returns the CFrame where a model's PIVOT should be placed
-- so that its connection points align to the given grid position
function WallGridConfig.getModelCFrame(
	pieceName: string,
	gridX: number,
	gridZ: number,
	rotationDegrees: number
): CFrame?
	local config = WallGridConfig.PIECES[pieceName]
	if not config then
		return nil
	end

	-- Where we want the connection point center to be (in world space)
	local targetCPCenter = WallGridConfig.fromGrid(gridX, gridZ)

	-- Create rotation
	local rotRad = math.rad(rotationDegrees)
	local rotation = CFrame.Angles(0, rotRad, 0)

	-- The offset from pivot to CP center, in model's local space
	local localOffset = config.connectionPointOffset

	-- Rotate this offset to world space
	local worldOffset = rotation:VectorToWorldSpace(localOffset)

	-- Pivot should be positioned so that when we add the offset, we reach targetCPCenter
	local pivotPos = targetCPCenter - worldOffset

	return CFrame.new(pivotPos) * rotation
end

return WallGridConfig
