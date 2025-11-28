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
local currentRotation = 0 -- Current rotation in degrees (0, 90, 180, 270)
local isWallBuilding = false -- Track if current building is a wall
local continuousPlacement = false -- Allow continuous wall placement

-- Load building data
local GameData = require(ReplicatedStorage.Shared.GameData)

-- Nearby wall highlighting
local highlightedWalls: { Part } = {}
local highlightColor = Color3.fromRGB(255, 255, 100) -- Yellow highlight

-- Helper: Check if building is a wall
local function isWall(buildingName: string): boolean
	local buildingInfo = GameData.Buildings[buildingName]
	return buildingInfo and buildingInfo.type == "Wall"
end

-- Clean up highlighted walls
local function clearHighlights()
	for _, wall in highlightedWalls do
		if wall and wall.Parent then
			wall.Color = Color3.fromRGB(139, 69, 19) -- Reset to default brown
		end
	end
	table.clear(highlightedWalls)
end

-- Clean up ghost building
local function cleanup()
	if ghostBuilding then
		ghostBuilding:Destroy()
		ghostBuilding = nil
	end
	clearHighlights()
	isPlacing = false
	currentBuildingName = nil
	currentRotation = 0
	isWallBuilding = false
	continuousPlacement = false
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
	currentRotation = 0
	isWallBuilding = isWall(buildingName)
	continuousPlacement = isWallBuilding -- Enable continuous placement for walls

	-- Try to load actual model for ghost if available
	if buildingInfo.model_asset_name then
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
				ghostBuilding = modelAsset:Clone()
				ghostBuilding.Name = "GhostBuilding"

				-- Make model semi-transparent for ghost effect
				for _, descendant in ghostBuilding:GetDescendants() do
					if descendant:IsA("BasePart") then
						descendant.Transparency = 0.5
						descendant.CanCollide = false
					end
				end

				PlacementDebug:info(`Loaded ghost model: {buildingInfo.model_asset_name}`)
			end
		end
	end

	-- Fallback: Create a simple part if no model loaded
	if not ghostBuilding then
		ghostBuilding = Instance.new("Part")
		ghostBuilding.Name = "GhostBuilding"
		ghostBuilding.Size = buildingInfo.size
		ghostBuilding.Anchored = true
		ghostBuilding.CanCollide = false
		ghostBuilding.Transparency = 0.5
		ghostBuilding.Material = Enum.Material.SmoothPlastic
	end

	ghostBuilding.Parent = Workspace

	PlacementDebug:info(`Wall building: {isWallBuilding}, Continuous: {continuousPlacement}`)
end

-- Highlight nearby walls
local function highlightNearbyWalls(position: Vector3)
	clearHighlights()

	if not isWallBuilding then
		return
	end

	-- Find nearby walls
	local buildingsFolder = Workspace:FindFirstChild("Buildings")
	if not buildingsFolder then
		return
	end

	local HIGHLIGHT_RANGE = 12 -- Highlight walls within 12 studs

	for _, building in buildingsFolder:GetChildren() do
		if building:IsA("BasePart") then
			local buildingType = building:GetAttribute("BuildingType")
			local owner = building:GetAttribute("Owner")

			-- Check if it's a wall owned by the same player
			if
				buildingType
				and isWall(buildingType)
				and owner == player.UserId
				and (building.Position - position).Magnitude <= HIGHLIGHT_RANGE
			then
				building.Color = highlightColor
				table.insert(highlightedWalls, building)
			end
		end
	end
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
		-- Snap to grid (use larger grid for walls)
		local gridSize = isWallBuilding and 8 or 4
		local pos = result.Position

		-- Snap X and Z to grid
		local gridX = math.floor(pos.X / gridSize + 0.5) * gridSize
		local gridZ = math.floor(pos.Z / gridSize + 0.5) * gridSize

		-- Raycast down from above the grid position to find terrain height
		local rayOrigin = Vector3.new(gridX, 200, gridZ) -- Start high above
		local rayDirection = Vector3.new(0, -300, 0) -- Cast downward

		local terrainParams = RaycastParams.new()
		terrainParams.FilterDescendantsInstances = { ghostBuilding, player.Character }
		terrainParams.FilterType = Enum.RaycastFilterType.Exclude
		terrainParams.IgnoreWater = true

		local terrainResult = Workspace:Raycast(rayOrigin, rayDirection, terrainParams)

		-- Default to terrain voxel height if no raycast hit
		local groundY = pos.Y

		if terrainResult then
			-- Check if we hit the baseplate - if so, use terrain instead
			if terrainResult.Instance.Name == "Baseplate" then
				-- Sample terrain voxel at this position
				local terrain = Workspace.Terrain
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
			else
				groundY = terrainResult.Position.Y
			end
		end

		-- Apply rotation
		local yRotation = CFrame.Angles(0, math.rad(currentRotation), 0)
		local finalPosition: Vector3

		if ghostBuilding:IsA("Model") then
			-- For models, calculate proper positioning
			local uprightRotation = CFrame.Angles(math.rad(-90), 0, 0)

			-- First position at origin to measure
			ghostBuilding:PivotTo(CFrame.new(0, 0, 0) * uprightRotation)

			-- Get model's size after rotation
			local _, modelSize = ghostBuilding:GetBoundingBox()
			local modelBottomOffset = modelSize.Y / 2

			-- Position with bottom on ground
			local finalY = groundY + modelBottomOffset
			finalPosition = Vector3.new(gridX, finalY, gridZ)
			ghostBuilding:PivotTo(CFrame.new(finalPosition) * yRotation * uprightRotation)
		else
			-- For parts, calculate Y offset
			local yOffset = ghostBuilding.Size.Y / 2
			finalPosition = Vector3.new(gridX, groundY + yOffset, gridZ)
			ghostBuilding.CFrame = CFrame.new(finalPosition) * yRotation
		end

		-- Highlight nearby walls if placing a wall
		highlightNearbyWalls(finalPosition)

		-- Validation - check if overlapping with other parts
		local overlapParams = OverlapParams.new()
		overlapParams.FilterDescendantsInstances = { ghostBuilding }
		overlapParams.FilterType = Enum.RaycastFilterType.Exclude

		-- Get bounding box for collision check
		local checkCFrame, checkSize
		if ghostBuilding:IsA("Model") then
			checkCFrame = ghostBuilding:GetBoundingBox()
			checkSize = ghostBuilding:GetExtentsSize()
		else
			checkCFrame = ghostBuilding.CFrame
			checkSize = ghostBuilding.Size
		end

		local overlappingParts = Workspace:GetPartBoundsInBox(checkCFrame, checkSize, overlapParams)

		-- Filter out baseplate and terrain
		local hasCollision = false
		for _, part in overlappingParts do
			if part.Name ~= "Baseplate" and not part:IsA("Terrain") then
				hasCollision = true
				break
			end
		end

		canPlace = not hasCollision

		-- Color feedback (handle both Model and Part)
		local ghostColor = canPlace and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(255, 0, 0)
		if ghostBuilding:IsA("Model") then
			for _, descendant in ghostBuilding:GetDescendants() do
				if descendant:IsA("BasePart") then
					descendant.Color = ghostColor
				end
			end
		else
			ghostBuilding.Color = ghostColor
		end
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
			-- Get position and CFrame (handle both Model and Part)
			local buildingPos, buildingCFrame
			if ghostBuilding:IsA("Model") then
				buildingCFrame = ghostBuilding:GetPivot()
				buildingPos = buildingCFrame.Position
			else
				buildingCFrame = ghostBuilding.CFrame
				buildingPos = ghostBuilding.Position
			end

			PlacementDebug:info("Placing building at:", buildingPos)

			-- Send to server
			gameEvent:FireServer("PlaceBuilding", {
				buildingName = currentBuildingName,
				position = buildingPos,
				cframe = buildingCFrame,
			})

			-- If continuous placement is enabled (for walls), keep placing
			if continuousPlacement then
				PlacementDebug:info("Continuous placement enabled - ready for next wall")
				-- Don't cleanup, keep the ghost active
			else
				cleanup()
			end
		end
	elseif input.KeyCode == Enum.KeyCode.R then
		-- R key - rotate building
		currentRotation = (currentRotation + 90) % 360
		PlacementDebug:info(`Rotated to {currentRotation} degrees`)
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
