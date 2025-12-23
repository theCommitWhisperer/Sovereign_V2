--!strict
-- BuildingManager: Handles building creation and management

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameData = require(ReplicatedStorage.Shared.GameData)
local PlayerManager = require(script.Parent.PlayerManager)
local SpawnManager = require(script.Parent.SpawnManager)
local WallSystem = require(script.Parent.Parent.Systems.WallSystem)

local DebugManager = require(ReplicatedStorage.Shared.DebugManager)
local StorageDebug = DebugManager.createChannel("Storage", false)
local channel = DebugManager.createChannel("BuildingManager", true) -- Enable debug for AI building issues

local BuildingManager = {}

-- Track stored resources in buildings
local BuildingStorage: { [Instance]: { [string]: number } } = {}

-- Ensure Buildings folder exists
local BuildingsFolder = Workspace:FindFirstChild("Buildings")
if not BuildingsFolder then
	BuildingsFolder = Instance.new("Folder")
	BuildingsFolder.Name = "Buildings"
	BuildingsFolder.Parent = Workspace
end

-- Check if a position is clear of other buildings and units
local function isPositionClear(position: Vector3, minimumDistance: number): boolean
	minimumDistance = minimumDistance or 25 -- Default 25 studs minimum distance

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
	if not isPositionClear(cframe.Position, 25) then
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
		part.Size = buildingInfo.size
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

	-- Add ownership attribute
	building:SetAttribute("Owner", ownerId)
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
		end
	end

	-- Register with WallSystem if it's a wall
	building.Parent = BuildingsFolder
	if isWallBuilding then
		WallSystem.registerWall(building)
	end

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
		PlayerManager.addBuilding(player :: Player, building)

		-- Special case for Keep
		local playerData = PlayerManager.get(player :: Player)
		if playerData and buildingName == "Keep" then
			playerData.Keep = building
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

	return amountToTake
end

-- Add resources to a building's storage
function BuildingManager.addToStorage(building: Instance, resourceType: string, amount: number): number
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
