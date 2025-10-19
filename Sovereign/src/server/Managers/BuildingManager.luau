--!strict
-- BuildingManager: Handles building creation and management

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameData = require(ReplicatedStorage.Shared.GameData)
local PlayerManager = require(script.Parent.PlayerManager)

local DebugManager = require(ReplicatedStorage.Shared.DebugManager)
local StorageDebug = DebugManager.createChannel("Storage", true)

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

function BuildingManager.createBuilding(player: Player, buildingName: string, cframe: CFrame): Instance?
	local buildingInfo = GameData.Buildings[buildingName]
	if not buildingInfo then
		warn(`[BuildingManager] Unknown building: {buildingName}`)
		return nil
	end

	print(`[BuildingManager] Creating {buildingName} for {player.Name}`)

	-- Create a simple part for now (we'll add models later)
	local building = Instance.new("Part")
	building.Name = `{buildingName}_{player.UserId}`
	building.Size = buildingInfo.size
	building.CFrame = cframe
	building.Anchored = true
	building.Material = Enum.Material.Wood

	-- Color based on building type
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

	-- Add ownership attribute
	building:SetAttribute("Owner", player.UserId)
	building:SetAttribute("BuildingType", buildingName)
	building:SetAttribute("IsConstructed", true)

	-- Initialize storage if building has storage capacity
	if buildingInfo.storage_capacity then
		BuildingStorage[building] = {}
		for resourceType, _ in pairs(buildingInfo.storage_capacity) do
			BuildingStorage[building][resourceType] = 0
		end
	end

	building.Parent = BuildingsFolder

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
