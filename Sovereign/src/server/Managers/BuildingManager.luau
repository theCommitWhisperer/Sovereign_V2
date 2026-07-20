--!strict
-- BuildingManager: Handles building creation and management

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameData = require(ReplicatedStorage.Shared.GameData)
local BuildingScaleConfig = require(ReplicatedStorage.Shared.GameData.BuildingScaleConfig)
local PlayerManager = require(script.Parent.PlayerManager)
local SpawnManager = require(script.Parent.SpawnManager)
local WallSystem = require(script.Parent.Parent.Systems.WallSystem)

local DebugManager = require(ReplicatedStorage.Shared.DebugManager)
local StorageDebug = DebugManager.createChannel("Storage", false)
local channel = DebugManager.createChannel("BuildingManager", false)

-- Import new A* pathfinding integration
local PathfindingIntegration = require(script.Parent.Parent.Systems.PathfindingIntegration)

local BuildingManager = {}

-- Track stored resources in buildings
local BuildingStorage: { [Instance]: { [string]: number } } = {}

-- Ensure a building model has the named worker-point parts that
-- PathfindingIntegration.addObstacle scans for when punching walkable holes.
-- If any required point is missing from the model we create a small invisible
-- part at a sensible offset so the pathfinding grid stays navigable.
local function ensureWorkerPoints(building: Model, buildingInfo: any, cframe: CFrame)
	-- Use the model's ACTUAL bounding box, not buildingInfo.size.
	-- addObstacle uses getCustomBoundingBox (the real model geometry) to mark
	-- the obstacle, so we must base our offsets on the real extent or worker
	-- points end up inside the obstacle (especially for large models like Keep).
	local _, actualSize = building:GetBoundingBox()
	local size = actualSize or buildingInfo.size or Vector3.new(8, 8, 8)
	local halfX = size.X / 2
	local halfZ = size.Z / 2
	-- margin must exceed BUILDING_PADDING (2 studs) in PathfindingIntegration
	-- so points sit clearly outside the unwalkable footprint.
	local margin = 6
	local forward = cframe.LookVector
	local right = cframe.RightVector
	local center = cframe.Position

	local function createPoint(name: string, position: Vector3)
		if building:FindFirstChild(name, true) then
			return -- model already has this part
		end
		local point = Instance.new("Part")
		point.Name = name
		point.Size = Vector3.new(1, 1, 1)
		point.Position = position
		point.Anchored = true
		point.CanCollide = false
		point.Transparency = 1
		point.Parent = building
	end

	local needsWorker = buildingInfo.requires_worker ~= nil
	local needsStorage = buildingInfo.storage_capacity ~= nil

	-- Every interactive building needs an entrance peasants can walk to
	if needsWorker or needsStorage then
		createPoint("BuildingEntrance", center + forward * (halfZ + margin))
	end

	if needsWorker then
		-- All worker points OUTSIDE the obstacle footprint (actual model bbox + padding).
		-- PathfindingIntegration punches 16-stud walkable holes around each.
		createPoint("ProductionStation", center + forward * (halfZ + margin) + right * margin)
		createPoint("ResourceDropoff", center + right * (halfX + margin))
		createPoint("WorkerRestPosition", center - forward * (halfZ + margin))
	end

	if needsStorage then
		createPoint("StorageAreaGeneral", center - right * (halfX + margin))
	end
end

-- Ensure Buildings folder exists
local BuildingsFolder = Workspace:FindFirstChild("Buildings")
if not BuildingsFolder then
	BuildingsFolder = Instance.new("Folder")
	BuildingsFolder.Name = "Buildings"
	BuildingsFolder.Parent = Workspace
end

-- Check if a position is clear of other buildings and units
local function isPositionClear(position: Vector3, minimumDistance: number): boolean
	minimumDistance = minimumDistance or 20 -- Default 20 studs minimum distance (reduced from 25)

	-- Check against all existing buildings
	local buildingsFolder = Workspace:FindFirstChild("Buildings")
	if buildingsFolder then
		for _, building in buildingsFolder:GetChildren() do
			if building:IsA("Model") then
				local buildingPos = building:GetPivot().Position
				local distance = (buildingPos - position).Magnitude
				if distance < minimumDistance then
					local buildingType = building:GetAttribute("BuildingType") or building.Name
					channel:warn(
						`Position {position} blocked by {buildingType} at {buildingPos} (distance: {math.floor(distance)} studs, minimum: {minimumDistance})`
					)
					return false
				end
			end
		end
	end

	-- Check against units
	local unitsFolder = Workspace:FindFirstChild("Units")
	if unitsFolder then
		for _, unit in unitsFolder:GetChildren() do
			if unit:IsA("Model") then
				local unitPos = unit:GetPivot().Position
				local distance = (unitPos - position).Magnitude
				if distance < 15 then -- Units need less clearance
					local unitType = unit:GetAttribute("UnitType") or unit.Name
					channel:warn(
						`Position {position} blocked by {unitType} unit at {unitPos} (distance: {math.floor(distance)} studs)`
					)
					return false
				end
			end
		end
	end

	channel:info(`Position {position} is clear - no collisions detected`)
	return true
end

function BuildingManager.createBuilding(
	player: Player | number, -- Can be Player object or ownerId (number for AI)
	buildingName: string,
	cframe: CFrame,
	wallPieceType: string?,
	manualRotation: number?,
	skipCost: boolean?
): Instance?
	local buildingInfo = GameData.Buildings[buildingName]
	if not buildingInfo then
		channel:warn(`Unknown building: {buildingName}`)
		return nil
	end

	-- Get ownerId and ownerName (support both Player and AI)
	local ownerId: number
	local ownerName: string
	local isAI = false

	if typeof(player) == "Instance" and player:IsA("Player") then
		ownerId = player.UserId
		ownerName = player.Name
	else
		ownerId = player :: number
		ownerName = `AI_{ownerId}`
		isAI = true
	end

	-- Check if owner can build in this location (territory check)
	local quadrant = SpawnManager.getPlayerQuadrant(ownerId)
	if quadrant then
		local buildPosition = cframe.Position
		if not SpawnManager.isPositionInEstate(buildPosition, quadrant) then
			channel:warn(`{ownerName} tried to build outside their estate (Quadrant {quadrant})`)
			return nil
		end
	end

	-- Check for collisions with existing buildings and units
	-- (clearance shrinks with the global building scale)
	if not isPositionClear(cframe.Position, BuildingScaleConfig.scaleDistance(25)) then
		channel:warn(`{ownerName} cannot build {buildingName} - position blocked by existing structure or unit`)
		return nil
	end

	channel:info(`Creating {buildingName} for {ownerName}`)

	-- Check for Assets first
	local Assets = ReplicatedStorage:FindFirstChild("Assets")
	local buildingAssets = Assets and Assets:FindFirstChild("Buildings")
	local modelAsset = nil

	-- Try to find the specific asset defined in BuildingData, or default to name
	local assetName = buildingInfo.model_asset_name or buildingName

	-- Special handling for Wall buildings: Use provided piece type or the building's asset
	local isWallBuilding = buildingName == "Stone_Wall"
		or buildingName == "Wall_Segment"
		or buildingName == "Wall_Corner"
		or buildingName == "Wall_Corner_Reverse"
		or buildingName == "Wall_Tower"
		or buildingName == "Wall_Gatehouse"
		or buildingName == "Ladder_Wall_Segment"

	if buildingName == "Stone_Wall" then
		assetName = wallPieceType or "Wall Segment"
	elseif isWallBuilding and buildingInfo.model_asset_name then
		assetName = buildingInfo.model_asset_name
	end

	if buildingAssets then
		local foundTemplate = buildingAssets:FindFirstChild(assetName)
		if foundTemplate then
			modelAsset = foundTemplate:Clone()

			-- Global building miniaturisation (see BuildingScaleConfig)
			if modelAsset:IsA("Model") then
				BuildingScaleConfig.applyToModel(modelAsset)
			end

			-- Ensure all ConnectionPoints are non-collidable and NOT anchored so they move with the model pivot.
			local connectionPointsFolder = modelAsset:FindFirstChild("ConnectionPoints")
			if connectionPointsFolder then
				for _, cp in connectionPointsFolder:GetChildren() do
					if cp:IsA("BasePart") and cp.Name == "ConnectionPoint" then
						cp.Anchored = false
						cp.CanCollide = false
					end
				end
			else
				-- Fallback: search descendants for ConnectionPoints
				for _, descendant in modelAsset:GetDescendants() do
					if descendant:IsA("BasePart") and descendant.Name == "ConnectionPoint" then
						descendant.Anchored = false
						descendant.CanCollide = false
					end
				end
			end
		end
	end

	local building
	if modelAsset then
		-- Use the actual model
		building = modelAsset
		building.Name = `{buildingName}_{ownerId}`

		-- Position the building using the provided CFrame exactly as-is
		building:PivotTo(cframe)
	else
		-- [FIXED] Fallback logic to ensure it creates a Model with a PrimaryPart
		building = Instance.new("Model")
		building.Name = `{buildingName}_{ownerId}`

		local part = Instance.new("Part")
		part.Name = "MainPart"
		part.Size = buildingInfo.size * BuildingScaleConfig.GlobalScale
		part.CFrame = cframe
		part.Anchored = true
		part.Material = Enum.Material.Wood
		part.Parent = building
		building.PrimaryPart = part

		if buildingInfo.subtype == "Castle Core" then
			part.Color = Color3.fromRGB(139, 69, 19)
		elseif buildingInfo.subtype == "Storage" then
			part.Color = Color3.fromRGB(205, 133, 63)
		else
			part.Color = Color3.fromRGB(139, 69, 19)
		end
	end

	-- Anchor all parts in the building to prevent physics movement
	for _, descendant in building:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
		end
	end

	-- Add ownership attributes
	building:SetAttribute("OwnerId", ownerId)
	building:SetAttribute("BuildingType", buildingName)
	building:SetAttribute("IsConstructed", true)

	-- For walls, set manual placement attributes BEFORE registering with WallSystem
	if isWallBuilding then
		if wallPieceType then
			building:SetAttribute("ManualPieceType", wallPieceType)
		end
		if manualRotation then
			building:SetAttribute("ManualRotation", manualRotation)
		end
	end

	-- Initialize storage if building has storage capacity
	if buildingInfo.storage_capacity then
		BuildingStorage[building] = {}
		for resourceType, _ in pairs(buildingInfo.storage_capacity) do
			BuildingStorage[building][resourceType] = 0
			-- Replicated mirror so the client shows 0/max before any production.
			building:SetAttribute(`Storage_{resourceType}`, 0)
		end
	end

	-- Register with WallSystem if it's a wall
	building.Parent = BuildingsFolder
	if isWallBuilding then
		WallSystem.registerWall(building)
	end

	-- Ensure the model has named worker-point parts so PathfindingIntegration
	-- can punch walkable holes around them. Missing points are created as
	-- invisible anchored parts at sensible offsets from the building center.
	ensureWorkerPoints(building, buildingInfo, cframe)

	-- Add building as obstacle to A* pathfinding grid
	PathfindingIntegration.addObstacle(building)

	-- Cache a guaranteed-walkable approach position so workers/haulers navigate to
	-- open ground next to the building instead of depending on authored worker-point
	-- parts (which can end up inside the obstacle or buried by a neighbour).
	local approach = PathfindingIntegration.getApproachPosition(building)
	if approach then
		building:SetAttribute("ApproachPosition", approach)
	end

	-- Listen for building destruction to remove from pathfinding grid
	building.Destroying:Connect(function()
		PathfindingIntegration.removeObstacle(building)
	end)

	-- Lazy-load GameplayEnhancementManager to avoid circular dependency (only for real players)
	if not isAI then
		local success, err = pcall(function()
			local GameplayEnhancementManager = require(script.Parent.GameplayEnhancementManager)
			GameplayEnhancementManager.onBuildingCreated(building, buildingName, ownerId)
		end)
		if not success then
			warn("GameplayEnhancementManager error:", err)
		end
	end

	-- Track in player data (only for real players, not AI)
	if not isAI and typeof(player) == "Instance" then
		local actualPlayer = player
		PlayerManager.addBuilding(actualPlayer, building)

		-- Special case for Keep
		local playerData = PlayerManager.get(actualPlayer)
		if playerData and buildingName == "Keep" then
			playerData.Keep = building
			channel:info("Keep registered for " .. actualPlayer.Name)
			-- Note: Peasant spawning is now handled by GameManager using SpawnPointSystem
		end
	end

	return building
end

-- Take resources from a building's storage
function BuildingManager.takeFromStorage(building: Instance, resourceType: string, amount: number): number
	if not BuildingStorage[building] or not BuildingStorage[building][resourceType] then
		return 0
	end

	local currentAmount = BuildingStorage[building][resourceType]
	local amountToTake = math.min(amount, currentAmount)
	BuildingStorage[building][resourceType] = currentAmount - amountToTake

	-- Mirror to a replicated attribute so the client (WorkerAssignmentPanel,
	-- tooltips) sees live storage without an extra remote.
	building:SetAttribute(`Storage_{resourceType}`, BuildingStorage[building][resourceType])

	return amountToTake
end

-- Add resources to a building's storage
function BuildingManager.addToStorage(building: Instance, resourceType: string, amount: number): number
	StorageDebug:info(`addToStorage called: building={building.Name}, resourceType={resourceType}, amount={amount}`)

	if not BuildingStorage[building] then
		StorageDebug:warn(`Building {building.Name} has no storage initialized`)
		return 0 -- Building has no storage
	end

	if not BuildingStorage[building][resourceType] then
		StorageDebug:warn(`Building {building.Name} cannot store {resourceType}`)
		return 0 -- Building can't store this resource
	end

	local buildingType = building:GetAttribute("BuildingType")
	local buildingInfo = GameData.Buildings[buildingType]
	if not buildingInfo or not buildingInfo.storage_capacity then
		return 0
	end

	local maxCapacity = buildingInfo.storage_capacity[resourceType] or 0
	local currentAmount = BuildingStorage[building][resourceType]
	local spaceAvailable = maxCapacity - currentAmount

	local amountToAdd = math.min(amount, spaceAvailable)
	BuildingStorage[building][resourceType] = currentAmount + amountToAdd

	-- Mirror to a replicated attribute so the client sees live storage.
	building:SetAttribute(`Storage_{resourceType}`, BuildingStorage[building][resourceType])

	StorageDebug:info(`Added to storage`, {
		building = buildingType,
		resourceType = resourceType,
		amountAdded = amountToAdd,
		newTotal = BuildingStorage[building][resourceType],
		maxCapacity = maxCapacity,
	})

	return amountToAdd
end

-- Get current storage amount
function BuildingManager.getStorageAmount(building: Instance, resourceType: string): number
	if not BuildingStorage[building] or not BuildingStorage[building][resourceType] then
		return 0
	end
	return BuildingStorage[building][resourceType]
end

-- Check if building has space for resources
function BuildingManager.hasStorageSpace(building: Instance, resourceType: string, amount: number): boolean
	if not BuildingStorage[building] or not BuildingStorage[building][resourceType] then
		return false
	end

	local buildingType = building:GetAttribute("BuildingType")
	local buildingInfo = GameData.Buildings[buildingType]
	if not buildingInfo or not buildingInfo.storage_capacity then
		return false
	end

	local maxCapacity = buildingInfo.storage_capacity[resourceType] or 0
	local currentAmount = BuildingStorage[building][resourceType]

	return (currentAmount + amount) <= maxCapacity
end

return BuildingManager
                                                                                                                                                                                                                                                                                                                                                                                                                  