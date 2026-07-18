--!strict
-- PathfindingIntegration V2: Smart obstacle detection using PrimaryPart only
-- This fixes the bounding box issue where worker points were included in obstacles

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)
local Pathfinding = require(script.Parent.Parent.Parent.Shared.Pathfinding)

local PathfindingIntegration = {}
PathfindingIntegration.__index = PathfindingIntegration

-- Debug channel
local PathfindingDebug = DebugManager.createChannel("PathfindingIntegration", true)

-- Configuration
local CONFIG = {
	CELL_SIZE = 4, -- Studs per cell
	BUILDING_PADDING = 2, -- Extra padding around buildings (studs)
	MAX_PATH_CALCULATIONS_PER_FRAME = 10,
	PATH_CACHE_SIZE = 100,
	PATH_CACHE_TIMEOUT = 5,
}

-- Active pathfinding state
local activePathfinding = nil
local gridVersion = 0

-- Performance tracking
local framePathCalculations = 0
local lastFrameReset = 0

-- Mover tracking
local activeMovers = {}

-- ============================================
-- INITIALIZATION
-- ============================================

function PathfindingIntegration.initialize(mapSize: number)
	PathfindingDebug:info("Initializing production pathfinding system")

	-- Calculate grid dimensions
	local gridWidth = math.ceil(mapSize / CONFIG.CELL_SIZE)
	local gridHeight = math.ceil(mapSize / CONFIG.CELL_SIZE)

	PathfindingDebug:info(`Map size: {mapSize}x{mapSize}`)
	PathfindingDebug:info(`Creating grid: {gridWidth}x{gridHeight}`)
	PathfindingDebug:info(`Cell size: {CONFIG.CELL_SIZE} studs`)
	PathfindingDebug:info(`Total cells: {gridWidth * gridHeight}`)

	-- Create pathfinding grid
	local grid = Pathfinding.createGrid(gridWidth, gridHeight, CONFIG.CELL_SIZE)

	if not grid then
		error("Failed to create pathfinding grid")
	end

	activePathfinding = {
		grid = grid,
		mapSize = mapSize,
		pathCache = {},
		obstacles = {},
	}

	gridVersion = 1

	PathfindingDebug:info("Pathfinding grid created successfully")
	return true
end

-- ============================================
-- OBSTACLE MANAGEMENT - SMART VERSION
-- ============================================

-- Add obstacle using ONLY PrimaryPart, not bounding box
function PathfindingIntegration.addObstacle(building: Model)
	if not activePathfinding then
		return
	end

	if not building or not building:IsA("Model") then
		return
	end

	-- Use ONLY the PrimaryPart, not the entire bounding box
	local primaryPart = building.PrimaryPart
	if not primaryPart then
		PathfindingDebug:warn(`Building {building.Name} has no PrimaryPart`)
		return
	end

	local pos = primaryPart.Position
	local size = primaryPart.Size

	-- Add padding
	local padding = CONFIG.BUILDING_PADDING
	local minX = pos.X - (size.X / 2 + padding)
	local maxX = pos.X + (size.X / 2 + padding)
	local minZ = pos.Z - (size.Z / 2 + padding)
	local maxZ = pos.Z + (size.Z / 2 + padding)

	-- Convert to grid coordinates
	local gridMinX, gridMinY = Pathfinding.worldToGrid(activePathfinding.grid, minX, minZ)
	local gridMaxX, gridMaxY = Pathfinding.worldToGrid(activePathfinding.grid, maxX, maxZ)

	-- Clamp to grid bounds
	gridMinX = math.max(1, math.min(gridMinX, activePathfinding.grid.width))
	gridMinY = math.max(1, math.min(gridMinY, activePathfinding.grid.height))
	gridMaxX = math.max(1, math.min(gridMaxX, activePathfinding.grid.width))
	gridMaxY = math.max(1, math.min(gridMaxY, activePathfinding.grid.height))

	-- Mark as unwalkable
	Pathfinding.setAreaWalkable(activePathfinding.grid, gridMinX, gridMinY, gridMaxX, gridMaxY, false)

	-- Store obstacle reference
	activePathfinding.obstacles[building] = {
		gridMinX = gridMinX,
		gridMinY = gridMinY,
		gridMaxX = gridMaxX,
		gridMaxY = gridMaxY,
	}

	-- Clear cache and invalidate paths
	activePathfinding.pathCache = {}
	gridVersion = gridVersion + 1
	invalidateAllMovers()

	PathfindingDebug:info(`Added obstacle: {building.Name} (grid version: {gridVersion})`)
end

-- Remove obstacle
function PathfindingIntegration.removeObstacle(building: Model)
	if not activePathfinding then
		return
	end

	local obstacleData = activePathfinding.obstacles[building]
	if not obstacleData then
		return
	end

	-- Mark area as walkable again
	Pathfinding.setAreaWalkable(
		activePathfinding.grid,
		obstacleData.gridMinX,
		obstacleData.gridMinY,
		obstacleData.gridMaxX,
		obstacleData.gridMaxY,
		true
	)

	-- Remove from tracking
	activePathfinding.obstacles[building] = nil

	-- Clear cache and invalidate paths
	activePathfinding.pathCache = {}
	gridVersion = gridVersion + 1
	invalidateAllMovers()

	PathfindingDebug:info(`Removed obstacle: {building.Name} (grid version: {gridVersion})`)
end

-- Update all building obstacles
function PathfindingIntegration.updateBuildingObstacles(buildingsFolder: Folder)
	if not activePathfinding then
		return 0
	end

	local obstacleCount = 0

	for _, building in ipairs(buildingsFolder:GetChildren()) do
		if building:IsA("Model") and building.PrimaryPart then
			local success = pcall(function()
				PathfindingIntegration.addObstacle(building)
			end)

			if success then
				obstacleCount = obstacleCount + 1
			end
		end
	end

	PathfindingDebug:info(`Updated grid with {obstacleCount} building obstacles`)
	return obstacleCount
end

-- ============================================
-- PATHFINDING CORE
-- ============================================

-- Invalidate all active movers when grid changes
function invalidateAllMovers()
	for mover, _ in pairs(activeMovers) do
		if mover and mover:IsA("Model") then
			mover:SetAttribute("PathInvalidated", true)
			mover:SetAttribute("CurrentPath", nil)
		end
	end
end

-- Register a mover
function PathfindingIntegration.registerMover(mover: Model)
	activeMovers[mover] = {
		registeredAt = tick(),
		lastGridVersion = gridVersion,
	}
end

-- Unregister a mover
function PathfindingIntegration.unregisterMover(mover: Model)
	activeMovers[mover] = nil
end

-- Get path with caching and performance throttling
function PathfindingIntegration.getPath(unit: Model, targetPos: Vector3): { Vector3 }?
	if not activePathfinding then
		return nil
	end

	if not unit.PrimaryPart then
		return nil
	end

	-- Performance throttling
	local currentTime = tick()
	if currentTime - lastFrameReset > 1 / 60 then
		framePathCalculations = 0
		lastFrameReset = currentTime
	end

	if framePathCalculations >= CONFIG.MAX_PATH_CALCULATIONS_PER_FRAME then
		return nil -- Throttled, try again next frame
	end

	-- Register mover
	PathfindingIntegration.registerMover(unit)

	local startPos = unit.PrimaryPart.Position

	-- Check cache
	local cacheKey = `{math.floor(startPos.X)}_{math.floor(startPos.Z)}_{math.floor(targetPos.X)}_{math.floor(targetPos.Z)}`
	local cached = activePathfinding.pathCache[cacheKey]

	if cached and (currentTime - cached.timestamp) < CONFIG.PATH_CACHE_TIMEOUT then
		return cached.path
	end

	-- Convert to grid coordinates
	local startGridX, startGridY = Pathfinding.worldToGrid(activePathfinding.grid, startPos.X, startPos.Z)
	local targetGridX, targetGridY = Pathfinding.worldToGrid(activePathfinding.grid, targetPos.X, targetPos.Z)

	-- Validate coordinates
	if not startGridX or not startGridY or not targetGridX or not targetGridY then
		return nil
	end

	-- Check if target is walkable, if not, find nearest walkable cell
	if not Pathfinding.isWalkable(activePathfinding.grid, targetGridX, targetGridY) then
		PathfindingDebug:info("Adjusted target position from unwalkable cell")

		-- Find nearest walkable cell
		local nearestX, nearestY = findNearestWalkableCell(targetGridX, targetGridY)
		if nearestX and nearestY then
			targetGridX, targetGridY = nearestX, nearestY
		else
			PathfindingDebug:warn(`Failed to find path for {unit.Name}`)
			unit:SetAttribute("PathfindingFailed", currentTime)
			return nil
		end
	end

	-- Calculate path
	framePathCalculations = framePathCalculations + 1
	local gridPath = Pathfinding.findPath(activePathfinding.grid, startGridX, startGridY, targetGridX, targetGridY)

	if not gridPath or #gridPath == 0 then
		PathfindingDebug:warn(`Failed to find path for {unit.Name}`)
		unit:SetAttribute("PathfindingFailed", currentTime)
		return nil
	end

	-- Convert grid path to world positions
	local worldPath = {}
	for _, gridPos in ipairs(gridPath) do
		local worldX, worldZ = Pathfinding.gridToWorld(activePathfinding.grid, gridPos.x, gridPos.y)
		table.insert(worldPath, Vector3.new(worldX, startPos.Y, worldZ))
	end

	-- Cache the path
	activePathfinding.pathCache[cacheKey] = {
		path = worldPath,
		timestamp = currentTime,
	}

	-- Limit cache size
	local cacheSize = 0
	for _ in pairs(activePathfinding.pathCache) do
		cacheSize = cacheSize + 1
	end

	if cacheSize > CONFIG.PATH_CACHE_SIZE then
		local oldest = nil
		local oldestTime = math.huge

		for key, data in pairs(activePathfinding.pathCache) do
			if data.timestamp < oldestTime then
				oldestTime = data.timestamp
				oldest = key
			end
		end

		if oldest then
			activePathfinding.pathCache[oldest] = nil
		end
	end

	return worldPath
end

-- Find nearest walkable cell (spiral search)
function findNearestWalkableCell(gridX: number, gridY: number): (number?, number?)
	if not activePathfinding then
		return nil, nil
	end

	local maxRadius = 10 -- Search up to 10 cells away

	for radius = 1, maxRadius do
		for dx = -radius, radius do
			for dy = -radius, radius do
				if math.abs(dx) == radius or math.abs(dy) == radius then
					local checkX = gridX + dx
					local checkY = gridY + dy

					if Pathfinding.isWalkable(activePathfinding.grid, checkX, checkY) then
						return checkX, checkY
					end
				end
			end
		end
	end

	return nil, nil
end

-- ============================================
-- UTILITIES
-- ============================================

function PathfindingIntegration.getGrid()
	return activePathfinding and activePathfinding.grid or nil
end

function PathfindingIntegration.getGridVersion()
	return gridVersion
end

function PathfindingIntegration.isInitialized()
	return activePathfinding ~= nil
end

PathfindingDebug:info("Production PathfindingIntegration module loaded")

return PathfindingIntegration
