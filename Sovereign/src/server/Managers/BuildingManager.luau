--!strict
-- BuildingManager: Handles building creation and management

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameData = require(ReplicatedStorage.Shared.GameData)
local PlayerManager = require(script.Parent.PlayerManager)
local SpawnManager = require(script.Parent.SpawnManager)
local WallManager = require(script.Parent.WallManager)

local DebugManager = require(ReplicatedStorage.Shared.DebugManager)
local StorageDebug = DebugManager.createChannel("Storage", false)
local channel = DebugManager.createChannel("BuildingManager", true) -- Enable debug for testing

local BuildingManager = {}

-- Helper: Check if building type is a wall
local function isWall(buildingName: string): boolean
	local buildingInfo = GameData.Buildings[buildingName]
	return buildingInfo and buildingInfo.type == "Wall"
end

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
		channel:warn(`Unknown building: {buildingName}`)
		return nil
	end

	-- Raycast down to find terrain/ground height at this position
	local buildPosition = cframe.Position
	local rayOrigin = Vector3.new(buildPosition.X, 200, buildPosition.Z)
	local rayDirection = Vector3.new(0, -300, 0)

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.IgnoreWater = true

	local terrainResult = Workspace:Raycast(rayOrigin, rayDirection, rayParams)
	local groundY = buildPosition.Y

	if terrainResult then
		-- Check if we hit the baseplate - if so, use terrain voxels instead
		if terrainResult.Instance.Name == "Baseplate" then
			-- Sample terrain voxel at this position
			local terrain = Workspace.Terrain
			local gridX = buildPosition.X
			local gridZ = buildPosition.Z
			local region = Region3.new(Vector3.new(gridX - 0.1, 0, gridZ - 0.1), Vector3.new(gridX + 0.1, 200, gridZ + 0.1))
			region = region:ExpandToGrid(4)
			local materials, _ = terrain:ReadVoxels(region, 4)
			local size = materials.Size

			-- Find highest non-air voxel
			for y = size.Y, 1, -1 do
				if materials[1][y][1] ~= Enum.Material.Air then
					groundY = (y - 1) * 4 + region.CFrame.Position.Y - region.Size.Y / 2
					break
				end
			end
			channel:info(`Found terrain voxel at height: {groundY}`)
		else
			groundY = terrainResult.Position.Y
			channel:info(`Hit non-baseplate surface at height: {groundY}`)
		end
	end

	channel:info(`Final ground height at ({buildPosition.X}, {buildPosition.Z}): {groundY}`)

	-- Adjust CFrame to be at ground level, preserving rotation
	local adjustedCFrame = CFrame.new(buildPosition.X, groundY, buildPosition.Z) * (cframe - cframe.Position)

	-- Check if player can build in this location (territory check)
	local quadrant = SpawnManager.getPlayerQuadrant(player.UserId)
	if quadrant then
		if not SpawnManager.isPositionInEstate(adjustedCFrame.Position, quadrant) then
			channel:warn(`{player.Name} tried to build outside their estate (Quadrant {quadrant})`)
			-- TODO: Send error message to client
			return nil
		end
	end

	channel:info(`Creating {buildingName} for {player.Name}`)

	local building: Instance

	-- Try to load model from assets if available
	if buildingInfo.model_asset_name then
		-- Try multiple possible paths for assets
		local buildingsFolder = ReplicatedStorage:FindFirstChild("Shared")
			and ReplicatedStorage.Shared:FindFirstChild("assets")
			and ReplicatedStorage.Shared.assets:FindFirstChild("buildings")

		if not buildingsFolder then
			buildingsFolder = ReplicatedStorage:FindFirstChild("Assets")
				and ReplicatedStorage.Assets:FindFirstChild("buildings")
		end

		if buildingsFolder then
			local modelAsset = buildingsFolder:FindFirstChild(buildingInfo.model_asset_name)
			if modelAsset then
				building = modelAsset:Clone()
				building.Name = `{buildingName}_{player.UserId}`

				-- Scale straight walls slightly for overlap (apply to all walls initially, will be adjusted by WallManager)
				if building:IsA("Model") and isWall(buildingName) then
					local scaleAmount = 1.06
					-- Determine rotation from CFrame
					local _, _, _, m11 = cframe:GetComponents()
					local isEastWest = math.abs(m11) < 0.5 -- Rotated 90° or 270°

					for _, descendant in building:GetDescendants() do
						if descendant:IsA("BasePart") then
							local originalSize = descendant.Size
							-- Scale in the direction the wall extends
							if isEastWest then
								descendant.Size = Vector3.new(originalSize.X * scaleAmount, originalSize.Y, originalSize.Z)
							else
								descendant.Size = Vector3.new(originalSize.X, originalSize.Y, originalSize.Z * scaleAmount)
							end
						end
					end
					channel:info(`Scaled straight wall by {scaleAmount}x for overlap`)
				end

				-- Set CFrame for model (with correct upright orientation)
				if building:IsA("Model") then
					-- Models need to be rotated to stand upright
					local uprightRotation = CFrame.Angles(math.rad(-90), 0, 0)

					-- Position directly at ground level (models pivot is already at bottom)
					-- The model's pivot should be at its base, so just place at groundY
					building:PivotTo(CFrame.new(buildPosition.X, groundY, buildPosition.Z) * (cframe - cframe.Position) * uprightRotation)

					channel:info(`Placed model at ground Y: {groundY}`)
				else
					building.CFrame = adjustedCFrame
				end

				channel:info(`Loaded model asset: {buildingInfo.model_asset_name} at ground level {groundY}`)
			else
				channel:warn(`Model asset not found: {buildingInfo.model_asset_name}`)
			end
		else
			channel:warn("Buildings folder not found in ReplicatedStorage")
		end
	end

	-- Fallback: Create a simple part if no model found
	if not building then
		building = Instance.new("Part")
		building.Name = `{buildingName}_{player.UserId}`
		building.Size = buildingInfo.size

		-- Position part with bottom on ground (add half the height)
		local partBottomY = groundY + (buildingInfo.size.Y / 2)
		local partCFrame = CFrame.new(buildPosition.X, partBottomY, buildPosition.Z) * (cframe - cframe.Position)
		building.CFrame = partCFrame

		building.Anchored = true
		building.Material = Enum.Material.Wood

		channel:info(`Created fallback part at Y: {partBottomY} (ground: {groundY}, offset: {buildingInfo.size.Y / 2})`)

		-- Color based on building type
		if buildingInfo.type == "Wall" then
			building.Color = Color3.fromRGB(139, 69, 19) -- Wall color (brown/stone)
			building.Material = Enum.Material.Cobblestone
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
		elseif buildingInfo.subtype == "Defense" then
			building.Color = Color3.fromRGB(105, 105, 105) -- Gray for defense buildings
		else
			building.Color = Color3.fromRGB(139, 69, 19) -- Default brown for Castle Core and others
		end
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

	-- Register wall with WallManager if it's a wall type
	if isWall(buildingName) then
		WallManager.registerWall(building, player.UserId, buildingName)
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

-- Delete a building
function BuildingManager.deleteBuilding(building: Instance)
	local buildingType = building:GetAttribute("BuildingType")

	-- Remove wall from WallManager if it's a wall
	if buildingType and isWall(buildingType) then
		WallManager.removeWall(building)
	end

	-- Clear storage data
	if BuildingStorage[building] then
		BuildingStorage[building] = nil
	end

	-- Remove from workspace
	building:Destroy()
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
