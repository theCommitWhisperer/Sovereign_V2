--!strict
-- PathfindingIntegration: Production-ready A* grid-based pathfinding for Sovereign
-- Manages the pathfinding grid, obstacles, and provides path-finding API for units

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local DebugManager = require(ReplicatedStorage.Shared.DebugManager)
local PathfindingDebug = DebugManager.createChannel("PathfindingIntegration", true)

local Pathfinding = require(ReplicatedStorage.Shared.Pathfinding)

local PathfindingIntegration = {}
PathfindingIntegration.__index = PathfindingIntegration

-- PRODUCTION CONFIGURATION
local CONFIG = {
	-- Grid settings
	CELL_SIZE = 4, -- Studs per cell (3-6 recommended for RTS)
	BUILDING_PADDING = 2, -- Extra padding around buildings (studs)

	-- Performance settings
	MAX_PATH_CALCULATIONS_PER_FRAME = 10, -- Throttle pathfinding to prevent lag spikes
	PATH_CACHE_DURATION = 5, -- Seconds to cache identical paths
	MAX_CACHED_PATHS = 100, -- Maximum number of cached paths

	-- Movement settings
	DEFAULT_SPEED = 16, -- Default unit speed (studs/second)
	ROTATION_SPEED = 180, -- Default rotation speed (degrees/second)
	WAYPOINT_THRESHOLD = 2.5, -- Distance to next waypoint before moving to it
	ARRIVAL_THRESHOLD = 5, -- Distance to destination to consider "arrived"

	-- Failsafe settings
	MAX_PATH_LENGTH = 1000, -- Maximum waypoints in a path (prevent infinite loops)
	FALLBACK_TO_DIRECT = true, -- If pathfinding fails, move directly to target

	-- Debug settings
	ENABLE_PERFORMANCE_MONITORING = true,
	LOG_FAILED_PATHS = true,
}

local activePathfinding = nil
local pathCalculationsThisFrame = 0
local lastFrameReset = tick()
local gridVersion = 0 -- Incremented when obstacles are added/removed

-- Performance monitoring
local function resetFrameCounter()
	local now = tick()
	if now - lastFrameReset >= 1/60 then
		pathCalculationsThisFrame = 0
		lastFrameReset = now
	end
end

-- Get current grid version (increments when obstacles change)
function PathfindingIntegration.getGridVersion()
	return gridVersion
end

-- Invalidate all active unit movers (forces recalculation on next frame)
local function invalidateAllMovers()
	if not activePathfinding then
		return
	end

	local count = 0
	for unit, mover in pairs(activePathfinding.unitMovers) do
		-- Mark the mover as needing recalculation by clearing it
		-- The MovementSystem will recreate it on next update
		pcall(function()
			mover:stop()
		end)
		activePathfinding.unitMovers[unit] = nil
		count = count + 1
	end

	if count > 0 then
		PathfindingDebug:info("Invalidated " .. count .. " unit paths due to grid changes")
	end
end

-- Generate cache key for path
local function getCacheKey(startPos, targetPos)
	local cellSize = activePathfinding and activePathfinding.cellSize or 4
	local sx = math.floor(startPos.X / cellSize) * cellSize
	local sz = math.floor(startPos.Z / cellSize) * cellSize
	local tx = math.floor(targetPos.X / cellSize) * cellSize
	local tz = math.floor(targetPos.Z / cellSize) * cellSize
	return string.format("%.0f,%.0f_%.0f,%.0f", sx, sz, tx, tz)
end

-- Clean expired cache entries
local function cleanPathCache()
	if not activePathfinding then
		return
	end

	local now = tick()
	local removed = 0

	for key, entry in pairs(activePathfinding.pathCache) do
		if now - entry.timestamp > CONFIG.PATH_CACHE_DURATION then
			activePathfinding.pathCache[key] = nil
			removed = removed + 1
		end
	end

	-- If still too many cached paths, clear all
	local count = 0
	for _ in pairs(activePathfinding.pathCache) do
		count = count + 1
	end

	if count > CONFIG.MAX_CACHED_PATHS then
		activePathfinding.pathCache = {}
		PathfindingDebug:info("Path cache cleared due to size limit")
	end
end

-- Initialize pathfinding for the current map
function PathfindingIntegration.initialize(mapSize)
	mapSize = mapSize or 1024

	PathfindingDebug:info("Initializing production pathfinding system")
	PathfindingDebug:info("Map size: " .. mapSize .. "x" .. mapSize)

	-- Validate map size
	if mapSize < 64 or mapSize > 4096 then
		-- warn("Unusual map size: " .. mapSize .. " - may cause performance issues")
	end

	-- Calculate grid parameters
	local cellSize = CONFIG.CELL_SIZE
	local gridWidth = math.ceil(mapSize / cellSize)
	local gridHeight = gridWidth

	local originX = -mapSize / 2
	local originZ = -mapSize / 2

	PathfindingDebug:info("Creating grid: " .. gridWidth .. "x" .. gridHeight)
	PathfindingDebug:info("Cell size: " .. cellSize .. " studs")
	PathfindingDebug:info("Total cells: " .. (gridWidth * gridHeight))

	-- Create the pathfinding grid
	local success, grid = pcall(function()
		return Pathfinding.createGrid(gridWidth, gridHeight, cellSize, originX, originZ)
	end)

	if not success then
		error("Failed to create pathfinding grid: " .. tostring(grid))
	end

	activePathfinding = {
		grid = grid,
		unitMovers = {},
		cellSize = cellSize,
		mapSize = mapSize,
		pathCache = {},
		stats = {
			totalPathsCalculated = 0,
			totalPathsCached = 0,
			totalPathsFailed = 0,
			averagePathTime = 0,
		},
	}

	PathfindingDebug:info("Pathfinding grid created successfully")

	-- Update grid with existing buildings
	local obstacleCount = PathfindingIntegration.updateAllObstacles()
	PathfindingDebug:info("Initialization complete - " .. obstacleCount .. " obstacles added")

	-- Start cache cleanup timer
	task.spawn(function()
		while activePathfinding do
			task.wait(30)
			cleanPathCache()
		end
	end)

	return activePathfinding
end

-- Get the active pathfinding instance
function PathfindingIntegration.get()
	return activePathfinding
end

-- Get current configuration
function PathfindingIntegration.getConfig()
	return CONFIG
end

-- Update grid with all obstacles from workspace
function PathfindingIntegration.updateAllObstacles()
	if not activePathfinding then
		-- warn("Pathfinding not initialized - cannot update obstacles")
		return 0
	end

	local buildingsFolder = Workspace:FindFirstChild("Buildings")
	if not buildingsFolder then
		PathfindingDebug:warn("No Buildings folder found - skipping obstacle update")
		return 0
	end

	local obstacleCount = 0
	local failedCount = 0

	for _, building in ipairs(buildingsFolder:GetChildren()) do
		if building:IsA("Model") then
			local success = pcall(function()
				PathfindingIntegration.addObstacle(building)
			end)

			if success then
				obstacleCount = obstacleCount + 1
			else
				failedCount = failedCount + 1
			end
		end
	end

	if failedCount > 0 then
		PathfindingDebug:warn("Failed to add " .. failedCount .. " obstacles")
	end

	PathfindingDebug:info("Updated grid with " .. obstacleCount .. " building obstacles")
	return obstacleCount
end

-- Add a single obstacle to the grid
function PathfindingIntegration.addObstacle(obstacle)
	if not activePathfinding then
		return
	end

	if not obstacle or not obstacle:IsA("Model") then
		return
	end

	-- Get bounding box with error handling
	local success, boundingCFrame, boundingSize = pcall(function()
		return obstacle:GetBoundingBox()
	end)

	if not success or not boundingCFrame or not boundingSize then
		PathfindingDebug:warn("Failed to get bounding box for " .. obstacle.Name)
		return
	end

	-- Validate bounding box
	if boundingSize.Magnitude < 0.1 or boundingSize.Magnitude > 1000 then
		PathfindingDebug:warn("Invalid bounding box size for " .. obstacle.Name)
		return
	end

	local pos = boundingCFrame.Position
	local size = boundingSize

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

	-- Clear cache and invalidate all paths when obstacles change
	activePathfinding.pathCache = {}
	gridVersion = gridVersion + 1
	invalidateAllMovers()

	PathfindingDebug:info("Added obstacle: " .. obstacle.Name .. " (grid version: " .. gridVersion .. ")")
end

-- Remove an obstacle from the grid
function PathfindingIntegration.removeObstacle(obstacle)
	if not activePathfinding then
		return
	end

	if not obstacle or not obstacle:IsA("Model") then
		return
	end

	local success, boundingCFrame, boundingSize = pcall(function()
		return obstacle:GetBoundingBox()
	end)

	if not success then
		return
	end

	local pos = boundingCFrame.Position
	local size = boundingSize

	local padding = CONFIG.BUILDING_PADDING
	local minX = pos.X - (size.X / 2 + padding)
	local maxX = pos.X + (size.X / 2 + padding)
	local minZ = pos.Z - (size.Z / 2 + padding)
	local maxZ = pos.Z + (size.Z / 2 + padding)

	local gridMinX, gridMinY = Pathfinding.worldToGrid(activePathfinding.grid, minX, minZ)
	local gridMaxX, gridMaxY = Pathfinding.worldToGrid(activePathfinding.grid, maxX, maxZ)

	-- Clamp to grid bounds
	gridMinX = math.max(1, math.min(gridMinX, activePathfinding.grid.width))
	gridMinY = math.max(1, math.min(gridMinY, activePathfinding.grid.height))
	gridMaxX = math.max(1, math.min(gridMaxX, activePathfinding.grid.width))
	gridMaxY = math.max(1, math.min(gridMaxY, activePathfinding.grid.height))

	-- Mark as walkable
	Pathfinding.setAreaWalkable(activePathfinding.grid, gridMinX, gridMinY, gridMaxX, gridMaxY, true)

	-- Clear cache and invalidate all paths when obstacles change
	activePathfinding.pathCache = {}
	gridVersion = gridVersion + 1
	invalidateAllMovers()

	PathfindingDebug:info("Removed obstacle: " .. obstacle.Name .. " (grid version: " .. gridVersion .. ")")
end

-- Check if a grid cell is walkable
local function isGridCellWalkable(grid, gridX, gridY)
	if gridX < 1 or gridX > grid.width or gridY < 1 or gridY > grid.height then
		return false
	end
	return grid.nodes[gridY][gridX].walkable
end

-- Find nearest walkable position to a given position
local function findNearestWalkable(worldPos, maxSearchRadius)
	maxSearchRadius = maxSearchRadius or 20 -- Default 20 studs search radius

	-- Convert to grid coordinates
	local gridX, gridY = Pathfinding.worldToGrid(activePathfinding.grid, worldPos.X, worldPos.Z)

	-- Clamp to grid bounds
	gridX = math.max(1, math.min(gridX, activePathfinding.grid.width))
	gridY = math.max(1, math.min(gridY, activePathfinding.grid.height))

	-- If current position is walkable, return it
	if isGridCellWalkable(activePathfinding.grid, gridX, gridY) then
		return worldPos
	end

	-- Search in expanding rings
	local cellSearchRadius = math.ceil(maxSearchRadius / activePathfinding.cellSize)

	for radius = 1, cellSearchRadius do
		-- Check cells in a ring at this radius
		for dx = -radius, radius do
			for dy = -radius, radius do
				-- Only check cells on the edge of the ring
				if math.abs(dx) == radius or math.abs(dy) == radius then
					local checkX = gridX + dx
					local checkY = gridY + dy

					-- Check if in bounds and walkable
					if isGridCellWalkable(activePathfinding.grid, checkX, checkY) then
						-- Found walkable cell - convert back to world coordinates
						local worldX, worldZ = Pathfinding.gridToWorld(activePathfinding.grid, checkX, checkY)
						return Vector3.new(worldX, worldPos.Y, worldZ)
					end
				end
			end
		end
	end

	-- No walkable position found
	return nil
end

-- Find a path between two world positions (with caching and throttling)
function PathfindingIntegration.findPath(startPos, targetPos, optimize)
	if not activePathfinding then
		-- warn("Pathfinding not initialized")
		return nil
	end

	-- Reset frame counter
	resetFrameCounter()

	-- Throttle pathfinding calculations
	if pathCalculationsThisFrame >= CONFIG.MAX_PATH_CALCULATIONS_PER_FRAME then
		-- PathfindingDebug:warn("Pathfinding throttled - too many calculations this frame")
		return nil
	end

	pathCalculationsThisFrame = pathCalculationsThisFrame + 1

	if optimize == nil then
		optimize = true
	end

	-- Check cache first
	local cacheKey = getCacheKey(startPos, targetPos)
	local cachedEntry = activePathfinding.pathCache[cacheKey]

	if cachedEntry and tick() - cachedEntry.timestamp < CONFIG.PATH_CACHE_DURATION then
		activePathfinding.stats.totalPathsCached = activePathfinding.stats.totalPathsCached + 1
		return cachedEntry.path
	end

	-- Validate positions
	if not startPos or not targetPos then
		-- warn("Invalid positions for pathfinding")
		return nil
	end

	local distance = (targetPos - startPos).Magnitude
	if distance < 1 then
		return {{x = targetPos.X, z = targetPos.Z}}
	end

	if distance > activePathfinding.mapSize * 2 then
		-- warn("Path too long: " .. distance .. " studs")
		return nil
	end

	-- Fix unwalkable start/end positions by finding nearest walkable cells
	local adjustedStartPos = startPos
	local adjustedTargetPos = targetPos

	local startGridX, startGridY = Pathfinding.worldToGrid(activePathfinding.grid, startPos.X, startPos.Z)
	startGridX = math.max(1, math.min(startGridX, activePathfinding.grid.width))
	startGridY = math.max(1, math.min(startGridY, activePathfinding.grid.height))

	if not isGridCellWalkable(activePathfinding.grid, startGridX, startGridY) then
		local nearestWalkable = findNearestWalkable(startPos, 20)
		if nearestWalkable then
			adjustedStartPos = nearestWalkable
			PathfindingDebug:info("Adjusted start position from unwalkable cell")
		else
			PathfindingDebug:warn("Could not find walkable start position within 20 studs")
			if CONFIG.FALLBACK_TO_DIRECT then
				return {{x = targetPos.X, z = targetPos.Z}}
			end
			return nil
		end
	end

	local targetGridX, targetGridY = Pathfinding.worldToGrid(activePathfinding.grid, targetPos.X, targetPos.Z)
	targetGridX = math.max(1, math.min(targetGridX, activePathfinding.grid.width))
	targetGridY = math.max(1, math.min(targetGridY, activePathfinding.grid.height))

	if not isGridCellWalkable(activePathfinding.grid, targetGridX, targetGridY) then
		local nearestWalkable = findNearestWalkable(targetPos, 20)
		if nearestWalkable then
			adjustedTargetPos = nearestWalkable
			PathfindingDebug:info("Adjusted target position from unwalkable cell")
		else
			PathfindingDebug:warn("Could not find walkable target position within 20 studs")
			if CONFIG.FALLBACK_TO_DIRECT then
				return {{x = targetPos.X, z = targetPos.Z}}
			end
			return nil
		end
	end

	-- Calculate path with error protection
	local startTime = tick()
	local path

	local success = pcall(function()
		path = Pathfinding.findOptimizedPath(
			activePathfinding.grid,
			adjustedStartPos.X,
			adjustedStartPos.Z,
			adjustedTargetPos.X,
			adjustedTargetPos.Z,
			{
				stringPull = optimize,
				simplify = optimize,
				smooth = false,
			}
		)
	end)

	local calcTime = (tick() - startTime) * 1000

	-- Update stats
	activePathfinding.stats.totalPathsCalculated = activePathfinding.stats.totalPathsCalculated + 1
	local totalCalcs = activePathfinding.stats.totalPathsCalculated
	local avgTime = activePathfinding.stats.averagePathTime
	activePathfinding.stats.averagePathTime = (avgTime * (totalCalcs - 1) + calcTime) / totalCalcs

	if not success or not path then
		activePathfinding.stats.totalPathsFailed = activePathfinding.stats.totalPathsFailed + 1

		if CONFIG.LOG_FAILED_PATHS then
			PathfindingDebug:warn("Path calculation failed from " .. tostring(startPos) .. " to " .. tostring(targetPos))
		end

		-- Fallback: direct path
		if CONFIG.FALLBACK_TO_DIRECT then
			path = {{x = targetPos.X, z = targetPos.Z}}
		else
			return nil
		end
	end

	-- Validate path length
	if path and #path > CONFIG.MAX_PATH_LENGTH then
		-- warn("Path too long (" .. #path .. " waypoints) - truncating")
		local truncated = {}
		for i = 1, CONFIG.MAX_PATH_LENGTH do
			table.insert(truncated, path[i])
		end
		path = truncated
	end

	-- Cache the path
	if path and #path > 0 then
		activePathfinding.pathCache[cacheKey] = {
			path = path,
			timestamp = tick(),
		}
	end

	if CONFIG.ENABLE_PERFORMANCE_MONITORING and calcTime > 10 then
		PathfindingDebug:warn("Slow pathfinding: " .. math.floor(calcTime) .. "ms for " .. (#path or 0) .. " waypoints")
	end

	return path
end

-- Move a unit to a target position using A* pathfinding
function PathfindingIntegration.moveUnitTo(unit, targetPosition, speed)
	if not activePathfinding then
		-- warn("Pathfinding not initialized")
		return false
	end

	-- Validate unit
	if not unit or not unit:IsA("Model") or not unit.Parent then
		-- warn("Invalid unit for pathfinding")
		return false
	end

	if not unit.PrimaryPart then
		-- warn("Unit " .. unit.Name .. " has no PrimaryPart")
		return false
	end

	-- Validate target position
	if not targetPosition or typeof(targetPosition) ~= "Vector3" then
		-- warn("Invalid target position")
		return false
	end

	local unitPos = unit.PrimaryPart.Position

	-- Find path
	local path = PathfindingIntegration.findPath(unitPos, targetPosition, true)

	if not path or #path == 0 then
		PathfindingDebug:warn("Failed to find path for " .. unit.Name)
		return false
	end

	-- Get or create unit mover
	local mover = activePathfinding.unitMovers[unit]

	if not mover then
		-- Create mover with validated speed
		local unitSpeed = speed or CONFIG.DEFAULT_SPEED
		unitSpeed = math.clamp(unitSpeed, 1, 100)

		local success, result = pcall(function()
			return Pathfinding.createUnitMover(unit, {
				speed = unitSpeed,
				rotationSpeed = CONFIG.ROTATION_SPEED,
				smoothRotation = true,
				waypointThreshold = CONFIG.WAYPOINT_THRESHOLD,
			})
		end)

		if not success or not result then
			-- warn("Failed to create unit mover for " .. unit.Name)
			return false
		end

		mover = result

		-- Set callbacks with error protection
		mover.onPathComplete = function()
			pcall(function()
				unit:SetAttribute("IsMoving", false)
			end)
		end

		activePathfinding.unitMovers[unit] = mover
	end

	-- Follow the path with error protection
	local success = pcall(function()
		mover:followPath(path)
		unit:SetAttribute("IsMoving", true)
	end)

	if not success then
		-- warn("Failed to start unit movement for " .. unit.Name)
		return false
	end

	return true
end

-- Stop a unit's movement
function PathfindingIntegration.stopUnit(unit)
	if not activePathfinding or not unit then
		return
	end

	local mover = activePathfinding.unitMovers[unit]
	if mover then
		pcall(function()
			mover:stop()
			unit:SetAttribute("IsMoving", false)
		end)
	end
end

-- Clean up when a unit is removed
function PathfindingIntegration.removeUnit(unit)
	if not activePathfinding or not unit then
		return
	end

	local mover = activePathfinding.unitMovers[unit]
	if mover then
		pcall(function()
			mover:destroy()
		end)
		activePathfinding.unitMovers[unit] = nil
	end
end

-- Get pathfinding statistics
function PathfindingIntegration.getStats()
	if not activePathfinding then
		return nil
	end

	local cacheSize = 0
	for _ in pairs(activePathfinding.pathCache) do
		cacheSize = cacheSize + 1
	end

	local activeMovers = 0
	for _ in pairs(activePathfinding.unitMovers) do
		activeMovers = activeMovers + 1
	end

	return {
		totalPathsCalculated = activePathfinding.stats.totalPathsCalculated,
		totalPathsCached = activePathfinding.stats.totalPathsCached,
		totalPathsFailed = activePathfinding.stats.totalPathsFailed,
		averagePathTime = math.floor(activePathfinding.stats.averagePathTime * 100) / 100,
		cacheSize = cacheSize,
		activeMovers = activeMovers,
	}
end

-- Visualize the pathfinding grid (debug)
function PathfindingIntegration.debugVisualizeGrid()
	if not activePathfinding then
		-- warn("Pathfinding not initialized")
		return
	end

	local existing = Workspace:FindFirstChild("PathfindingGrid")
	if existing then
		existing:Destroy()
	end

	return Pathfinding.visualizeGrid(activePathfinding.grid, Workspace)
end

-- Visualize a path (debug)
function PathfindingIntegration.debugVisualizePath(path)
	if not path then
		return
	end

	local existing = Workspace:FindFirstChild("PathVisualization")
	if existing then
		existing:Destroy()
	end

	return Pathfinding.visualizePath(path, Workspace)
end

PathfindingDebug:info("Production PathfindingIntegration module loaded")

return PathfindingIntegration
