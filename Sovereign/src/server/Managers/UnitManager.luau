--!strict
-- UnitManager: Handles unit creation and management

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local ServerStorage = game:GetService("ServerStorage")

local GameData = require(ReplicatedStorage.Shared.GameData)
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)
local UnitManagerDebug = DebugManager.createChannel("UnitManager", false)
local Managers = script.Parent
local CombatManager = require(Managers.CombatManager)
local MoraleManager = require(Managers.MoraleManager)
local FormationManager = require(Managers.FormationManager)
local PlayerManager = require(Managers.PlayerManager)

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

local function getDummyModel(): Model
	-- ... (up to UnitManagerDebug:warn)

	UnitManagerDebug:warn("No Dummy found in ServerStorage, creating simple model")
	local model = Instance.new("Model")
	model.Name = "Dummy"

	-- Make HumanoidRootPart invisible (for BillboardGuis)
	local humanoidRootPart = Instance.new("Part")
	humanoidRootPart.Name = "HumanoidRootPart"
	humanoidRootPart.Size = Vector3.new(2, 4, 2)
	humanoidRootPart.Transparency = 1 -- Set to 1 to be completely invisible
	humanoidRootPart.CanCollide = false
	humanoidRootPart.Material = Enum.Material.SmoothPlastic
	humanoidRootPart.Parent = model

	-- Add basic visible parts (Head and Torso)
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(2, 2, 2)
	head.Color = Color3.fromRGB(255, 204, 153)
	head.CanCollide = true -- IMPORTANT: Visible parts must collide
	head.Material = Enum.Material.Plastic
	head.Shape = Enum.PartType.Block
	head.Parent = model

	local torso = Instance.new("Part")
	torso.Name = "Torso"
	torso.Size = Vector3.new(3, 4, 1.5)
	torso.Color = Color3.fromRGB(100, 100, 100)
	torso.CanCollide = true
	torso.Material = Enum.Material.Plastic
	torso.Parent = model

	local humanoid = Instance.new("Humanoid")
	humanoid.HipHeight = 2.5 -- Standard R15 hip height
	humanoid.Parent = model

	model.PrimaryPart = humanoidRootPart

	-- Position and Weld parts (simplified)
	torso.Position = humanoidRootPart.Position
	head.Position = humanoidRootPart.Position + Vector3.new(0, 3, 0)

	local weldTorso = Instance.new("WeldConstraint")
	weldTorso.Part0 = humanoidRootPart
	weldTorso.Part1 = torso
	weldTorso.Parent = humanoidRootPart

	local weldHead = Instance.new("WeldConstraint")
	weldHead.Part0 = torso
	weldHead.Part1 = head
	weldHead.Parent = torso

	model.Parent = ServerStorage
	return model
end

-- NEW: Ground finding logic (portable version of UnitSpawnManager's logic)
local function findGroundPosition(initialPoint: Vector3): Vector3
	local rayOrigin = initialPoint + Vector3.new(0, 50, 0)
	local rayDirection = Vector3.new(0, -100, 0)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { UnitsFolder }

	local result = Workspace:Raycast(rayOrigin, rayDirection, raycastParams)
	if result and result.Position then
		return result.Position
	else
		return Vector3.new(initialPoint.X, 0.5, initialPoint.Z)
	end
end

function UnitManager.createUnit(unitType: string, ownerId: number, faction: string, position: Vector3?): Model?
	local unitInfo = GameData.Units[unitType]
	if not unitInfo then
		UnitManagerDebug:warn(`Unknown unit type: {unitType}`)
		return nil
	end

	-- ... (existing logic for player lookup, name generation, and cloning)
	local success, player = pcall(function()
		return game.Players:GetPlayerByUserId(ownerId)
	end)

	local dummyModel = getDummyModel()
	if not dummyModel then
		UnitManagerDebug:warn("Failed to get dummy model")
		return nil
	end

	local unit = dummyModel:Clone()

	local uniqueId = tostring(math.random(1000, 9999))
	unit.Name = `{unitType}_{ownerId}_{uniqueId}`

	-- Set attributes (CRITICAL STEP MOVED UP)
	unit:SetAttribute("UnitType", unitType)
	unit:SetAttribute("Owner", ownerId)
	unit:SetAttribute("UnitId", unit.Name)

	-- Initialize components
	if player then
		CombatManager.initializeCombatUnit(unit, player)
	end
	MoraleManager.initializeUnit(unit, faction)

	-- Set health attributes safely
	-- ...

	-- Set initial position on the ground (FIXED)
	local desiredPos = position or Vector3.new(math.random(-20, 20), 10, math.random(-20, 20))
	local groundPos = findGroundPosition(desiredPos)

	local humanoid = unit:FindFirstChildOfClass("Humanoid")
	local hrp = unit:FindFirstChild("HumanoidRootPart")

	if not humanoid or not hrp then
		unit:Destroy()
		return nil
	end

	-- Position the HumanoidRootPart so the unit stands on the ground
	local spawnCFrame = CFrame.new(groundPos) * CFrame.new(0, humanoid.HipHeight + (hrp.Size.Y / 2), 0)

	unit:SetPrimaryPartCFrame(spawnCFrame)

	-- Update humanoid speed if specified
	-- ...

	-- Add to workspace
	local unitsFolder = workspace:FindFirstChild("Units")
	if not unitsFolder then
		unitsFolder = Instance.new("Folder")
		unitsFolder.Name = "Units"
		unitsFolder.Parent = workspace
	end
	unit.Parent = unitsFolder

	-- Add to player's units if we found the player
	-- ...

	return unit
end

return UnitManager
