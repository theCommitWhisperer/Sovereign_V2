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
local PlacementDebug = DebugManager.createChannel("Placement", true)

-- [ADD] At the top with other requires
local WallSystemVals = {
	Grid = 8,
	Dist = 8.1, -- Slightly larger than grid to catch neighbors
}
-- Bitmask directions (Same as server)
local DIRECTIONS = {
	{ x = 0, z = -1, bit = 1 }, -- North
	{ x = 1, z = 0, bit = 2 }, -- East
	{ x = 0, z = 1, bit = 4 }, -- South
	{ x = -1, z = 0, bit = 8 }, -- West
}

-- [ADD] Helper to get wall model name based on bitmask (Must match server logic)
-- NOTE: Assuming "Wall Segment" asset is VERTICAL (N-S) at 0 rotation.
local function getWallAssetName(bitmask)
	if bitmask == 15 then
		return "Tower", 0
	end
	if bitmask == 7 then
		return "Tower", 0
	end
	if bitmask == 11 then
		return "Tower", 180
	end
	if bitmask == 13 then
		return "Tower", 90
	end
	if bitmask == 14 then
		return "Tower", 270
	end
	if bitmask == 3 then
		return "Wall Corner", 0
	end
	if bitmask == 6 then
		return "Wall Corner", 270
	end
	if bitmask == 9 then
		return "Wall Corner", 90
	end
	if bitmask == 12 then
		return "Wall Corner", 180
	end
	if bitmask == 1 or bitmask == 4 or bitmask == 5 then
		return "Wall Segment", 90 -- Vertical (N-S connection)
	end
	return "Wall Segment", 0 -- Horizontal (E-W connection or default)
end

-- Wait for RemoteEvents
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local gameEvent = RemoteEvents:WaitForChild("GameEvent")

-- State
local isPlacing = false
local currentBuildingName = nil
local ghostBuilding = nil
local canPlace = false
local manualRotation = 0 -- Manual rotation offset in degrees (for R key)
local wallPieceIndex = 1 -- Which wall piece to show (1=straight, 2=corner, 3=3way, 4=4way)
local pivotIndex = 1 -- 1=center, 2=right, 3=left
local PIVOT_MODES = { 0, 1, -1 } -- Center, Right, Left (corresponds to half-length multiplier)

-- Wall piece cycle for manual selection
local WALL_PIECES = {
	{ name = "Wall Segment", rotation = 0 },
	{ name = "Wall Corner", rotation = 0 },
	{ name = "Wall Corner Reverse", rotation = 0 },
	{ name = "Tower", rotation = 0 },
	{ name = "Gatehouse", rotation = 0 },
	{ name = "Ladder Wall Segment", rotation = 0 },
}

-- Load building data
local GameData = require(ReplicatedStorage.Shared.GameData)
local KeybindingsManager = require(script.Parent.Camera.KeybindingsManager)

-- Clean up ghost building
local function cleanup()
	if ghostBuilding then
		ghostBuilding:Destroy()
		ghostBuilding = nil
	end
	isPlacing = false
	currentBuildingName = nil
	manualRotation = 0 -- Reset rotation
	wallPieceIndex = 1 -- Reset wall piece selection
	pivotIndex = 1 -- Reset pivot to center
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
	local buildingTemplate
	if buildingName == "Stone_Wall" then
		local assets = ReplicatedStorage:WaitForChild("Assets")
		if assets then
			local buildings = assets:WaitForChild("Buildings")
			if buildings then
				buildingTemplate = buildings:FindFirstChild("Wall Segment")
			end
		end
	end

	if buildingTemplate then
		ghostBuilding = buildingTemplate:Clone()
		ghostBuilding.Name = "Wall Segment"
		for _, v in ghostBuilding:GetDescendants() do
			if v:IsA("BasePart") then
				v.Anchored = true
				v.CanCollide = false
				v.Transparency = 0.5
				v.Color = Color3.new(0, 1, 0)
			end
		end
	else
		ghostBuilding = Instance.new("Part")
		ghostBuilding.Name = "GhostBuilding"
		ghostBuilding.Size = buildingInfo.size
		ghostBuilding.Anchored = true
		ghostBuilding.CanCollide = false
		ghostBuilding.Transparency = 0.5
		ghostBuilding.Material = Enum.Material.SmoothPlastic
	end

	ghostBuilding.Parent = Workspace
end

local function updateGhostPosition()
	if not (isPlacing and ghostBuilding) then
		return
	end

	-- Raycast from mouse to find placement position
	local mouseLocation = UserInputService:GetMouseLocation()
	local mouseRay = camera:ScreenPointToRay(mouseLocation.X, mouseLocation.Y)

	local ignoreList = { ghostBuilding, player.Character }
	local baseplate = Workspace:FindFirstChild("Baseplate")
	if baseplate then
		table.insert(ignoreList, baseplate)
	end

	local raycastParams = RaycastParams.new()
	raycastParams.FilterDescendantsInstances = ignoreList
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude

	local result = Workspace:Raycast(mouseRay.Origin, mouseRay.Direction * 1000, raycastParams)

	if result then
		-- Snap to grid
		local gridSize = currentBuildingName == "Stone_Wall" and 8 or 4
		local pos = result.Position

		local snappedX = math.floor(pos.X / gridSize + 0.5) * gridSize
		local snappedZ = math.floor(pos.Z / gridSize + 0.5) * gridSize

		-- New raycast to find ground height accurately
		local groundRaycastStart = Vector3.new(snappedX, 1000, snappedZ)
		local groundRaycastDir = Vector3.new(0, -2000, 0)

		-- For this raycast, we need to ignore all existing buildings to find the terrain.
		local groundRaycastParams = RaycastParams.new()
		local groundIgnoreList = { player.Character, ghostBuilding }
		local buildingsFolder = Workspace:FindFirstChild("Buildings")
		if buildingsFolder then
			for _, b in ipairs(buildingsFolder:GetChildren()) do
				table.insert(groundIgnoreList, b)
			end
		end
		groundRaycastParams.FilterDescendantsInstances = groundIgnoreList
		groundRaycastParams.FilterType = Enum.RaycastFilterType.Exclude

		local groundResult = Workspace:Raycast(groundRaycastStart, groundRaycastDir, groundRaycastParams)

		local groundY = pos.Y -- fallback to original
		if groundResult then
			groundY = groundResult.Position.Y
		end

		local distance_from_pivot_to_floor = 0
		if ghostBuilding:IsA("Model") then
			local lowestY = 0
			for _, descendant in ipairs(ghostBuilding:GetDescendants()) do
				if descendant:IsA("BasePart") then
					local part_cframe_relative_to_pivot = ghostBuilding:GetPivot():ToObjectSpace(descendant.CFrame)
					local part_size = descendant.Size
					for i = 0, 7 do
						local x = (bit32.band(i, 1) == 0) and -part_size.X / 2 or part_size.X / 2
						local y = (bit32.band(i, 2) == 0) and -part_size.Y / 2 or part_size.Y / 2
						local z = (bit32.band(i, 4) == 0) and -part_size.Z / 2 or part_size.Z / 2
						local corner_in_part_space = Vector3.new(x, y, z)
						local corner_in_model_space = part_cframe_relative_to_pivot * corner_in_part_space
						if corner_in_model_space.Y < lowestY then
							lowestY = corner_in_model_space.Y
						end
					end
				end
			end
			distance_from_pivot_to_floor = -lowestY
		else
			distance_from_pivot_to_floor = ghostBuilding.Size.Y / 2
		end

		local snappedPos = Vector3.new(snappedX, groundY + distance_from_pivot_to_floor, snappedZ)

		-- [NEW] Wall Smart Preview Logic
		if currentBuildingName == "Stone_Wall" then
			local bitmask = 0
			local params = OverlapParams.new()
			params.FilterDescendantsInstances = { ghostBuilding, player.Character }
			params.FilterType = Enum.RaycastFilterType.Exclude

			-- Check 4 directions for neighbors
			for _, dir in ipairs(DIRECTIONS) do
				local checkPos = snappedPos + Vector3.new(dir.x * WallSystemVals.Grid, 0, dir.z * WallSystemVals.Grid)

				-- Check for existing walls at neighbor coordinates
				local checkSize = Vector3.new(4, 20, 4) -- Use a larger box to find neighbors
				local checkCenter = checkPos + Vector3.new(0, checkSize.Y / 2, 0) -- Center the box above the ground
				PlacementDebug:info("Checking for neighbor at", { center = checkCenter, size = checkSize })
				local parts = Workspace:GetPartBoundsInBox(CFrame.new(checkCenter), checkSize, params)
				PlacementDebug:info("Found parts:", #parts)

				for i, p in ipairs(parts) do
					local parentName = p.Parent and p.Parent.Name or "nil"
					local buildingType = p.Parent and p.Parent:GetAttribute("BuildingType") or "nil"
					PlacementDebug:info("Part " .. i, { name = p.Name, parent = parentName, type = buildingType })
					-- Check if it's a wall
					if p.Parent and p.Parent:GetAttribute("BuildingType") == "Stone_Wall" then
						bitmask = bitmask + dir.bit
						PlacementDebug:info("Found neighbor wall, bitmask is now", bitmask)
						break
					end
				end
			end
			PlacementDebug:info("Final bitmask", bitmask)

			-- Use manually selected piece if user pressed R, otherwise auto-select
			local assetName, rotation
			if wallPieceIndex > 1 then
				-- Manual piece selection via R key
				assetName = WALL_PIECES[wallPieceIndex].name
				rotation = WALL_PIECES[wallPieceIndex].rotation
				PlacementDebug:info("Using manual wall piece", { asset = assetName, index = wallPieceIndex })
			else
				-- Automatic piece selection based on neighbors
				assetName, rotation = getWallAssetName(bitmask)
				PlacementDebug:info("Auto-selected wall piece", { asset = assetName, rot = rotation })
			end

			-- Swap Ghost Mesh if needed
			if ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Buildings") then
				local assets = ReplicatedStorage.Assets.Buildings
				local template = assets:FindFirstChild(assetName)

				if template and ghostBuilding.Name ~= assetName then
					ghostBuilding:Destroy()
					ghostBuilding = template:Clone()
					ghostBuilding.Name = assetName
					ghostBuilding.Parent = Workspace
					-- Re-apply ghost visual properties
					for _, v in ghostBuilding:GetDescendants() do
						if v:IsA("BasePart") then
							v.Transparency = 0.5
							v.CanCollide = false
							v.Color = Color3.new(0, 1, 0)
						end
					end
				end
			end

			-- Calculate final position with pivot offset
			local finalPosition = snappedPos
			local pivotMode = PIVOT_MODES[pivotIndex]
			-- Only apply pivot offset to the basic straight wall piece
			if wallPieceIndex == 1 and pivotMode ~= 0 then
				local wallLength = 8
				local halfLength = wallLength / 2
				local offsetVector = Vector3.new(halfLength * pivotMode, 0, 0)

				-- Rotate the offset vector by the current manual rotation
				local rotatedOffset = CFrame.Angles(0, math.rad(manualRotation), 0):VectorToWorldSpace(offsetVector)

				finalPosition = snappedPos - rotatedOffset
				PlacementDebug:info("Applying pivot offset", { offset = rotatedOffset })
			end

			-- Apply Position and Rotation
			local finalRotation = rotation + manualRotation
			ghostBuilding:PivotTo(CFrame.new(finalPosition) * CFrame.Angles(0, math.rad(finalRotation), 0))
		else
			-- Standard non-wall behavior (apply manual rotation)
			if ghostBuilding:IsA("Model") then
				ghostBuilding:PivotTo(CFrame.new(snappedPos) * CFrame.Angles(0, math.rad(manualRotation), 0))
			else
				ghostBuilding.CFrame = CFrame.new(snappedPos) * CFrame.Angles(0, math.rad(manualRotation), 0)
			end
		end

		-- Simple validation - check if overlapping with other parts
		local overlapParams = OverlapParams.new()
		overlapParams.FilterDescendantsInstances = { ghostBuilding }
		overlapParams.FilterType = Enum.RaycastFilterType.Exclude

		local boundsCFrame = ghostBuilding:IsA("Model")
				and ghostBuilding.PrimaryPart
				and ghostBuilding.PrimaryPart.CFrame
			or ghostBuilding.CFrame
		local boundsSize = ghostBuilding:IsA("Model") and ghostBuilding.PrimaryPart and ghostBuilding.PrimaryPart.Size
			or ghostBuilding.Size
		local overlappingParts = Workspace:GetPartBoundsInBox(boundsCFrame, boundsSize, overlapParams)

		-- Check collisions
		local hasCollision = false
		if currentBuildingName == "Stone_Wall" then
			local ghostGridX = math.floor(snappedPos.X / 8 + 0.5)
			local ghostGridZ = math.floor(snappedPos.Z / 8 + 0.5)

			for _, part in ipairs(overlappingParts) do
				local parent = part.Parent
				if parent and parent:GetAttribute("BuildingType") == "Stone_Wall" then
					-- It's a wall. Check if it's on the same grid cell.
					local wallPos = parent:GetPivot().Position
					local wallGridX = math.floor(wallPos.X / 8 + 0.5)
					local wallGridZ = math.floor(wallPos.Z / 8 + 0.5)

					if wallGridX == ghostGridX and wallGridZ == ghostGridZ then
						-- Overlapping with a wall on the same cell. This is not allowed.
						hasCollision = true
						break
					end
					-- If it's on a different cell, it's a neighbor, so we ignore the collision and continue to the next part.
				elseif part.Name ~= "Baseplate" and not part:IsA("Terrain") then
					-- It's not a wall and not the ground. This is a collision.
					hasCollision = true
					break
				end
			end
		else
			-- Standard non-wall buildings use standard collision
			for _, part in ipairs(overlappingParts) do
				if part.Name ~= "Baseplate" and not part:IsA("Terrain") then
					hasCollision = true
					break
				end
			end
		end

		canPlace = not hasCollision

		local color = canPlace and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(255, 0, 0)
		if ghostBuilding:IsA("BasePart") then
			ghostBuilding.Color = color
		else
			for _, v in ghostBuilding:GetDescendants() do
				if v:IsA("BasePart") then
					v.Color = color
				end
			end
		end
	end
end

-- Handle input
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if not isPlacing then
		return
	end

	-- Check for customizable actions first, allow even if game processed
	if input.KeyCode == KeybindingsManager.GetKeybinding("RotatePlacement") then
		manualRotation = (manualRotation + 90) % 360
		PlacementDebug:info("Rotated building", { rotation = manualRotation })
		return
	end

	if input.KeyCode == KeybindingsManager.GetKeybinding("CyclePlacementType") then
		if currentBuildingName == "Stone_Wall" then
			-- Cycle through wall piece types
			wallPieceIndex = (wallPieceIndex % #WALL_PIECES) + 1
			PlacementDebug:info(
				"Changed wall piece",
				{ index = wallPieceIndex, piece = WALL_PIECES[wallPieceIndex].name }
			)
		end
		return
	end

	if input.KeyCode == KeybindingsManager.GetKeybinding("CyclePivot") then
		pivotIndex = (pivotIndex % #PIVOT_MODES) + 1
		local pivotName = "Center"
		if pivotIndex == 2 then
			pivotName = "Right"
		end
		if pivotIndex == 3 then
			pivotName = "Left"
		end
		PlacementDebug:info("Changed pivot mode", { pivot = pivotName })
		return
	end

	if gameProcessed then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		-- Left click - place building
		if canPlace and ghostBuilding then
			local pivot = ghostBuilding:GetPivot()
			PlacementDebug:info("Placing building at:", pivot.Position)

			-- Send to server (include manual piece selection for walls)
			local placementData = {
				buildingName = currentBuildingName,
				position = pivot.Position,
				cframe = pivot,
				manualRotation = manualRotation, -- Send manual rotation offset
			}

			-- For walls, send the selected piece type
			if currentBuildingName == "Stone_Wall" and wallPieceIndex > 1 then
				placementData.wallPieceType = WALL_PIECES[wallPieceIndex].name
			end

			gameEvent:FireServer("PlaceBuilding", placementData)

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
