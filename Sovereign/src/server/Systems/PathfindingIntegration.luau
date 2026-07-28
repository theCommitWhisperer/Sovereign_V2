--!strict
-- PathfindingIntegration Smart: Uses full building bounding box BUT creates walkable zones at worker points
-- This allows accurate building collision while enabling pathfinding to worker points

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)
local Pathfinding = require(ReplicatedStorage.Shared.Pathfinding)

local PathfindingIntegration = {}
PathfindingIntegration.__index = PathfindingIntegration

local PathfindingDebug = DebugManager.createChannel("PathfindingIntegration", false)

-- Configuration
local CONFIG = {
	CELL_SIZE = 4,
	BUILDING_PADDING = 2,
	WORKER_POINT_RADIUS = 16, -- Walkable radius around worker points (in studs). Must exceed peasant spawn radius (12) so newly spawned peasants are always on walkable cells.
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
	-- SpawnPoint drives peasant spawn positions (radius 12) so its surrounding
	-- cells must be walkable or newly spawned peasants land on the Keep obstacle.
	"SpawnPoint",
	-- Idle peasants gather and sit at the Keep's Campfire (IdlePeasantManager).
	--
	-- This one matters more than it looks. The obstacle is an AXIS-ALIGNED box
	-- over every non-worker-point part, and the Keep's campfire sits at the far
	-- edge of the model — so counting it as building geometry STRETCHED the box
	-- 13 studs further out (162 -> 149 wide once excluded) across exactly the
	-- open ground the fire stands on. Measured on Stone_Wall_Large_Keep: with the
	-- campfire counted, all 6 gathering slots were unreachable; excluded, the
	-- fire sits 9 studs clear of the obstacle and all 6 are reachable.
	--
	-- Symptom when this is missing: peasants bunch against the side of the Keep
	-- and never arrive, with open ground visibly between them and the fire.
	"Campfire",
}

-- Active state
local activePathfinding = nil
local gridVersion = 0
local framePathCalculations = 0
local lastFrameReset = 0
local activeMovers = {}

-- Rate-limited warnings: recoverable conditions (a unit briefly on an unwalkable
-- cell, a transient path miss) used to spam the output every frame. Collapse
-- repeats of the same key to one line every few seconds.
local lastWarnTimes: { [string]: number } = {}
local function throttledWarn(key: string, message: string, interval: number?)
	local now = tick()
	if (now - (lastWarnTimes[key] or 0)) >= (interval or 5) then
		lastWarnTimes[key] = now
		PathfindingDebug:warn(message)
	end
end

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
local function isNamedWorkerPoint(name: string): boolean
	for _, pointName in ipairs(WORKER_POINT_NAMES) do
		if name == pointName then
			return true
		end
	end
	return false
end

-- Is this part a worker point, or part of one?
--
-- Worker points used to have to be single BaseParts. That silently excluded any
-- marker authored as a MODEL — the Keep's Campfire is ten parts under a Model
-- named "Campfire", so it matched nothing, was treated as building geometry, and
-- its own gathering slots ended up inside the obstacle it created.
--
-- So a part also counts if it sits under a Model carrying a worker-point name.
-- Both callers want that: getCustomBoundingBox keeps those parts OUT of the
-- obstacle box, and markWorkerPointsWalkable carves walkable cells around them.
local function isWorkerPoint(part: Instance): boolean
	if not part:IsA("BasePart") then
		return false
	end

	if isNamedWorkerPoint(part.Name) then
		return true
	end

	-- Walk up through enclosing Models only. Stops at the building's Folder (or
	-- Workspace), so this can't run away up the tree.
	local ancestor = part.Parent
	while ancestor and ancestor:IsA("Model") do
		if isNamedWorkerPoint(ancestor.Name) then
			return true
		end
		ancestor = ancestor.Parent
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

	-- Re-carve EVERY building's worker points. A newly added obstacle can bury a
	-- neighbour's already-carved entrance (e.g. clustered farms), turning it into
	-- a walkable pocket the A* graph can't reach — which is exactly what made
	-- workers path-fail forever and only arrive via the emergency snap. Re-punching
	-- all holes after each change keeps every entrance connected to open ground.
	-- Cheap: only runs on placement / bulk grid rebuilds.
	for otherBuilding in pairs(activePathfinding.obstacles) do
		if otherBuilding ~= building and otherBuilding.Parent then
			markWorkerPointsWalkable(otherBuilding)
		end
	end

	-- Clear cache and invalidate paths
	activePathfinding.pathCache = {}
	gridVersion = gridVersion + 1
	invalidateAllMovers()

	PathfindingDebug:info(`Added obstacle: {building.Name} (grid version: {gridVersion})`)
end

-- Re-punch walkable holes for every registered building's worker points.
-- Call after any batch of grid changes to guarantee entrances stay reachable.
function PathfindingIntegration.recarveAllWorkerPoints()
	if not activePathfinding then
		return
	end
	for building in pairs(activePathfinding.obstacles) do
		if building.Parent then
			markWorkerPointsWalkable(building)
		end
	end
	activePathfinding.pathCache = {}
	gridVersion = gridVersion + 1
	invalidateAllMovers()
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

-- Returns (path, failReason). failReason "throttled" means the per-frame path
-- budget ran out — retry next frame, do NOT count as a pathfinding failure.
function PathfindingIntegration.getPath(unit: Model, targetPos: Vector3): ({ Vector3 }?, string?)
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
		-- Budget exhausted this frame — NOT a pathfinding failure. Callers must
		-- not count this toward their failure/fallback logic (the direct-walk
		-- fallback walks straight through buildings).
		return nil, "throttled"
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

	-- Check if start position is walkable, adjust if needed. This auto-recovers
	-- (we relocate the unit), so it's info-level, not a warning.
	if not isWalkable(activePathfinding.grid, startGridX, startGridY) then
		PathfindingDebug:info(`Unit {unit.Name} on unwalkable cell ({startGridX},{startGridY}); relocating to nearest walkable`)

		local nearestX, nearestY = findNearestWalkableCell(startGridX, startGridY)
		if nearestX and nearestY then
			startGridX, startGridY = nearestX, nearestY
			-- Teleport the unit to the walkable cell so it doesn't get stuck
			-- repeating the same failed lookup every frame.
			local safeWorldX, safeWorldZ = Pathfinding.gridToWorld(activePathfinding.grid, nearestX, nearestY)
			if unit.PrimaryPart then
				local safeY = unit.PrimaryPart.Position.Y
				unit:PivotTo(CFrame.new(safeWorldX, safeY, safeWorldZ))
				PathfindingDebug:info(`Teleported {unit.Name} to walkable cell ({nearestX},{nearestY})`)
			end
		else
			throttledWarn("nostart", `Failed to find walkable start position for a unit (throttled)`)
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
			throttledWarn("nogoal", `Failed to find walkable target for a unit (throttled)`)
			unit:SetAttribute("PathfindingFailed", currentTime)
			return nil
		end
	end

	framePathCalculations = framePathCalculations + 1
	local pathPoints = Pathfinding.findPath(activePathfinding.grid, startGridX, startGridY, targetGridX, targetGridY)

	if not pathPoints or #pathPoints == 0 then
		throttledWarn("nopath", `A* found no path for a unit (throttled — check obstacle layout)`)
		unit:SetAttribute("PathfindingFailed", currentTime)
		return nil
	end

	-- Smooth the raw grid path: string-pull collapses the staircase into
	-- straight line-of-sight segments, then simplify drops collinear points.
	-- Units then cut natural diagonals instead of walking cell-to-cell zigzags.
	local ok, smoothed = pcall(function()
		return Pathfinding.optimizePath(pathPoints, activePathfinding.grid, {
			stringPull = true,
			simplify = true,
		})
	end)
	if ok and smoothed and #smoothed > 0 then
		pathPoints = smoothed
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

	-- Search radius must exceed the largest building obstacle.
	-- The Keep is ~24x28 cells; a unit at its center needs to search ~14 cells
	-- outward to escape. 50 cells = 200 studs covers any building with margin.
	local maxRadius = 50

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

-- Compute a guaranteed-walkable "approach position" for a building: the nearest
-- walkable, graph-connected grid cell to the building centre, in world space.
-- This replaces reliance on authored/generated worker-point PARTS for navigation
-- — a building never needs a correctly-placed BuildingEntrance to be reachable;
-- workers just walk to the open ground the pathfinder already knows is next to it.
-- Returns nil only if the building has no primary part.
function PathfindingIntegration.getApproachPosition(building: Model): Vector3?
	if not building or not building:IsA("Model") then
		return nil
	end
	local center = building:GetPivot().Position

	-- No grid (e.g. Battle Arena — flat open ground): walking straight at the
	-- centre is fine, nothing is unwalkable.
	if not activePathfinding or not activePathfinding.grid then
		return center
	end

	local gx, gy = Pathfinding.worldToGrid(activePathfinding.grid, center.X, center.Z)
	if not gx or not gy then
		return center
	end

	-- If the centre cell itself is walkable (small building / no obstacle) use it;
	-- otherwise find the closest open cell just outside the footprint.
	if isWalkable(activePathfinding.grid, gx, gy) then
		return center
	end

	local nx, ny = findNearestWalkableCell(gx, gy)
	if not nx or not ny then
		return center
	end
	local wx, wz = Pathfinding.gridToWorld(activePathfinding.grid, nx, ny)
	return Vector3.new(wx, center.Y, wz)
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

-- Expose the grid + version so FlowFieldManager can build integration fields
-- and invalidate them when buildings change the grid.
function PathfindingIntegration.getGrid()
	return activePathfinding and activePathfinding.grid or nil
end

function PathfindingIntegration.getGridVersion(): number
	return gridVersion
end

PathfindingDebug:info("Production PathfindingIntegration module loaded")

return PathfindingIntegration
