--!strict
-- UnitManager: Handles unit creation and management

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local ServerStorage = game:GetService("ServerStorage")

local GameData = require(ReplicatedStorage.Shared.GameData)
local PlayerManager = require(script.Parent.PlayerManager) -- Same folder now

local UnitManager = {}

-- Ensure Units folder exists
local UnitsFolder = Workspace:FindFirstChild("Units")
if not UnitsFolder then
	UnitsFolder = Instance.new("Folder")
	UnitsFolder.Name = "Units"
	UnitsFolder.Parent = Workspace
end

local function loadModelFromAsset(assetId: number): Model?
	local success, model = pcall(function()
		return game:GetService("InsertService"):LoadAsset(assetId)
	end)

	if success and model then
		local actualModel = model:FindFirstChildOfClass("Model")
		if actualModel then
			actualModel.Parent = ServerStorage
			model:Destroy()
			return actualModel
		end
	end

	return nil
end

-- Try to find a dummy model, create a simple one if not found
local function getDummyModel(): Model
	local dummy = ServerStorage:FindFirstChild("Dummy")
	if dummy and dummy:IsA("Model") then
		return dummy
	end

	local PEASANT_ASSET_ID = 0 -- Replace with actual asset ID
	if PEASANT_ASSET_ID > 0 then
		local loaded = loadModelFromAsset(PEASANT_ASSET_ID)
		if loaded then
			loaded.Name = "Dummy"
			return loaded
		end
	end

	warn("[UnitManager] No Dummy found in ServerStorage, creating simple model")
	local model = Instance.new("Model")
	model.Name = "Dummy"

	-- Make HumanoidRootPart larger and more visible for easier selection
	local humanoidRootPart = Instance.new("Part")
	humanoidRootPart.Name = "HumanoidRootPart"
	humanoidRootPart.Size = Vector3.new(2, 4, 2) -- Made taller (was 2,2,1)
	humanoidRootPart.Transparency = 0.7 -- More visible
	humanoidRootPart.CanCollide = false
	humanoidRootPart.Color = Color3.fromRGB(150, 150, 150)
	humanoidRootPart.Material = Enum.Material.SmoothPlastic
	humanoidRootPart.Parent = model

	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(2, 2, 2) -- Made bigger (was 2,1,1)
	head.Color = Color3.fromRGB(255, 204, 153) -- Skin tone
	head.CanCollide = false
	head.Shape = Enum.PartType.Ball -- Make it a sphere
	head.Parent = model

	local humanoid = Instance.new("Humanoid")
	humanoid.Parent = model

	model.PrimaryPart = humanoidRootPart

	-- Position head on top of body
	head.Position = humanoidRootPart.Position + Vector3.new(0, 3, 0)

	-- Weld head to HRP
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = humanoidRootPart
	weld.Part1 = head
	weld.Parent = humanoidRootPart

	model.Parent = ServerStorage
	return model
end

function UnitManager.createUnit(unitType: string, ownerId: number, position: Vector3?): Model?
	local unitInfo = GameData.Units[unitType]
	if not unitInfo then
		warn(`[UnitManager] Unknown unit type: {unitType}`)
		return nil
	end

	-- Get player safely - wrap in pcall in case ownerId is invalid
	local success, player = pcall(function()
		return game.Players:GetPlayerByUserId(ownerId)
	end)

	local playerName = "Unknown"
	if success and player then
		playerName = player.Name
	else
		playerName = tostring(ownerId)
	end

	print(`[UnitManager] Creating {unitType} for {playerName} (ID: {ownerId})`)

	-- Get dummy model
	local dummyModel = getDummyModel()
	if not dummyModel then
		warn("[UnitManager] Failed to get dummy model")
		return nil
	end

	-- Clone the dummy
	local unit = dummyModel:Clone()

	-- Generate unique ID
	local uniqueId = tostring(math.random(1000, 9999))
	unit.Name = `{unitType}_{ownerId}_{uniqueId}`

	-- Set attributes
	unit:SetAttribute("UnitType", unitType)
	unit:SetAttribute("Owner", ownerId)
	unit:SetAttribute("UnitId", unit.Name)

	-- Set health attributes safely
	if unitInfo.health then
		unit:SetAttribute("MaxHealth", unitInfo.health.max_health or 100)
		unit:SetAttribute("CurrentHealth", unitInfo.health.current_health or unitInfo.health.max_health or 100)
	else
		unit:SetAttribute("MaxHealth", 100)
		unit:SetAttribute("CurrentHealth", 100)
	end

	-- Set initial position
	local spawnPos = position or Vector3.new(math.random(-20, 20), 10, math.random(-20, 20))
	unit:SetPrimaryPartCFrame(CFrame.new(spawnPos))

	-- Update humanoid speed if specified
	if unitInfo.movement then
		local humanoid = unit:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.WalkSpeed = unitInfo.movement.speed_meters_per_second * 16 -- Convert m/s to studs/s
		end
	end

	-- Add to workspace
	local unitsFolder = workspace:FindFirstChild("Units")
	if not unitsFolder then
		unitsFolder = Instance.new("Folder")
		unitsFolder.Name = "Units"
		unitsFolder.Parent = workspace
	end
	unit.Parent = unitsFolder

	-- Add to player's units if we found the player
	if success and player then
		PlayerManager.addUnit(player, unit)
	else
		warn(`[UnitManager] Could not find player with UserId {ownerId}`)
	end

	return unit
end

return UnitManager
