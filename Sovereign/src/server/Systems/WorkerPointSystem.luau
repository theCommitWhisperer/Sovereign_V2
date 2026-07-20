--!strict
-- WorkerPointSystem: Manages worker navigation points within buildings
-- Similar to SpawnPointSystem, this provides precise positional control for worker behavior
-- Workers use different points for spawning, idling, working, and resource delivery

local WorkerPointSystem = {}

-- Descriptive point types for different worker activities
export type WorkerPointType =
	"BuildingEntrance" -- Where workers first enter the building
	| "WorkerRestPosition" -- Where workers stand when idle/waiting for tasks
	| "ProductionStation" -- Where workers perform their primary work (forge, workbench, etc.)
	| "ResourceDropoff" -- Where workers deposit gathered/produced resources
	| "ResourcePickup" -- Where haulers collect resources from production buildings
	| "StorageAreaWood" -- Dedicated wood storage location
	| "StorageAreaStone" -- Dedicated stone storage location
	| "StorageAreaFood" -- Dedicated food storage location
	| "StorageAreaIron" -- Dedicated iron ore/bars storage location
	| "StorageAreaGold" -- Dedicated gold storage location
	| "StorageAreaWeapons" -- Dedicated weapons storage location
	| "StorageAreaGeneral" -- General purpose storage (fallback)

-- Type for point search results
export type PointSearchResult = {
	part: BasePart,
	position: Vector3,
	cframe: CFrame,
}

-- Configuration for search behavior
local CONFIG = {
	RECURSIVE_SEARCH = true, -- Search all descendants, not just direct children
	LOG_MISSING_POINTS = true, -- Log warnings when points are not found
	USE_PRIMARY_PART_FALLBACK = true, -- Fall back to PrimaryPart if point not found
}

-- Find a specific point within a building model
-- Returns the BasePart if found, nil otherwise
local function findPointPart(buildingModel: Model, pointName: string, silent: boolean?): BasePart?
	if not buildingModel or not buildingModel:IsA("Model") then
		warn(`WorkerPointSystem: Invalid building model provided`)
		return nil
	end

	-- Search for the point (recursive by default)
	local point = buildingModel:FindFirstChild(pointName, CONFIG.RECURSIVE_SEARCH)

	if point then
		-- If it's a BasePart, use it directly
		if point:IsA("BasePart") then
			return point :: BasePart
		end

		-- If it's a Model, try to use its PrimaryPart
		if point:IsA("Model") then
			local model = point :: Model
			if model.PrimaryPart then
				return model.PrimaryPart
			else
				-- Model doesn't have PrimaryPart, try to find any BasePart
				local firstPart = model:FindFirstChildWhichIsA("BasePart", true)
				if firstPart then
					return firstPart
				end
			end
		end

		-- If it's an Attachment, get the parent part
		if point:IsA("Attachment") then
			local attachment = point :: Attachment
			if attachment.Parent and attachment.Parent:IsA("BasePart") then
				return attachment.Parent :: BasePart
			end
		end
	end

	-- Point not found
	if CONFIG.LOG_MISSING_POINTS and not silent then
		-- Only log if it's not a storage-specific point (those are expected to be missing sometimes)
		if not pointName:match("StorageArea") then
			warn(`WorkerPointSystem: Point "{pointName}" not found in building {buildingModel.Name}`)
		end
	end

	return nil
end

-- Get fallback position if specific point not found
local function getFallbackPosition(buildingModel: Model, pointType: WorkerPointType): Vector3?
	if not CONFIG.USE_PRIMARY_PART_FALLBACK then
		return nil
	end

	-- Try to use PrimaryPart
	if buildingModel.PrimaryPart then
		return buildingModel.PrimaryPart.Position
	end

	-- Try to find any BasePart
	local firstPart = buildingModel:FindFirstChildWhichIsA("BasePart", true)
	if firstPart then
		return firstPart.Position
	end

	warn(`WorkerPointSystem: Cannot get fallback position for {buildingModel.Name} - no parts found`)
	return nil
end

-- Main function: Find a specific point in a building
function WorkerPointSystem.findPoint(buildingModel: Model, pointType: WorkerPointType): PointSearchResult?
	local pointPart = findPointPart(buildingModel, pointType)

	if pointPart then
		return {
			part = pointPart,
			position = pointPart.Position,
			cframe = pointPart.CFrame,
		}
	end

	-- No point found, try fallback
	local fallbackPos = getFallbackPosition(buildingModel, pointType)
	if fallbackPos then
		-- Create a synthetic result using the fallback
		local fallbackCFrame = CFrame.new(fallbackPos)
		if buildingModel.PrimaryPart then
			fallbackCFrame = buildingModel.PrimaryPart.CFrame
		end

		return {
			part = buildingModel.PrimaryPart or buildingModel:FindFirstChildWhichIsA("BasePart", true) :: BasePart,
			position = fallbackPos,
			cframe = fallbackCFrame,
		}
	end

	return nil
end

-- Get just the position of a point (most common use case)
function WorkerPointSystem.getPointPosition(buildingModel: Model, pointType: WorkerPointType): Vector3?
	local result = WorkerPointSystem.findPoint(buildingModel, pointType)
	return result and result.position or nil
end

-- Get the full CFrame of a point (includes rotation)
function WorkerPointSystem.getPointCFrame(buildingModel: Model, pointType: WorkerPointType): CFrame?
	local result = WorkerPointSystem.findPoint(buildingModel, pointType)
	return result and result.cframe or nil
end

-- Check if a building has a specific point
function WorkerPointSystem.hasPoint(buildingModel: Model, pointType: WorkerPointType): boolean
	-- Silent: hasPoint is a presence probe (often for optional points like
	-- TeleportIntoBuilding), so a missing point is not worth a warning.
	local pointPart = findPointPart(buildingModel, pointType, true)
	return pointPart ~= nil
end

-- Get the appropriate storage point for a specific resource type
-- This is the main function haulers use to find where to deposit resources
function WorkerPointSystem.getStoragePointForResource(
	buildingModel: Model,
	resourceType: string
): Vector3?
	-- Map resource types to their storage point names
	local resourceToPointMap: { [string]: WorkerPointType } = {
		Wood = "StorageAreaWood",
		Stone = "StorageAreaStone",
		Food = "StorageAreaFood",
		Bread = "StorageAreaFood",
		Flour = "StorageAreaFood",
		Ale = "StorageAreaFood",
		Iron_Ore = "StorageAreaIron",
		Iron_Bars = "StorageAreaIron",
		Coal = "StorageAreaIron",
		Gold = "StorageAreaGold",
		Weapons = "StorageAreaWeapons",
		Leather = "StorageAreaGeneral",
		Furniture = "StorageAreaGeneral",
		Manuscripts = "StorageAreaGeneral",
	}

	-- Try to find the specific storage point for this resource
	local specificPointType = resourceToPointMap[resourceType]
	if specificPointType then
		local specificPoint = WorkerPointSystem.getPointPosition(buildingModel, specificPointType)
		if specificPoint then
			return specificPoint
		end
	end

	-- Fallback 1: Try general storage point
	local generalPoint = WorkerPointSystem.getPointPosition(buildingModel, "StorageAreaGeneral")
	if generalPoint then
		return generalPoint
	end

	-- Fallback 2: Try building entrance
	local entrancePoint = WorkerPointSystem.getPointPosition(buildingModel, "BuildingEntrance")
	if entrancePoint then
		return entrancePoint
	end

	-- Fallback 3: Use building center (PrimaryPart)
	return getFallbackPosition(buildingModel, "StorageAreaGeneral")
end

-- Get the production station position for a worker
-- This is where workers do their actual work (at the forge, workbench, etc.)
function WorkerPointSystem.getProductionPosition(buildingModel: Model): Vector3?
	-- Try ProductionStation first
	local productionPos = WorkerPointSystem.getPointPosition(buildingModel, "ProductionStation")
	if productionPos then
		return productionPos
	end

	-- Fallback to WorkerRestPosition (workers can work where they rest if no dedicated station)
	local restPos = WorkerPointSystem.getPointPosition(buildingModel, "WorkerRestPosition")
	if restPos then
		return restPos
	end

	-- Final fallback to building entrance
	return WorkerPointSystem.getPointPosition(buildingModel, "BuildingEntrance")
end

-- Get the resource pickup point for haulers
-- This is where haulers go to collect completed resources from production buildings
-- For most buildings, this is the same as ResourceDropoff (workers drop, haulers pick up)
function WorkerPointSystem.getPickupPosition(buildingModel: Model): Vector3?
	-- Most buildings: haulers pick up from where workers drop off
	-- Try ResourceDropoff first (most common case) - but only if it actually exists
	if WorkerPointSystem.hasPoint(buildingModel, "ResourceDropoff") then
		local dropoffPos = WorkerPointSystem.getPointPosition(buildingModel, "ResourceDropoff")
		if dropoffPos then
			return dropoffPos
		end
	end

	-- Try ProductionStation (for buildings where resources are produced in place)
	if WorkerPointSystem.hasPoint(buildingModel, "ProductionStation") then
		local productionPos = WorkerPointSystem.getPointPosition(buildingModel, "ProductionStation")
		if productionPos then
			return productionPos
		end
	end

	-- Only try dedicated ResourcePickup as fallback (rare case for resource gatherers)
	if WorkerPointSystem.hasPoint(buildingModel, "ResourcePickup") then
		local pickupPos = WorkerPointSystem.getPointPosition(buildingModel, "ResourcePickup")
		if pickupPos then
			return pickupPos
		end
	end

	-- Final fallback to building entrance (always exists and is walkable)
	return WorkerPointSystem.getPointPosition(buildingModel, "BuildingEntrance")
end

-- Get the resource dropoff point for workers
-- This is where workers deposit gathered/produced resources within their building
function WorkerPointSystem.getDropoffPosition(buildingModel: Model): Vector3?
	-- Try ResourceDropoff first
	local dropoffPos = WorkerPointSystem.getPointPosition(buildingModel, "ResourceDropoff")
	if dropoffPos then
		return dropoffPos
	end

	-- Fallback to ProductionStation (drop off at workstation)
	local productionPos = WorkerPointSystem.getPointPosition(buildingModel, "ProductionStation")
	if productionPos then
		return productionPos
	end

	-- Final fallback to building entrance
	return WorkerPointSystem.getPointPosition(buildingModel, "BuildingEntrance")
end

-- Get all storage points in a building (useful for debugging/visualization)
function WorkerPointSystem.getAllStoragePoints(buildingModel: Model): { [string]: Vector3 }
	local storagePoints: { [string]: Vector3 } = {}

	local storagePointTypes: { WorkerPointType } = {
		"StorageAreaWood",
		"StorageAreaStone",
		"StorageAreaFood",
		"StorageAreaIron",
		"StorageAreaGold",
		"StorageAreaWeapons",
		"StorageAreaGeneral",
	}

	for _, pointType in storagePointTypes do
		local pos = WorkerPointSystem.getPointPosition(buildingModel, pointType)
		if pos then
			storagePoints[pointType] = pos
		end
	end

	return storagePoints
end

-- Get all worker points in a building (useful for debugging/visualization)
function WorkerPointSystem.getAllWorkerPoints(buildingModel: Model): { [string]: Vector3 }
	local workerPoints: { [string]: Vector3 } = {}

	local workerPointTypes: { WorkerPointType } = {
		"BuildingEntrance",
		"WorkerRestPosition",
		"ProductionStation",
		"ResourceDropoff",
		"ResourcePickup",
	}

	for _, pointType in workerPointTypes do
		local pos = WorkerPointSystem.getPointPosition(buildingModel, pointType)
		if pos then
			workerPoints[pointType] = pos
		end
	end

	return workerPoints
end

-- Validate that a building has the minimum required points for workers
-- Returns true if valid, false + error message if invalid
function WorkerPointSystem.validateWorkerBuilding(buildingModel: Model): (boolean, string?)
	-- Every building should at least have a BuildingEntrance (or fallback to PrimaryPart)
	local entrance = WorkerPointSystem.getPointPosition(buildingModel, "BuildingEntrance")
	if not entrance then
		return false, `Building {buildingModel.Name} has no BuildingEntrance and no PrimaryPart fallback`
	end

	-- Production buildings should have a ProductionStation
	if buildingModel:GetAttribute("RequiresWorker") then
		local productionStation = WorkerPointSystem.getPointPosition(buildingModel, "ProductionStation")
		if not productionStation then
			return false, `Production building {buildingModel.Name} is missing ProductionStation point`
		end
	end

	return true, nil
end

-- Validate that a storage building has appropriate storage points
function WorkerPointSystem.validateStorageBuilding(buildingModel: Model): (boolean, string?)
	-- Storage buildings should have at least StorageAreaGeneral or specific storage points
	local generalStorage = WorkerPointSystem.hasPoint(buildingModel, "StorageAreaGeneral")
	local hasAnySpecificStorage = WorkerPointSystem.hasPoint(buildingModel, "StorageAreaWood")
		or WorkerPointSystem.hasPoint(buildingModel, "StorageAreaStone")
		or WorkerPointSystem.hasPoint(buildingModel, "StorageAreaFood")
		or WorkerPointSystem.hasPoint(buildingModel, "StorageAreaIron")
		or WorkerPointSystem.hasPoint(buildingModel, "StorageAreaGold")
		or WorkerPointSystem.hasPoint(buildingModel, "StorageAreaWeapons")

	if not generalStorage and not hasAnySpecificStorage then
		return false,
			`Storage building {buildingModel.Name} has no storage points (needs StorageAreaGeneral or specific storage points)`
	end

	return true, nil
end

-- Debug: Print all points found in a building
function WorkerPointSystem.debugPrintPoints(buildingModel: Model)
	print(`\n=== WorkerPointSystem Debug: {buildingModel.Name} ===`)

	print("\nWorker Points:")
	local workerPoints = WorkerPointSystem.getAllWorkerPoints(buildingModel)
	for pointType, position in workerPoints do
		print(`  {pointType}: {position}`)
	end

	print("\nStorage Points:")
	local storagePoints = WorkerPointSystem.getAllStoragePoints(buildingModel)
	for pointType, position in storagePoints do
		print(`  {pointType}: {position}`)
	end

	print("\nValidation:")
	local workerValid, workerError = WorkerPointSystem.validateWorkerBuilding(buildingModel)
	print(`  Worker Building Valid: {workerValid}` .. (workerError and ` - {workerError}` or ""))

	local storageValid, storageError = WorkerPointSystem.validateStorageBuilding(buildingModel)
	print(`  Storage Building Valid: {storageValid}` .. (storageError and ` - {storageError}` or ""))

	print("=== End Debug ===\n")
end

return WorkerPointSystem
