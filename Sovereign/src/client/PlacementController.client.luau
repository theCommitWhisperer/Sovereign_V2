--!strict
-- PlacementController: Handles building placement preview and validation

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local DebugManager = require(ReplicatedStorage.Shared.DebugManager)
local PlacementDebug = DebugManager.createChannel("Placement", false)

-- Wait for RemoteEvents
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local gameEvent = RemoteEvents:WaitForChild("GameEvent")

-- State
local isPlacing = false
local currentBuildingName = nil
local ghostBuilding = nil
local canPlace = false

-- Load building data
local GameData = require(ReplicatedStorage.Shared.GameData)

-- Clean up ghost building
local function cleanup()
	if ghostBuilding then
		ghostBuilding:Destroy()
		ghostBuilding = nil
	end
	isPlacing = false
	currentBuildingName = nil
end

-- Start placement mode
local function startPlacement(buildingName: string)
	cleanup() -- Clean up any existing ghost

	local buildingInfo = GameData.Buildings[buildingName]
	if not buildingInfo then
		PlacementDebug:warn("Unknown building:", { buildingName = buildingName })
		return
	end

	PlacementDebug:info("Starting placement for:", buildingName)

	isPlacing = true
	currentBuildingName = buildingName

	-- Create ghost building
	ghostBuilding = Instance.new("Part")
	ghostBuilding.Name = "GhostBuilding"
	ghostBuilding.Size = buildingInfo.size
	ghostBuilding.Anchored = true
	ghostBuilding.CanCollide = false
	ghostBuilding.Transparency = 0.5
	ghostBuilding.Material = Enum.Material.SmoothPlastic
	ghostBuilding.Parent = Workspace
end

-- Update ghost position
local function updateGhostPosition()
	if not (isPlacing and ghostBuilding) then
		return
	end

	-- Raycast from mouse to find placement position
	local mouseLocation = UserInputService:GetMouseLocation()
	local mouseRay = camera:ScreenPointToRay(mouseLocation.X, mouseLocation.Y)

	local raycastParams = RaycastParams.new()
	raycastParams.FilterDescendantsInstances = { ghostBuilding, player.Character }
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude

	local result = Workspace:Raycast(mouseRay.Origin, mouseRay.Direction * 1000, raycastParams)

	if result then
		-- Snap to grid
		local gridSize = 4
		local pos = result.Position
		local snappedPos = Vector3.new(
			math.floor(pos.X / gridSize + 0.5) * gridSize,
			pos.Y + (ghostBuilding.Size.Y / 2),
			math.floor(pos.Z / gridSize + 0.5) * gridSize
		)

		ghostBuilding.Position = snappedPos

		-- Simple validation - check if overlapping with other parts
		local overlapParams = OverlapParams.new()
		overlapParams.FilterDescendantsInstances = { ghostBuilding }
		overlapParams.FilterType = Enum.RaycastFilterType.Exclude

		local overlappingParts = Workspace:GetPartBoundsInBox(ghostBuilding.CFrame, ghostBuilding.Size, overlapParams)

		-- Filter out baseplate and terrain
		local hasCollision = false
		for _, part in overlappingParts do
			if part.Name ~= "Baseplate" and not part:IsA("Terrain") then
				hasCollision = true
				break
			end
		end

		canPlace = not hasCollision
		ghostBuilding.Color = canPlace and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(255, 0, 0)
	end
end

-- Handle input
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or not isPlacing then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		-- Left click - place building
		if canPlace and ghostBuilding then
			PlacementDebug:info("Placing building at:", ghostBuilding.Position)

			-- Send to server
			gameEvent:FireServer("PlaceBuilding", {
				buildingName = currentBuildingName,
				position = ghostBuilding.Position,
				cframe = ghostBuilding.CFrame,
			})

			cleanup()
		end
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 or input.KeyCode == Enum.KeyCode.Escape then
		-- Right click or ESC - cancel
		PlacementDebug:info("Placement cancelled")
		cleanup()
	end
end)

-- Listen for server requests to start placement
gameEvent.OnClientEvent:Connect(function(action, data)
	if action == "StartPlacement" and typeof(data) == "string" then
		startPlacement(data)
	end
end)

-- Update ghost every frame
RunService.RenderStepped:Connect(function()
	if isPlacing then
		updateGhostPosition()
	end
end)

PlacementDebug:info("Initialized")
