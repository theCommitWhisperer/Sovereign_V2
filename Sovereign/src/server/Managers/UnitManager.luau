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

-- Try to find a dummy model, create a simple one if not found
local function getDummyModel(): Model
	local dummy = ServerStorage:FindFirstChild("Dummy")
	if dummy and dummy:IsA("Model") then
		return dummy
	end

	-- Create a simple dummy if none exists
	warn("[UnitManager] No Dummy found in ServerStorage, creating simple model")
	local model = Instance.new("Model")
	model.Name = "Dummy"

	local humanoidRootPart = Instance.new("Part")
	humanoidRootPart.Name = "HumanoidRootPart"
	humanoidRootPart.Size = Vector3.new(2, 2, 1)
	humanoidRootPart.Transparency = 1
	humanoidRootPart.CanCollide = false
	humanoidRootPart.Parent = model

	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(2, 1, 1)
	head.Color = Color3.fromRGB(255, 204, 153) -- Skin tone
	head.Parent = model

	local humanoid = Instance.new("Humanoid")
	humanoid.Parent = model

	model.PrimaryPart = humanoidRootPart

	-- Position head above HRP
	head.Position = humanoidRootPart.Position + Vector3.new(0, 1.5, 0)

	-- Weld head to HRP
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = humanoidRootPart
	weld.Part1 = head
	weld.Parent = humanoidRootPart

	model.Parent = ServerStorage
	return model
end

function UnitManager.createUnit(unitName: string, player: Player, spawnPosition: Vector3): Model?
	local unitInfo = GameData.Units[unitName]
	if not unitInfo then
		warn(`[UnitManager] Unknown unit: {unitName}`)
		return nil
	end

	print(`[UnitManager] Creating {unitName} for {player.Name}`)

	-- Clone the dummy model
	local dummyModel = getDummyModel()
	local unit = dummyModel:Clone()
	unit.Name = `{unitName}_{player.UserId}_{math.random(1000, 9999)}`

	-- Set up humanoid
	local humanoid = unit:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.MaxHealth = unitInfo.hit_points
		humanoid.Health = unitInfo.hit_points
		humanoid.WalkSpeed = unitInfo.movement.speed_meters_per_second * 16 -- Convert to studs/s
	end

	-- Add ownership attributes
	unit:SetAttribute("Owner", player.UserId)
	unit:SetAttribute("UnitType", unitName)

	-- Color code units
	if unitName == "King" then
		for _, part in unit:GetDescendants() do
			if part:IsA("BasePart") and part.Name == "Head" then
				part.Color = Color3.fromRGB(255, 215, 0) -- Gold
			end
		end
	else
		for _, part in unit:GetDescendants() do
			if part:IsA("BasePart") and part.Name == "Head" then
				part.Color = Color3.fromRGB(101, 67, 33) -- Brown for peasants
			end
		end
	end

	-- Position the unit
	if unit.PrimaryPart then
		unit:SetPrimaryPartCFrame(CFrame.new(spawnPosition + Vector3.new(0, 3, 0)))
	end

	unit.Parent = UnitsFolder

	-- Track in player data
	PlayerManager.addUnit(player, unit)

	return unit
end

return UnitManager
