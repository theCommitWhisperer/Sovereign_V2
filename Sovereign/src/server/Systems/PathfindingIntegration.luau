--!strict
-- PathfindingIntegration Smart: Uses full building bounding box BUT creates walkable zones at worker points
-- This allows accurate building collision while enabling pathfinding to worker points

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)
local Pathfinding = require(ReplicatedStorage.Shared.Pathfinding)

local PathfindingIntegration = {}
PathfindingIntegration.__index = PathfindingIntegration

local PathfindingDebug = DebugManager.createChannel("PathfindingIntegration", true)

-- Configuration
local CONFIG = {
	CELL_SIZE = 4,
	BUILDING_PADDING = 2,
	WORKER_POINT_RADIUS = 8, -- Walkable radius around worker points (in studs) - increased for reliable pathfinding
	MAX_PATH_CALCULATIONS_PER_FRAME = 10,
	PATH_CACHE_SIZE = 100,
	PATH_CACHE_TIMEOUT = 5,
}

-- Worker point names that should be walkable
local WORKER_POINT_NAMES = {
	"BuildingEntrance",
	"ProductionStation",
	"ResourceDropoff",
	"ResourcePickup",
	"WorkerRestPosition",
	"StorageAreaWood",
	"StorageAreaStone",
	"StorageAreaFood",
	"StorageAreaIron",
	"StorageAreaGold",
	"StorageAreaWeapons",
	"StorageAreaGeneral",
}

-- Active state
local activePathfinding = nil
local gridVersion = 0
local framePathCalculations = 0
local lastFrameReset = 0
local activeMovers = {}

-- ============================================
-- INITIALIZATION
-- ============================================

function PathfindingIntegration.initialize(mapSize: number)
	PathfindingDebug:info("Initializing production pathfinding system")

	local gridWidth = math.ceil(mapSize / CONFIG.CELL_SIZE)
	local gridHeight = math.ceil(mapSize / CONFIG.CELL_SIZE)

	PathfindingDebug:info(`Map size: {mapSize}x{mapSize}`)
	PathfindingDebug:info(`Creating grid: {gridWidth}x{gridHeight}`)
	PathfindingDebug:info(`Cell size: {CONFIG.CELL_SIZE} studs`)
	PathfindingDebug:info(`Total cells: {gridWidth * gridHeight}`)

	-- Calculate grid origin (centered at 0,0)
	local originX = -(mapSize / 2)
	local originZ = -(mapSize / 2)

	local grid = Pathfinding.createGrid(gridWidth, gridHeight, CONFIG.CELL_SIZE, originX, originZ)

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
-- SMART OBSTACLE MANAGEMENT
-- ============================================

-- Check if a part is a worker point
local function isWorkerPoint(part: Instance): boolean
	if not part:IsA("BasePart") then
		return false
	end

	for _, pointName in ipairs(WORKER_POINT_NAMES) do
		if part.Name == pointName then
			return true
		end
	end

	return false
end

-- Get all worker points in a building
local function getWorkerPoints(building: Model): { BasePart }
	local points = {}

	for _, descendant in ipairs(building:GetDescendants()) do
		if isWorkerPoint(descendant) then
			table.insert(points, descendant :: BasePart)
		end
	end

	return points
end

-- Create a custom bounding box that excludes worker points
local function getCustomBoundingBox(building: Model): (CFrame?, Vector3?)
	if not building or not building:IsA("Model") then
		return nil, nil
	end

	-- Get all parts EXCEPT worker points
	local buildingParts = {}
	for _, descendant in ipairs(building:GetDescendants()) do
		if descendant:IsA("BasePart") and not isWorkerPoint(descendant) then
			table.insert(buildingParts, descendant)
		end
	end

	if #buildingParts == 0 then
		-- No non-worker parts found, use full bounding box
		return building:GetBoundingBox()
	end

	-- Calculate bounding box from building parts only
	local minX, minY, minZ = math.huge, math.huge, math.huge
	local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge

	for _, part in ipairs(buildingParts) do
		local cf = part.CFrame
		local size = part.Size

		local corners = {
			cf * CFrame.new(-size.X/2, -size.Y/2, -size.Z/2),
			cf * CFrame.new( size.X/2, -size.Y/2, -size.Z/2),
			cf * CFrame.new(-size.X/2,  size.Y/2, -size.Z/2),
			cf * CFrame.new( size.X/2,  size.Y/2, -size.Z/2),
			cf * CFrame.new(-size.X/2, -size.Y/2,  size.Z/2),
			cf * CFrame.new( size.X/2, -size.Y/2,  size.Z/2),
			cf * CFrame.new(-size.X/2,  size.Y/2,  size.Z/2),
			cf * CFrame.new( size.X/2,  size.Y/2,  size.Z/2),
		}

		for _, corner in ipairs(corners) do
			local pos = corner.Position
			minX = math.min(minX, pos.X)
			minY = math.min(minY, pos.Y)
			minZ = math.min(minZ, pos.Z)
			maxX = math.max(maxX, pos.X)
			maxY = math.max(maxY, pos.Y)
			maxZ = math.max(maxZ, pos.Z)
		end
	end

	local center = Vector3.new((minX + maxX) / 2, (minY + maxY) / 2, (minZ + maxZ) / 2)
	local size = Vector3.new(maxX - minX, maxY - minY, maxZ - minZ)

	return CFrame.new(center), size
end

-- Mark walkable zones around worker points
local function markWorkerPointsWalkable(building: Model)
	if not activePathfinding then
		return
	end

	local workerPoints = getWorkerPoints(building)

	for _, point in ipairs(workerPoints) do
		-- Mark all worker points as walkable (ProductionStation, ResourceDropoff, BuildingEntrance, etc.)
		-- This allows workers and haulers to pathfind to any worker point that's outside the building

		local pos = point.Position
		local radius = CONFIG.WORKER_POINT_RADIUS

		-- Convert to grid coordinates
		local centerGridX, centerGridY = Pathfinding.worldToGrid(activePathfinding.grid, pos.X, pos.Z)

		if not centerGridX or not centerGridY then
			continue
		end

		-- Calculate grid cells to mark as walkable (circle around point)
		local radiusInCells = math.ceil(radius / CONFIG.CELL_SIZE)

		for dx = -radiusInCells, radiusInCells do
			for dy = -radiusInCells, radiusInCells do
				-- Check if within radius
				if math.sqrt(dx * dx + dy * dy) <= radiusInCells then
					local gridX = centerGridX + dx
					local gridY = centerGridY + dy

					-- Clamp to bounds
					gridX = math.max(1, math.min(gridX, activePathfinding.grid.width))
					gridY = math.max(1, math.min(gridY, activePathfinding.grid.height))

					-- Mark as walkable (create hole in obstacle)
					Pathfinding.setNodeWalkable(activePathfinding.grid, gridX, gridY, true)
				end
			end
		end

		PathfindingDebug:info(`Marked walkable zone at {point.Name}`, {
			position = pos,
			radius = radius,
		})
	end
end

-- Add obstacle with smart worker point handling
function PathfindingIntegration.addObstacle(building: Model)
	if not activePathfinding then
		return
	end

	if not building or not building:IsA("Model") then
		return
	end

	-- Get custom bounding box (excludes worker points)
	local boundingCFrame, boundingSize = getCustomBoundingBox(building)

	if not boundingCFrame or not boundingSize then
		PathfindingDebug:warn(`Failed to get bounding box for {building.Name}`)
		return
	end

	-- Validate bounding box
	if boundingSize.Magnitude < 0.1 or boundingSize.Magnitude > 1000 then
		PathfindingDebug:warn(`Invalid bounding box size for {building.Name}`)
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

	-- Mark building area as unwalkable
	Pathfinding.setAreaWalkable(activePathfinding.grid, gridMinX, gridMinY, gridMaxX, gridMaxY, false)

	-- THEN mark worker points as walkable (creates walkable holes)
	markWorkerPointsWalkable(building)

	-- Store obstacle reference
	activePathfinding.obstacles[building] = {
		gridMinX = gridMinX,
		gridMinY = gridMinY,
		gridMaxX = gridMaxX,
		gridMaxY = gridMaxY,
		workerPoints = getWorkerPoints(building),
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

	-- Mark entire area as walkable again (including worker points)
	Pathfinding.setAreaWalkable(
		activePathfinding.grid,
		obstacleData.gridMinX,
		obstacleData.gridMinY,
		obstacleData.gridMaxX,
		obstacleData.gridMaxY,
		true
	)

	activePathfinding.obstacles[building] = nil
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
		if building:IsA("Model") then
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

-- Helper function to check if a grid cell is walkable
local function isWalkable(grid, gridX: number, gridY: number): boolean
	if gridX < 1 or gridX > grid.width or gridY < 1 or gridY > grid.height then
		return false
	end
	return grid.nodes[gridY][gridX].walkable
end

function invalidateAllMovers()
	for mover, _ in pairs(activeMovers) do
		if mover and mover:IsA("Model") then
			mover:SetAttribute("PathInvalidated", true)
			mover:SetAttribute("CurrentPath", nil)
		end
	end
end

function PathfindingIntegration.registerMover(mover: Model)
	activeMovers[mover] = {
		registeredAt = tick(),
		lastGridVersion = gridVersion,
	}
end

function PathfindingIntegration.unregisterMover(mover: Model)
	activeMovers[mover] = nil
end

function PathfindingIntegration.getPath(unit: Model, targetPos: Vector3): { Vector3 }?
	if not activePathfinding then
		PathfindingDebug:warn("getPath called but pathfinding not initialized")
		return nil
	end

	if not activePathfinding.grid then
		PathfindingDebug:warn("getPath called but grid is nil")
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
		return nil
	end

	PathfindingIntegration.registerMover(unit)

	local startPos = unit.PrimaryPart.Position
	local cacheKey = `{math.floor(startPos.X)}_{math.floor(startPos.Z)}_{math.floor(targetPos.X)}_{math.floor(targetPos.Z)}`
	local cached = activePathfinding.pathCache[cacheKey]

	if cached and (currentTime - cached.timestamp) < CONFIG.PATH_CACHE_TIMEOUT then
		return cached.path
	end

	local startGridX, startGridY = Pathfinding.worldToGrid(activePathfinding.grid, startPos.X, startPos.Z)
	local targetGridX, targetGridY = Pathfinding.worldToGrid(activePathfinding.grid, targetPos.X, targetPos.Z)

	if not startGridX or not startGridY or not targetGridX or not targetGridY then
		return nil
	end

	-- Check if start position is walkable, adjust if needed
	if not isWalkable(activePathfinding.grid, startGridX, startGridY) then
		PathfindingDebug:warn(`Unit {unit.Name} is on unwalkable cell, finding nearest walkable position`)

		local nearestX, nearestY = findNearestWalkableCell(startGridX, startGridY)
		if nearestX and nearestY then
			startGridX, startGridY = nearestX, nearestY
			PathfindingDebug:info(`Adjusted start position to nearest walkable cell`)
		else
			PathfindingDebug:warn(`Failed to find walkable start position for {unit.Name}`)
			unit:SetAttribute("PathfindingFailed", currentTime)
			return nil
		end
	end


	-- Check if target is walkable
	if not isWalkable(activePathfinding.grid, targetGridX, targetGridY) then
		PathfindingDebug:info("Adjusted target position from unwalkable cell")

		local nearestX, nearestY = findNearestWalkableCell(targetGridX, targetGridY)
		if nearestX and nearestY then
			targetGridX, targetGridY = nearestX, nearestY
		else
			PathfindingDebug:warn(`Failed to find path for {unit.Name}`)
			unit:SetAttribute("PathfindingFailed", currentTime)
			return nil
		end
	end

	framePathCalculations = framePathCalculations + 1
	local pathPoints = Pathfinding.findPath(activePathfinding.grid, startGridX, startGridY, targetGridX, targetGridY)

	if not pathPoints or #pathPoints == 0 then
		PathfindingDebug:warn(`Failed to find path for {unit.Name}`)
		unit:SetAttribute("PathfindingFailed", currentTime)
		return nil
	end

	-- Convert PathPoints (world x,z) to Vector3 positions
	local worldPath = {}
	for _, point in ipairs(pathPoints) do
		-- PathfindingCore.findPath already returns world coordinates
		table.insert(worldPath, Vector3.new(point.x, startPos.Y, point.z))
	end

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

function findNearestWalkableCell(gridX: number, gridY: number): (number?, number?)
	if not activePathfinding then
		return nil, nil
	end

	local maxRadius = 10

	for radius = 1, maxRadius do
		for dx = -radius, radius do
			for dy = -radius, radius do
				if math.abs(dx) == radius or math.abs(dy) == radius then
					local checkX = gridX + dx
					local checkY = gridY + dy

					if isWalkable(activePathfinding.grid, checkX, checkY) then
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
