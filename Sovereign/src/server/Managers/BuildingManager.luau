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
local channel = DebugManager.createChannel("BuildingManager", false)

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

function BuildingManager.createBuilding(
	player: Player,
	buildingName: string,
	cframe: CFrame,
	wallPieceType: string?,
	manualRotation: number?
): Instance?
	local buildingInfo = GameData.Buildings[buildingName]
	if not buildingInfo then
		channel:warn(`Unknown building: {buildingName}`)
		return nil
	end

	-- Check if player can build in this location (territory check)
	local quadrant = SpawnManager.getPlayerQuadrant(player.UserId)
	if quadrant then
		local buildPosition = cframe.Position
		if not SpawnManager.isPositionInEstate(buildPosition, quadrant) then
			channel:warn(`{player.Name} tried to build outside their estate (Quadrant {quadrant})`)
			-- TODO: Send error message to client
			return nil
		end
	end

	channel:info(`Creating {buildingName} for {player.Name}`)

	-- [MODIFIED] Check for Assets first
	local Assets = ReplicatedStorage:FindFirstChild("Assets")
	local buildingAssets = Assets and Assets:FindFirstChild("Buildings")
	local modelAsset = nil
	
	-- Try to find the specific asset defined in BuildingData, or default to name
	local assetName = buildingInfo.model_asset_name or buildingName
	
	-- Special handling for Wall: Use provided piece type or default to Straight
	if buildingName == "Stone_Wall" then
		assetName = wallPieceType or "Wall Segment"
	end
	
	if buildingAssets then
		local foundTemplate = buildingAssets:FindFirstChild(assetName)
		if foundTemplate then
			modelAsset = foundTemplate:Clone()
		end
	end

	local building
	if modelAsset then
		-- Use the actual model
		building = modelAsset
		building.Name = `{buildingName}_{player.UserId}`
		building:PivotTo(cframe)
	else
		-- Fallback to generic part (your existing code)
		building = Instance.new("Part")
		building.Name = `{buildingName}_{player.UserId}`
		building.Size = buildingInfo.size
		building.CFrame = cframe
		building.Anchored = true
		building.Material = Enum.Material.Wood
		-- ... (Keep existing color logic for fallbacks)
		if buildingInfo.subtype == "Castle Core" then
			building.Color = Color3.fromRGB(139, 69, 19) -- Brown
		elseif buildingInfo.subtype == "Storage" then
			building.Color = Color3.fromRGB(205, 133, 63) -- Peru/tan
		elseif buildingInfo.subtype == "Resource Gathering" then
			building.Color = Color3.fromRGB(160, 82, 45) -- Sienna
		elseif
			buildingInfo.subtype == "Food Production"
			or buildingInfo.subtype == "Food Processing"
			or buildingInfo.subtype == "Food Service"
		then
			building.Color = Color3.fromRGB(244, 164, 96) -- Sandy brown
		elseif buildingInfo.subtype == "Housing" then
			building.Color = Color3.fromRGB(210, 180, 140) -- Tan
		else
			building.Color = Color3.fromRGB(139, 69, 19)
		end
	end

	-- Add ownership attribute
	building:SetAttribute("Owner", player.UserId)
	building:SetAttribute("BuildingType", buildingName)
	building:SetAttribute("IsConstructed", true)

	-- For walls, set manual placement attributes BEFORE registering with WallSystem
	if buildingName == "Stone_Wall" then
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

	-- [ADDED] Register with WallSystem if it's a wall
	building.Parent = BuildingsFolder
	if buildingName == "Stone_Wall" then
		WallSystem.registerWall(building)
	end

	-- Track in player data
	PlayerManager.addBuilding(player, building)

	-- Special case for Keep
	local playerData = PlayerManager.get(player)
	if playerData and buildingName == "Keep" then
		playerData.Keep = building
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
