--!strict
--[[
	WallGridManager - Core wall system management (Server-side)

	Features:
	- Grid-based wall storage and management
	- Automatic wall piece selection using bitmasking
	- Neighbor detection and connectivity
	- Wall network tracking
	- Optimized for mobile performance

	Usage:
		WallGridManager.initialize()
		WallGridManager.placeWall(gridX, gridZ, ownerId, wallType)
		WallGridManager.removeWall(gridX, gridZ)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local WallPieceDatabase = require(ReplicatedStorage.Shared.WallPieceDatabase)

local WallGridManager = {}

-- Grid storage: [gridX][gridZ] = WallData
type WallData = {
	instance: Model,
	gridX: number,
	gridZ: number,
	pieceType: string,
	rotation: number,
	ownerId: number,
	manualOverride: string?, -- If player manually selected a piece type
	manualRotation: number?, -- If player manually rotated the piece
}

local wallGrid: { [number]: { [number]: WallData } } = {}
local buildingsFolder: Folder = nil

-- Initialize the wall system
function WallGridManager.initialize()
	print("[WallGridManager] Initializing...")

	-- Get or create Buildings folder
	buildingsFolder = Workspace:FindFirstChild("Buildings") :: Folder
	if not buildingsFolder then
		buildingsFolder = Instance.new("Folder")
		buildingsFolder.Name = "Buildings"
		buildingsFolder.Parent = Workspace
	end

	-- Scan existing walls and register them
	local wallCount = 0
	for _, child in buildingsFolder:GetChildren() do
		if child:IsA("Model") then
			local buildingType = child:GetAttribute("BuildingType")
			if buildingType and string.find(buildingType, "Wall") then
				-- Extract grid position from the model
				local position = child:GetPivot().Position
				local gridX, gridZ = WallPieceDatabase.worldToGrid(position)

				-- Register in grid
				if not wallGrid[gridX] then
					wallGrid[gridX] = {}
				end

				wallGrid[gridX][gridZ] = {
					instance = child,
					gridX = gridX,
					gridZ = gridZ,
					pieceType = child:GetAttribute("WallPieceType") or "Straight_Stone_Wall",
					rotation = child:GetAttribute("Rotation") or 0,
					ownerId = child:GetAttribute("Owner") or 0,
					manualOverride = child:GetAttribute("ManualPieceType"),
					manualRotation = child:GetAttribute("ManualRotation") or 0,
				}

				wallCount += 1
			end
		end
	end

	print(string.format("[WallGridManager] Initialized with %d existing walls", wallCount))

	-- Update all existing walls to ensure correct visuals
	for x, column in wallGrid do
		for z, _ in column do
			WallGridManager._updateWallVisuals(x, z)
		end
	end

	print("[WallGridManager] Initialization complete")
end

-- Calculate bitmask for neighbors at a grid position
function WallGridManager._calculateBitmask(gridX: number, gridZ: number): number
	local bitmask = 0

	for _, dir in WallPieceDatabase.DIRECTIONS do
		local nx = gridX + dir.x
		local nz = gridZ + dir.z

		-- Check if neighbor exists
		if wallGrid[nx] and wallGrid[nx][nz] then
			bitmask = bit32.bor(bitmask, dir.bit)
		end
	end

	return bitmask
end

-- Update wall visuals at a specific grid position
function WallGridManager._updateWallVisuals(gridX: number, gridZ: number, initialTargetY: number?)
	if not wallGrid[gridX] or not wallGrid[gridX][gridZ] then
		return
	end

	local wallData = wallGrid[gridX][gridZ]
	local bitmask = WallGridManager._calculateBitmask(gridX, gridZ)

	-- Determine which piece type and rotation to use
	local newPieceType, autoRotation = WallPieceDatabase.getPieceFromBitmask(bitmask, wallData.manualOverride)

	-- Combine auto rotation with manual rotation (if any)
	local manualRot = wallData.manualRotation or 0
	local finalRotation = (autoRotation + manualRot) % 360

	-- Check if we need to swap the model
	local currentPiece = wallData.instance:GetAttribute("WallPieceType") or wallData.pieceType
	local currentRotation = wallData.instance:GetAttribute("Rotation") or 0

	if currentPiece == newPieceType and currentRotation == finalRotation then
		-- No change needed
		return
	end

	-- Get the asset template
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets then
		warn("[WallGridManager] Assets folder not found")
		return
	end

	local buildings = assets:FindFirstChild("Buildings")
	if not buildings then
		warn("[WallGridManager] Buildings folder not found")
		return
	end

	local template = buildings:FindFirstChild(newPieceType)
	if not template or not template:IsA("Model") then
		warn(string.format("[WallGridManager] Wall piece template not found: %s", newPieceType))
		return
	end

	-- Clone new wall piece
	local newWall = template:Clone() :: Model

	-- Preserve the vertical placement. Use the initialTargetY if provided (for the very first placement),
	-- otherwise use the existing pivot's Y to prevent height changes during auto-tiling.
	local targetY = initialTargetY or wallData.instance:GetPivot().Position.Y

	-- Get the base world position from the database (which includes the 8x8 offset)
	local worldPos = WallPieceDatabase.gridToWorld(gridX, gridZ, targetY, newPieceType)

	-- For corner pieces, apply an additional small offset to close the 0.5 unit gap
	if newPieceType == "Corner_Stone_Wall" then
		local gapOffset = 0.5
		local offsetX, offsetZ = 0, 0
		if finalRotation == 0 then -- SE quadrant
			offsetX, offsetZ = -gapOffset, -gapOffset
		elseif finalRotation == 90 then -- SW quadrant
			offsetX, offsetZ = gapOffset, -gapOffset
		elseif finalRotation == 180 then -- NW quadrant
			offsetX, offsetZ = gapOffset, gapOffset
		elseif finalRotation == 270 then -- NE quadrant
			offsetX, offsetZ = -gapOffset, gapOffset
		end
		worldPos = worldPos + Vector3.new(offsetX, 0, offsetZ)
	end

	local rotationCFrame = CFrame.Angles(0, math.rad(finalRotation), 0)
	newWall:PivotTo(CFrame.new(worldPos) * rotationCFrame)

	-- Copy attributes from old wall
	newWall:SetAttribute("BuildingType", wallData.instance:GetAttribute("BuildingType") or "Stone_Wall")
	newWall:SetAttribute("Owner", wallData.ownerId)
	newWall:SetAttribute("WallPieceType", newPieceType)
	newWall:SetAttribute("Rotation", finalRotation)
	newWall:SetAttribute("GridX", gridX)
	newWall:SetAttribute("GridZ", gridZ)

	if wallData.manualOverride then
		newWall:SetAttribute("ManualPieceType", wallData.manualOverride)
	end

	if manualRot ~= 0 then
		newWall:SetAttribute("ManualRotation", manualRot)
	end

	-- Anchor all parts and disable collision on non-primary parts
	for _, descendant in newWall:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			if descendant ~= newWall.PrimaryPart then
				descendant.CanCollide = false
			end
		end
	end

	-- Set up properties
	newWall.Name = string.format("Wall_%d_%d", gridX, gridZ)
	newWall.Parent = buildingsFolder

	-- Clean up old wall
	wallData.instance:Destroy()

	-- Update grid reference
	wallData.instance = newWall
	wallData.pieceType = newPieceType
	wallData.rotation = finalRotation

	print(string.format(
		"[WallGridManager] Updated wall at (%d, %d): %s, rotation %d°, bitmask %d",
		gridX,
		gridZ,
		newPieceType,
		finalRotation,
		bitmask
	))
end

-- Place a new wall at grid coordinates
function WallGridManager.placeWall(
	gridX: number,
	gridZ: number,
	ownerId: number,
	buildingType: string,
	manualOverride: string?,
	manualRotation: number?
): Model?
	-- Check if position is already occupied
	if wallGrid[gridX] and wallGrid[gridX][gridZ] then
		warn(string.format("[WallGridManager] Grid position (%d, %d) already occupied", gridX, gridZ))
		return nil
	end

	-- Calculate initial bitmask
	local bitmask = WallGridManager._calculateBitmask(gridX, gridZ)

	-- Determine piece type
	local pieceType, autoRotation = WallPieceDatabase.getPieceFromBitmask(bitmask, manualOverride)

	-- Apply manual rotation if provided
	local rotation = autoRotation
	if manualRotation then
		rotation = (autoRotation + manualRotation) % 360
	end

	-- Get template
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets then
		warn("[WallGridManager] Assets folder not found")
		return nil
	end

	local buildings = assets:FindFirstChild("Buildings")
	if not buildings then
		warn("[WallGridManager] Buildings folder not found")
		return nil
	end

	local template = buildings:FindFirstChild(pieceType)
	if not template or not template:IsA("Model") then
		warn(string.format("[WallGridManager] Wall piece template not found: %s", pieceType))
		return nil
	end

	-- Clone and position wall
	local newWall = template:Clone() :: Model

	-- Get ground level by raycasting down from the grid cell center
	local raycastPos = WallPieceDatabase.gridToWorld(gridX, gridZ, 0, pieceType)
	local rayStart = Vector3.new(raycastPos.X, 1000, raycastPos.Z)
	local rayDir = Vector3.new(0, -2000, 0)
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude

	local rayResult = Workspace:Raycast(rayStart, rayDir, rayParams)
	local groundY = rayResult and rayResult.Position.Y or 0

	-- Calculate where to place the pivot to get the bottom on the ground
	local boundingCF, boundingSize = newWall:GetBoundingBox()
	local pivotY = newWall:GetPivot().Position.Y
	local boundingBottom = boundingCF.Position.Y - (boundingSize.Y / 2)
	local pivotToBottomOffset = pivotY - boundingBottom
	local targetPivotY = groundY + pivotToBottomOffset

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

	local rotationCFrame = CFrame.Angles(0, math.rad(rotation), 0)
	newWall:PivotTo(CFrame.new(worldPos) * rotationCFrame)

	-- Anchor all parts
	for _, descendant in newWall:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
		end
	end

	-- Set attributes
	newWall:SetAttribute("BuildingType", buildingType)
	newWall:SetAttribute("Owner", ownerId)
	newWall:SetAttribute("WallPieceType", pieceType)
	newWall:SetAttribute("Rotation", rotation)
	newWall:SetAttribute("GridX", gridX)
	newWall:SetAttribute("GridZ", gridZ)

	if manualOverride then
		newWall:SetAttribute("ManualPieceType", manualOverride)
	end

	if manualRotation and manualRotation ~= 0 then
		newWall:SetAttribute("ManualRotation", manualRotation)
	end

	newWall.Name = string.format("Wall_%d_%d", gridX, gridZ)
	newWall.Parent = buildingsFolder

	-- Register in grid
	if not wallGrid[gridX] then
		wallGrid[gridX] = {}
	end

	wallGrid[gridX][gridZ] = {
		instance = newWall,
		gridX = gridX,
		gridZ = gridZ,
		pieceType = pieceType,
		rotation = rotation,
		ownerId = ownerId,
		manualOverride = manualOverride,
		manualRotation = manualRotation or 0,
	}

	-- DEBUG: Log final placed position
	local finalPivot = newWall:GetPivot()
	local pos = finalPivot.Position
	print(string.format(
		"[SERVER PLACEMENT LOG] Type: %s, Grid: (%d, %d), Position: (%.2f, %.2f, %.2f), Rotation: %d",
		pieceType,
		gridX,
		gridZ,
		pos.X,
		pos.Y,
		pos.Z,
		rotation
	))

	-- Update this wall and all neighbors
	WallGridManager._updateWallVisuals(gridX, gridZ, targetPivotY)

	for _, dir in WallPieceDatabase.DIRECTIONS do
		WallGridManager._updateWallVisuals(gridX + dir.x, gridZ + dir.z)
	end

	return newWall
end

-- Remove a wall at grid coordinates
function WallGridManager.removeWall(gridX: number, gridZ: number): boolean
	if not wallGrid[gridX] or not wallGrid[gridX][gridZ] then
		return false
	end

	local wallData = wallGrid[gridX][gridZ]

	-- Destroy the instance
	if wallData.instance then
		wallData.instance:Destroy()
	end

	-- Remove from grid
	wallGrid[gridX][gridZ] = nil

	print(string.format("[WallGridManager] Removed wall at (%d, %d)", gridX, gridZ))

	-- Update neighbors
	for _, dir in WallPieceDatabase.DIRECTIONS do
		WallGridManager._updateWallVisuals(gridX + dir.x, gridZ + dir.z)
	end

	return true
end

-- Get wall data at grid position
function WallGridManager.getWall(gridX: number, gridZ: number): WallData?
	if wallGrid[gridX] and wallGrid[gridX][gridZ] then
		return wallGrid[gridX][gridZ]
	end
	return nil
end

-- Check if a position is occupied
function WallGridManager.isOccupied(gridX: number, gridZ: number): boolean
	return wallGrid[gridX] ~= nil and wallGrid[gridX][gridZ] ~= nil
end

-- Get all walls owned by a player
function WallGridManager.getPlayerWalls(ownerId: number): { WallData }
	local walls = {}

	for _, column in wallGrid do
		for _, wallData in column do
			if wallData.ownerId == ownerId then
				table.insert(walls, wallData)
			end
		end
	end

	return walls
end

-- Get all walls in the system
function WallGridManager.getAllWalls(): { WallData }
	local walls = {}

	for _, column in wallGrid do
		for _, wallData in column do
			table.insert(walls, wallData)
		end
	end

	return walls
end

-- Get wall count
function WallGridManager.getWallCount(): number
	local count = 0

	for _, column in wallGrid do
		for _ in column do
			count += 1
		end
	end

	return count
end

-- Debug: Print grid state
function WallGridManager.debugPrintGrid(centerX: number, centerZ: number, radius: number)
	print(string.format("[WallGridManager] Grid state around (%d, %d):", centerX, centerZ))

	for z = centerZ - radius, centerZ + radius do
		local line = ""
		for x = centerX - radius, centerX + radius do
			if wallGrid[x] and wallGrid[x][z] then
				line = line .. "X"
			else
				line = line .. "."
			end
		end
		print(line)
	end
end

return WallGridManager
