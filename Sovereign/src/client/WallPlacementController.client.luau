--!strict
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera
local WallPieceDatabase = require(ReplicatedStorage.Shared.WallPieceDatabase)
local KeybindingsManager = require(script.Parent.Camera.KeybindingsManager)

local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local gameEvent = RemoteEvents:WaitForChild("GameEvent")

local WallPlacementController = {}

-- State
local isPlacingWall = false
local ghostWall: Model? = nil
local canPlace = false
local currentBuildingType = "Stone_Wall"
local manualPieceOverride: string? = nil
local verticalOffset = 0
local isAdjustingHeight = false

-- Drag placement state
local isDragging = false
local dragStartGridX: number? = nil
local dragStartGridZ: number? = nil
local dragPath: { { x: number, z: number, pieceType: string? } } = {}
local dragGhosts: { Model } = {}

-- Rotation state
local manualRotation = 0 -- Manual rotation in degrees (0, 90, 180, 270)

-- Current grid position (tracked separately to avoid offset issues with large pieces)
local currentGridX: number = 0
local currentGridZ: number = 0

-- Wall piece cycling (for T key)
local WALL_PIECES = {
	{ name = "Auto (Smart)", pieceType = nil }, -- auto-select based on neighbors
	{ name = "Straight Wall", pieceType = "Straight_Stone_Wall" },
	{ name = "Short Wall", pieceType = "Short_Straight_Stone_Wall" },
	{ name = "Corner Wall", pieceType = "Corner_Stone_Wall" },
	{ name = "Ladder Wall", pieceType = "Ladder_Stone_Wall" },
	{ name = "Small Tower", pieceType = "Small_Tower_Stone_Wall" },
	{ name = "Large Tower", pieceType = "Large_Tower_Stone_Wall" },
	{ name = "Keep", pieceType = "Large_Keep_Stone" },
	{ name = "Gatehouse", pieceType = "Gatehouse_Stone_Wall" },
}

local wallPieceIndex = 1

-- Bindable event to notify HUD/HUD BuildingMenu about current wall piece
local wallPieceEvent = ReplicatedStorage:FindFirstChild("WallPieceChanged")
if not wallPieceEvent then
	wallPieceEvent = Instance.new("BindableEvent")
	wallPieceEvent.Name = "WallPieceChanged"
	wallPieceEvent.Parent = ReplicatedStorage
end

-- Debug (only log once every 2 seconds max)
local lastDebugTime = 0
local function debugLog(message: string, isWarning: boolean?)
	if tick() - lastDebugTime > 2 then
		if isWarning then
			warn(message)
		else
			print(message)
		end
		lastDebugTime = tick()
	end
end

-- Calculate a line of grid positions from start to end (Bresenham's line algorithm)
local function calculateGridLine(x0: number, z0: number, x1: number, z1: number): { { x: number, z: number } }
	local points = {}
	local dx = math.abs(x1 - x0)
	local dz = math.abs(z1 - z0)
	local sx = x0 < x1 and 1 or -1
	local sz = z0 < z1 and 1 or -1
	local err = dx - dz

	local x, z = x0, z0

	while true do
		table.insert(points, { x = x, z = z })

		if x == x1 and z == z1 then
			break
		end

		local e2 = 2 * err
		if e2 > -dz then
			err = err - dz
			x = x + sx
		end
		if e2 < dx then
			err = err + dx
			z = z + sz
		end
	end

	return points
end

-- Calculate drag path with smart spacing for towers
local function calculateDragPath(x0: number, z0: number, x1: number, z1: number, pieceType: string?): { { x: number, z: number, pieceType: string? } }
	local basePath = calculateGridLine(x0, z0, x1, z1)

	-- If no manual override or not a tower type, return the basic path
	if not pieceType or not WallPieceDatabase.isTowerPiece(pieceType) then
		local result = {}
		for _, point in basePath do
			table.insert(result, {
				x = point.x,
				z = point.z,
				pieceType = pieceType, -- Will be nil for auto-mode
			})
		end
		return result
	end

	-- Tower spacing mode: place towers at intervals with straight walls between
	local spacing = WallPieceDatabase.TOWER_SPACING + 1 -- +1 because we want gaps between towers
	local result = {}

	for i, point in basePath do
		if (i - 1) % spacing == 0 then
			-- Place a tower
			table.insert(result, {
				x = point.x,
				z = point.z,
				pieceType = pieceType,
			})
		else
			-- Place a straight wall between towers
			table.insert(result, {
				x = point.x,
				z = point.z,
				pieceType = "Straight_Stone_Wall",
			})
		end
	end

	-- Always end with a tower if we're placing towers
	if #result > 0 and result[#result].pieceType ~= pieceType then
		result[#result].pieceType = pieceType
	end

	return result
end

-- Clear all drag ghost visuals
local function clearDragGhosts()
	for _, ghost in dragGhosts do
		if ghost and ghost.Parent then
			ghost:Destroy()
		end
	end
	dragGhosts = {}
end

-- Helper function to calculate bitmask for a point in the path
local function calculateBitmaskForPoint(gridX: number, gridZ: number, path: { { x: number, z: number, pieceType: string? } }): number
	local bitmask = 0

	-- Check existing walls in the world
	local checkParams = OverlapParams.new()
	checkParams.FilterDescendantsInstances = { ghostWall, player.Character }
	checkParams.FilterType = Enum.RaycastFilterType.Exclude

	for _, dir in WallPieceDatabase.DIRECTIONS do
		local nx = gridX + dir.x
		local nz = gridZ + dir.z

		-- Check if neighbor is in the drag path
		local inPath = false
		for _, pathPoint in path do
			if pathPoint.x == nx and pathPoint.z == nz then
				inPath = true
				break
			end
		end

		if inPath then
			-- Neighbor is part of the path
			bitmask = bit32.bor(bitmask, dir.bit)
		else
			-- Check if neighbor exists in the world
			local neighborPos = WallPieceDatabase.gridToWorld(nx, nz, 0)
			local parts = Workspace:GetPartBoundsInBox(CFrame.new(neighborPos), Vector3.new(10, 10, 10), checkParams)

			for _, part in parts do
				if part.Parent and part.Parent:IsA("Model") then
					local buildingType = part.Parent:GetAttribute("BuildingType")
					if buildingType and string.find(buildingType, "Wall") then
						bitmask = bit32.bor(bitmask, dir.bit)
						break
					end
				end
			end
		end
	end

	return bitmask
end

-- Create ghost visuals for drag path
local function createDragGhosts(path: { { x: number, z: number, pieceType: string? } })
	clearDragGhosts()

	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets then
		return
	end

	local buildings = assets:FindFirstChild("Buildings")
	if not buildings then
		return
	end

	for _, point in path do
		-- Skip if already occupied
		local checkParams = OverlapParams.new()
		checkParams.FilterDescendantsInstances = { ghostWall, player.Character }
		checkParams.FilterType = Enum.RaycastFilterType.Exclude

		local cellCenter = WallPieceDatabase.gridToWorld(point.x, point.z, 0)
		local parts = Workspace:GetPartBoundsInBox(CFrame.new(cellCenter), Vector3.new(10, 20, 10), checkParams)

		local occupied = false
		for _, part in parts do
			local parent = part.Parent
			if parent and parent:IsA("Model") then
				local buildingType = parent:GetAttribute("BuildingType")
				if buildingType and string.find(buildingType, "Wall") then
					occupied = true
					break
				end
			end
		end

		if not occupied then
			local pieceType: string
			local rotation = 0

			-- Check if this point has a specific piece type assigned
			if point.pieceType then
				-- Use the assigned piece type with manual rotation
				pieceType = point.pieceType
				rotation = manualRotation
			else
				-- Calculate bitmask based on neighbors (including other points in path)
				local bitmask = calculateBitmaskForPoint(point.x, point.z, path)
				-- Use auto-selection to determine piece type (smart mode)
				local autoRotation: number
				pieceType, autoRotation = WallPieceDatabase.getPieceFromBitmask(bitmask, nil)
				-- Add manual rotation to auto rotation
				rotation = (autoRotation + manualRotation) % 360
			end

			local template = buildings:FindFirstChild(pieceType)

			if template and template:IsA("Model") then
				local ghost = template:Clone() :: Model

				-- Calculate position with proper height
				local raycastPos = WallPieceDatabase.gridToWorld(point.x, point.z, 0, pieceType)
				local rayStart = Vector3.new(raycastPos.X, 1000, raycastPos.Z)
				local rayDir = Vector3.new(0, -2000, 0)
				local rayParams = RaycastParams.new()
				rayParams.FilterType = Enum.RaycastFilterType.Exclude
				local rayResult = Workspace:Raycast(rayStart, rayDir, rayParams)
				local groundY = rayResult and rayResult.Position.Y or 0

				local boundingCF, boundingSize = ghost:GetBoundingBox()
				local pivotY = ghost:GetPivot().Position.Y
				local boundingBottom = boundingCF.Position.Y - (boundingSize.Y / 2)
				local pivotToBottomOffset = pivotY - boundingBottom
				local targetPivotY = groundY + pivotToBottomOffset + verticalOffset

				-- Get the base world position from the database (which includes the 8x8 offset)
				local worldPos = WallPieceDatabase.gridToWorld(point.x, point.z, targetPivotY, pieceType)

				-- For corner pieces, apply an additional small offset to close the 0.5 unit gap
				if pieceType == "Corner_Stone_Wall" then
					local gapOffset = 0.5
					local offsetX, offsetZ = 0, 0
					if rotation == 0 then -- SE quadrant
						offsetX, offsetZ = -gapOffset, -gapOffset
					elseif rotation == 90 then -- SW quadrant
						offsetX, offsetZ = gapOffset, -gapOffset
					elseif rotation == 180 then -- NW quadrant
						offsetX, offsetZ = gapOffset, gapOffset
					elseif rotation == 270 then -- NE quadrant
						offsetX, offsetZ = -gapOffset, gapOffset
					end
					worldPos = worldPos + Vector3.new(offsetX, 0, offsetZ)
				end

				ghost:PivotTo(CFrame.new(worldPos) * CFrame.Angles(0, math.rad(rotation), 0))

				-- Make it semi-transparent
				for _, descendant in ghost:GetDescendants() do
					if descendant:IsA("BasePart") then
						descendant.Anchored = true
						descendant.CanCollide = false
						descendant.Transparency = 0.7
						descendant.Color = Color3.new(0, 0.8, 1) -- Blue tint for drag preview
					end
				end

				ghost.Parent = Workspace
				table.insert(dragGhosts, ghost)
			end
		end
	end
end

-- Visual ghost update

local function updateGhostPosition()
	if not isPlacingWall then
		return
	end

	if not ghostWall then
		debugLog("[WallPlacement] ERROR: No ghost exists but isPlacingWall=true", true)
		return
	end

	local mouseLocation = UserInputService:GetMouseLocation()
	local mouseRay = camera:ScreenPointToRay(mouseLocation.X, mouseLocation.Y)

	local rayParams = RaycastParams.new()
	rayParams.FilterDescendantsInstances = { ghostWall, player.Character }
	rayParams.FilterType = Enum.RaycastFilterType.Exclude

	local result = Workspace:Raycast(mouseRay.Origin, mouseRay.Direction * 1000, rayParams)
	if not result then
		return
	end

	local rawHitPos = result.Position
	local gridX, gridZ = WallPieceDatabase.worldToGrid(rawHitPos)

	-- If this grid cell is already occupied by a wall, try to move to the
	-- nearest adjacent cell in the direction of the hit point. This makes
	-- it easy to build lines of walls instead of "replacing" the previous one.
	local function isWallAtGrid(x: number, z: number): boolean
		local cellCenter = WallPieceDatabase.gridToWorld(x, z, 0)
		local checkParams = OverlapParams.new()
		checkParams.FilterDescendantsInstances = { ghostWall, player.Character }
		checkParams.FilterType = Enum.RaycastFilterType.Exclude

		local parts = Workspace:GetPartBoundsInBox(CFrame.new(cellCenter), Vector3.new(10, 20, 10), checkParams)
		for _, part in parts do
			local parent = part.Parent
			if parent and parent:IsA("Model") then
				local buildingType = parent:GetAttribute("BuildingType")
				if buildingType and string.find(buildingType, "Wall") then
					return true
				end
			end
		end
		return false
	end

	if isWallAtGrid(gridX, gridZ) then
		-- Decide which neighbor to use based on where the mouse hit is relative
		-- to the center of this occupied grid cell.
		local cellCenter = WallPieceDatabase.gridToWorld(gridX, gridZ, rawHitPos.Y)
		local dx = rawHitPos.X - cellCenter.X
		local dz = rawHitPos.Z - cellCenter.Z

		local primaryHorizontal = math.abs(dx) > math.abs(dz)
		local candidateOffsets
		if primaryHorizontal then
			-- Clicked more to the left/right side of the cell
			if dx >= 0 then
				candidateOffsets = {
					{ x = 1, z = 0 }, -- East
					{ x = 0, z = (dz >= 0 and 1 or -1) }, -- then front/back
				}
			else
				candidateOffsets = {
					{ x = -1, z = 0 }, -- West
					{ x = 0, z = (dz >= 0 and 1 or -1) },
				}
			end
		else
			-- Clicked more to the front/back side of the cell
			if dz >= 0 then
				candidateOffsets = {
					{ x = 0, z = 1 }, -- South
					{ x = (dx >= 0 and 1 or -1), z = 0 },
				}
			else
				candidateOffsets = {
					{ x = 0, z = -1 }, -- North
					{ x = (dx >= 0 and 1 or -1), z = 0 },
				}
			end
		end

		for _, off in candidateOffsets do
			local nx = gridX + off.x
			local nz = gridZ + off.z
			if not isWallAtGrid(nx, nz) then
				gridX, gridZ = nx, nz
				break
			end
		end
	end

	-- Store the current grid position for use in placeWall()
	-- This avoids issues with large pieces where the ghost pivot is offset from the grid center
	currentGridX = gridX
	currentGridZ = gridZ

	-- Calculate where to place the pivot to get the bottom at baseY
	local boundingCF, boundingSize = ghostWall:GetBoundingBox()
	local pivotY = ghostWall:GetPivot().Position.Y
	local boundingBottom = boundingCF.Position.Y - (boundingSize.Y / 2)
	local pivotToBottomOffset = pivotY - boundingBottom

	-- Calculate bitmask for neighbors
	local bitmask = 0
	local checkParams = OverlapParams.new()
	checkParams.FilterDescendantsInstances = { ghostWall, player.Character }
	checkParams.FilterType = Enum.RaycastFilterType.Exclude

	for _, dir in WallPieceDatabase.DIRECTIONS do
		local neighborPos = WallPieceDatabase.gridToWorld(gridX + dir.x, gridZ + dir.z, 0)
		local parts = Workspace:GetPartBoundsInBox(CFrame.new(neighborPos), Vector3.new(10, 10, 10), checkParams)

		for _, part in parts do
			if part.Parent and part.Parent:IsA("Model") then
				local buildingType = part.Parent:GetAttribute("BuildingType")
				if buildingType and string.find(buildingType, "Wall") then
					bitmask = bit32.bor(bitmask, dir.bit)
					break
				end
			end
		end
	end

	local pieceType, autoRotation = WallPieceDatabase.getPieceFromBitmask(bitmask, manualPieceOverride)
	local rotation = (autoRotation + manualRotation) % 360

	-- Get ground level by raycasting down from the grid cell center
	local raycastPos = WallPieceDatabase.gridToWorld(gridX, gridZ, 0, pieceType)
	local groundRayStart = Vector3.new(raycastPos.X, 1000, raycastPos.Z)
	local groundRayDir = Vector3.new(0, -2000, 0)
	local groundRayParams = RaycastParams.new()
	groundRayParams.FilterDescendantsInstances = { ghostWall, player.Character }
	groundRayParams.FilterType = Enum.RaycastFilterType.Exclude
	local groundResult = Workspace:Raycast(groundRayStart, groundRayDir, groundRayParams)
	local baseY = (groundResult and groundResult.Position.Y or rawHitPos.Y) + verticalOffset

	-- Place pivot so that bottom sits at baseY (after pieceType is determined for offset calculation)
	local targetPivotY = baseY + pivotToBottomOffset

	-- Swap ghost if piece type changed
	local currentPieceType = ghostWall:GetAttribute("WallPieceType")
	if currentPieceType ~= pieceType then
		local assets = ReplicatedStorage:FindFirstChild("Assets")
		if assets then
			local buildings = assets:FindFirstChild("Buildings")
			if buildings then
				local template = buildings:FindFirstChild(pieceType)
				if template and template:IsA("Model") then
					ghostWall:Destroy()
					ghostWall = template:Clone() :: Model
					ghostWall:SetAttribute("WallPieceType", pieceType)
					ghostWall.Parent = Workspace

					for _, descendant in ghostWall:GetDescendants() do
						if descendant:IsA("BasePart") then
							descendant.Anchored = true
							descendant.CanCollide = false
							descendant.Transparency = 0.5
							descendant.Color = Color3.new(0, 1, 0)
						end
					end
				end
			end
		end
	end

	-- Position ghost
	if ghostWall then
		-- Get the base world position from the database (which includes the 8x8 offset)
		local worldPos = WallPieceDatabase.gridToWorld(gridX, gridZ, targetPivotY, pieceType)

		-- For corner pieces, apply an additional small offset to close the 0.5 unit gap
		if pieceType == "Corner_Stone_Wall" then
			local gapOffset = 0.5
			local offsetX, offsetZ = 0, 0
			if rotation == 0 then -- SE quadrant
				offsetX, offsetZ = -gapOffset, -gapOffset
			elseif rotation == 90 then -- SW quadrant
				offsetX, offsetZ = gapOffset, -gapOffset
			elseif rotation == 180 then -- NW quadrant
				offsetX, offsetZ = gapOffset, gapOffset
			elseif rotation == 270 then -- NE quadrant
				offsetX, offsetZ = -gapOffset, gapOffset
			end
			worldPos = worldPos + Vector3.new(offsetX, 0, offsetZ)
		end

		ghostWall:PivotTo(CFrame.new(worldPos) * CFrame.Angles(0, math.rad(rotation), 0))

		-- Collision check
		local collisionParams = OverlapParams.new()
		collisionParams.FilterDescendantsInstances = { ghostWall, player.Character }
		collisionParams.FilterType = Enum.RaycastFilterType.Exclude

		local cf, size = ghostWall:GetBoundingBox()
		local collisions = Workspace:GetPartBoundsInBox(cf, size * 0.8, collisionParams)

		canPlace = true
		for _, part in collisions do
			if part.Name ~= "Baseplate" and not part:IsA("Terrain") then
				local parent = part.Parent
				if parent and parent:IsA("Model") then
					local buildingType = parent:GetAttribute("BuildingType")
					if not buildingType or not string.find(buildingType, "Wall") then
						canPlace = false
						break
					end
				else
					canPlace = false
					break
				end
			end
		end

		local color = canPlace and Color3.new(0, 1, 0) or Color3.new(1, 0, 0)
		for _, descendant in ghostWall:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.Color = color
			end
		end

		-- Update drag path if dragging
		if isDragging and dragStartGridX and dragStartGridZ then
			-- BUGFIX: Use the mouse's grid cell, not the ghost's offset pivot cell
			local endGridX, endGridZ = gridX, gridZ

			-- Calculate path from start to current position with smart spacing
			local newPath = calculateDragPath(dragStartGridX, dragStartGridZ, endGridX, endGridZ, manualPieceOverride)

			-- Only update if path changed
			local pathChanged = #newPath ~= #dragPath
			if not pathChanged then
				for i, point in newPath do
					if not dragPath[i] or dragPath[i].x ~= point.x or dragPath[i].z ~= point.z or dragPath[i].pieceType ~= point.pieceType then
						pathChanged = true
						break
					end
				end
			end

			if pathChanged then
				dragPath = newPath
				createDragGhosts(dragPath)
			end
		end
	end
end

function WallPlacementController.startPlacement(buildingType: string)
	if isPlacingWall then
		WallPlacementController.stopPlacement()
	end

	currentBuildingType = buildingType or "Stone_Wall"
	isPlacingWall = true
	verticalOffset = 0
	manualRotation = 0 -- Reset rotation when starting new placement

	-- Check if the buildingType is a specific wall piece type
	local isSpecificWallPiece = WallPieceDatabase.getPieceConfig(buildingType) ~= nil

	if isSpecificWallPiece and buildingType ~= "Stone_Wall" then
		-- User selected a specific wall type from HUD - use that piece
		manualPieceOverride = buildingType
		-- Find the matching index in WALL_PIECES
		for i, piece in ipairs(WALL_PIECES) do
			if piece.pieceType == buildingType then
				wallPieceIndex = i
				break
			end
		end
	else
		-- Default to auto mode for "Stone_Wall" or unrecognized types
		manualPieceOverride = WALL_PIECES[1].pieceType
		wallPieceIndex = 1
	end

	-- Notify HUD of initial wall piece selection
	wallPieceEvent:Fire({
		currentPiece = WALL_PIECES[wallPieceIndex].name,
		isPlacingWalls = true,
	})

	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets then
		warn("[WallPlacement] FAILED: Assets folder not found")
		isPlacingWall = false
		return
	end

	local buildings = assets:FindFirstChild("Buildings")
	if not buildings then
		warn("[WallPlacement] FAILED: Buildings folder not found")
		isPlacingWall = false
		return
	end

	local template = buildings:FindFirstChild("Straight_Stone_Wall")
	if not template or not template:IsA("Model") then
		warn("[WallPlacement] FAILED: Straight_Stone_Wall not found or not a Model")
		isPlacingWall = false
		return
	end

	ghostWall = template:Clone() :: Model
	ghostWall:SetAttribute("WallPieceType", "Straight_Stone_Wall")
	ghostWall.Parent = Workspace

	local partCount = 0
	for _, descendant in ghostWall:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.Transparency = 0.5
			descendant.Color = Color3.new(0, 1, 0)
			partCount += 1
		end
	end

	print(string.format("[WallPlacement] READY: Ghost created with %d parts. Move mouse to position.", partCount))
end

function WallPlacementController.stopPlacement()
	isPlacingWall = false
	manualPieceOverride = nil
	wallPieceIndex = 1

	-- Clean up drag state
	WallPlacementController.clearDragGhosts()
	isDragging = false
	dragStartGridX = nil
	dragStartGridZ = nil
	dragPath = {}

	-- Tell HUD that we're no longer placing walls
	wallPieceEvent:Fire({
		currentPiece = WALL_PIECES[wallPieceIndex].name,
		isPlacingWalls = false,
	})
	if ghostWall then
		ghostWall:Destroy()
		ghostWall = nil
	end
end

function WallPlacementController.placeWall()
	if not isPlacingWall or not ghostWall or not canPlace then
		return
	end

	-- Use the tracked grid coordinates instead of recalculating from the ghost's pivot,
	-- which might be offset for certain piece types (like corners).
	local gridX, gridZ = currentGridX, currentGridZ

	-- DEBUG: Log ghost position before sending to server
	local ghostPivot = ghostWall:GetPivot()
	local pos = ghostPivot.Position
	local pieceType = ghostWall:GetAttribute("WallPieceType")
	print(string.format(
		"[CLIENT GHOST LOG] Type: %s, Grid: (%d, %d), Position: (%.2f, %.2f, %.2f), Rotation: %d",
		pieceType or "Unknown",
		gridX,
		gridZ,
		pos.X,
		pos.Y,
		pos.Z,
		manualRotation
	))

	gameEvent:FireServer("PlaceWall", {
		gridX = gridX,
		gridZ = gridZ,
		buildingType = currentBuildingType,
		manualOverride = manualPieceOverride,
		manualRotation = manualRotation,
	})

	print(string.format("[WallPlacement] PLACED at grid (%d, %d)", gridX, gridZ))
end

-- Public function to clear drag ghosts (exposed for cleanup)
function WallPlacementController.clearDragGhosts()
	clearDragGhosts()
end

-- Place all walls along the drag path
function WallPlacementController.placeDragWalls()
	if #dragPath == 0 then
		-- If not dragging, just place the single ghost
		WallPlacementController.placeWall()
		return
	end

	-- Send all placements to server
	for i, point in ipairs(dragPath) do
		-- DEBUG: Log ghost position before sending to server
		local ghost = dragGhosts[i]
		if ghost then
			local ghostPivot = ghost:GetPivot()
			local pos = ghostPivot.Position
			local pieceType = ghost:GetAttribute("WallPieceType") or point.pieceType
			print(string.format(
				"[CLIENT GHOST LOG] Type: %s, Grid: (%d, %d), Position: (%.2f, %.2f, %.2f), Rotation: %d",
				pieceType or "Unknown",
				point.x,
				point.z,
				pos.X,
				pos.Y,
				pos.Z,
				manualRotation
			))
		end

		gameEvent:FireServer("PlaceWall", {
			gridX = point.x,
			gridZ = point.z,
			buildingType = currentBuildingType,
			manualOverride = point.pieceType, -- Each point has its specific piece type
			manualRotation = manualRotation,
		})
	end

	print(string.format("[WallPlacement] PLACED %d walls along path", #dragPath))
end

-- Input handling
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	-- Track height-adjust key separately so you can hold Shift before or during placement
	if input.KeyCode == KeybindingsManager.GetKeybinding("AdjustPlacementHeight") then
		isAdjustingHeight = true
		debugLog("[WallPlacement] Height adjust enabled", false)
	end

	if not isPlacingWall then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		-- Start drag placement
		if ghostWall then
			isDragging = true
			dragStartGridX = currentGridX
			dragStartGridZ = currentGridZ
			dragPath = { { x = currentGridX, z = currentGridZ, pieceType = manualPieceOverride } }
			createDragGhosts(dragPath) -- Create initial ghost for the drag

			print("[WallPlacement] Drag started at grid (" .. currentGridX .. ", " .. currentGridZ .. ") with piece: " .. tostring(manualPieceOverride or "Auto"))
		end
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 or input.KeyCode == Enum.KeyCode.Escape then
		WallPlacementController.stopPlacement()
	elseif input.KeyCode == KeybindingsManager.GetKeybinding("CyclePlacementType") then
		-- Cycle through wall pieces (T key by default)
		wallPieceIndex = (wallPieceIndex % #WALL_PIECES) + 1
		local piece = WALL_PIECES[wallPieceIndex]
		manualPieceOverride = piece.pieceType

		wallPieceEvent:Fire({
			currentPiece = piece.name,
			isPlacingWalls = true,
		})
		debugLog(string.format("[WallPlacement] Piece cycled to: %s (%s)", piece.name, manualPieceOverride or "auto"))
	elseif input.KeyCode == KeybindingsManager.GetKeybinding("RotatePlacement") then
		-- Rotate wall by 90 degrees (R key by default)
		manualRotation = (manualRotation + 90) % 360
		print(string.format("[WallPlacement] Wall rotated to %d°", manualRotation))
	end
end)

UserInputService.InputEnded:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	if input.KeyCode == KeybindingsManager.GetKeybinding("AdjustPlacementHeight") then
		isAdjustingHeight = false
		debugLog("[WallPlacement] Height adjust disabled", false)
	end

	-- End drag placement when mouse button is released
	if input.UserInputType == Enum.UserInputType.MouseButton1 and isDragging then
		isDragging = false

		-- Place all walls along the path
		WallPlacementController.placeDragWalls()

		-- Clear drag visuals
		WallPlacementController.clearDragGhosts()
		dragPath = {}
		dragStartGridX = nil
		dragStartGridZ = nil

		print("[WallPlacement] Drag ended")
	end
end)

-- Mouse wheel adjusts vertical offset while Shift (AdjustPlacementHeight) is held
UserInputService.InputChanged:Connect(function(input, gameProcessed)
	if gameProcessed or not isPlacingWall then
		return
	end

	if not isAdjustingHeight then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseWheel then
		-- Delta > 0 = scroll up, Delta < 0 = scroll down
		local step = 0.5
		verticalOffset += input.Position.Z * step
		-- Clamp to a reasonable range so walls don't fly away
		if verticalOffset > 10 then
			verticalOffset = 10
		elseif verticalOffset < -10 then
			verticalOffset = -10
		end

		debugLog(string.format("[WallPlacement] Vertical offset: %.2f", verticalOffset), false)
	end
end)

-- Update loop
RunService.RenderStepped:Connect(function()
	if isPlacingWall then
		updateGhostPosition()
	end
end)

-- Listen for server events
gameEvent.OnClientEvent:Connect(function(action, data)
	if action == "StartPlacement" then
		if data and (data == "Stone_Wall" or string.find(tostring(data), "Wall")) then
			print("[WallPlacement] START:", data)
			WallPlacementController.startPlacement(data)
		end
	elseif action == "PlacementEnded" then
		WallPlacementController.stopPlacement()
	end
end)

return WallPlacementController
