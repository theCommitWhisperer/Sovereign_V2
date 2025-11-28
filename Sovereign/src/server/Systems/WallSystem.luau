--!nonstrict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local WallSystem = {}

-- Configuration
local WALL_GRID_SIZE = 8 -- Wall segments are 8x8
local WALL_HEIGHT_OFFSET = 0 -- Adjust based on your model's pivot

-- Spatial Hash: [x][z] = WallInstance
local wallGrid: { [number]: { [number]: Instance } } = {}

-- Load Assets (Assuming these exist in ReplicatedStorage.Assets.Buildings)
-- You may need to adjust the path to match where your assets are stored
local Assets = ReplicatedStorage:WaitForChild("Assets", 5) and ReplicatedStorage.Assets:WaitForChild("Buildings", 5)

if not Assets then
	warn("WallSystem: Could not find Assets.Buildings folder. Visuals will not update.")
end

-- Bitmask Directions: N=1, E=2, S=4, W=8
local DIRECTIONS = {
	{ x = 0, z = -1, bit = 1 }, -- North
	{ x = 1, z = 0, bit = 2 }, -- East
	{ x = 0, z = 1, bit = 4 }, -- South
	{ x = -1, z = 0, bit = 8 }, -- West
}

-- Model Lookup Table: [Bitmask] = { AssetName, YRotation }
-- Assumes default assets are:
-- Straight: Horizontal (E-W) at 0°, Vertical (N-S) at 90°
-- Corner: Oriented to match straight wall connections
-- 3Way: Oriented to match straight wall connections
local ADJACENCY_LOOKUP = {
	[0] = { "Wall Segment", 0 }, -- Isolated (Default to Horizontal)
	[1] = { "Wall Segment", 90 }, -- N (Vertical)
	[2] = { "Wall Segment", 0 }, -- E (Horizontal)
	[3] = { "Wall Corner", 0 }, -- N + E (NE Corner)
	[4] = { "Wall Segment", 90 }, -- S (Vertical)
	[5] = { "Wall Segment", 90 }, -- N + S (Straight Vertical)
	[4] = { "Wall Segment", 0 }, -- S (Vertical)
	[5] = { "Wall Segment", 0 }, -- N + S (Straight Vertical)
	[6] = { "Wall Corner", 270 }, -- E + S (SE Corner)
	[7] = { "Tower", 0 }, -- N + E + S (East T)
	[8] = { "Wall Segment", 0 }, -- W (Horizontal)
	[8] = { "Wall Segment", 90 }, -- W (Horizontal)
	[9] = { "Wall Corner", 90 }, -- N + W (NW Corner)
	[10] = { "Wall Segment", 0 }, -- E + W (Straight Horizontal)
	[10] = { "Wall Segment", 90 }, -- E + W (Straight Horizontal)
	[11] = { "Tower", 180 }, -- N + W + E (North T)
	[12] = { "Wall Corner", 180 }, -- S + W (SW Corner)
	[13] = { "Tower", 90 }, -- N + S + W (West T)
	[14] = { "Tower", 270 }, -- S + W + E (South T)
	[15] = { "Tower", 0 }, -- N + E + S + W (4-way)
}

-- Convert World Position to Grid Coordinates
local function toGrid(position: Vector3)
	return math.floor(position.X / WALL_GRID_SIZE + 0.5), math.floor(position.Z / WALL_GRID_SIZE + 0.5)
end

-- Update the visual model of a specific wall based on neighbors
local function updateWallVisuals(x: number, z: number)
	if not wallGrid[x] or not wallGrid[x][z] then
		return
	end

	local currentWall = wallGrid[x][z] :: Model
	local bitmask = 0

	-- Calculate neighbor bitmask
	for _, dir in ipairs(DIRECTIONS) do
		local nx, nz = x + dir.x, z + dir.z
		if wallGrid[nx] and wallGrid[nx][nz] then
			-- Check if the neighbor is also a Stone Wall (or compatible type)
			-- You can add a specific Attribute check here if you have multiple wall types
			bitmask = bitmask + dir.bit
		end
	end

	-- Check if wall has a manually selected piece type
	local manualPieceType = currentWall:GetAttribute("ManualPieceType")
	local manualRotation = currentWall:GetAttribute("ManualRotation") or 0

	-- If wall has manual piece type, don't auto-update it
	local assetName: string
	local rotation: number

	if manualPieceType then
		-- Manual piece selection - just keep the current piece and rotation
		assetName = manualPieceType
		rotation = manualRotation
	elseif manualRotation ~= 0 then
		-- Manual rotation mode: figure out which piece based on neighbors AND rotation
		-- Rotate the bitmask to match the manual rotation
		local rotatedBitmask = bitmask
		if manualRotation == 90 then
			-- Rotate bitmask 90° clockwise: N->E, E->S, S->W, W->N
			rotatedBitmask = 0
			if bit32.band(bitmask, 1) > 0 then
				rotatedBitmask = rotatedBitmask + 2
			end -- N->E
			if bit32.band(bitmask, 2) > 0 then
				rotatedBitmask = rotatedBitmask + 4
			end -- E->S
			if bit32.band(bitmask, 4) > 0 then
				rotatedBitmask = rotatedBitmask + 8
			end -- S->W
			if bit32.band(bitmask, 8) > 0 then
				rotatedBitmask = rotatedBitmask + 1
			end -- W->N
		elseif manualRotation == 180 then
			-- Rotate bitmask 180°: N->S, E->W, S->N, W->E
			rotatedBitmask = 0
			if bit32.band(bitmask, 1) > 0 then
				rotatedBitmask = rotatedBitmask + 4
			end -- N->S
			if bit32.band(bitmask, 2) > 0 then
				rotatedBitmask = rotatedBitmask + 8
			end -- E->W
			if bit32.band(bitmask, 4) > 0 then
				rotatedBitmask = rotatedBitmask + 1
			end -- S->N
			if bit32.band(bitmask, 8) > 0 then
				rotatedBitmask = rotatedBitmask + 2
			end -- W->E
		elseif manualRotation == 270 then
			-- Rotate bitmask 270° clockwise: N->W, E->N, S->E, W->S
			rotatedBitmask = 0
			if bit32.band(bitmask, 1) > 0 then
				rotatedBitmask = rotatedBitmask + 8
			end -- N->W
			if bit32.band(bitmask, 2) > 0 then
				rotatedBitmask = rotatedBitmask + 1
			end -- E->N
			if bit32.band(bitmask, 4) > 0 then
				rotatedBitmask = rotatedBitmask + 2
			end -- S->E
			if bit32.band(bitmask, 8) > 0 then
				rotatedBitmask = rotatedBitmask + 4
			end -- W->S
		end

		local config = ADJACENCY_LOOKUP[rotatedBitmask] or ADJACENCY_LOOKUP[0]
		assetName = config[1]
		rotation = (config[2] + manualRotation) % 360
	else
		-- Automatic mode: use neighbors to determine piece
		local config = ADJACENCY_LOOKUP[bitmask] or ADJACENCY_LOOKUP[0]
		assetName = config[1]
		rotation = config[2]
	end

	-- Check if we need to swap the model
	local currentAsset = currentWall:GetAttribute("AssetName")
	local currentRotation = currentWall:GetAttribute("Rotation")

	-- Use model name as fallback for asset name
	if not currentAsset then
		currentAsset = currentWall.Name
	end

	-- Calculate current rotation from CFrame if attribute not set
	if not currentRotation then
		local _, currentY, _ = currentWall:GetPivot():ToEulerAnglesYXZ()
		local rotDeg = math.deg(currentY)
		-- Normalize to 0-359 range
		currentRotation = rotDeg % 360
	end

	-- Check if already correct (within 1 degree tolerance for rotation)
	local rotationMatches = math.abs((currentRotation :: number) - rotation) < 1
	if currentAsset == assetName and rotationMatches then
		-- Set attributes if missing
		if not currentWall:GetAttribute("AssetName") then
			currentWall:SetAttribute("AssetName", assetName)
		end
		if not currentWall:GetAttribute("Rotation") then
			currentWall:SetAttribute("Rotation", rotation)
		end
		return -- No change needed
	end

	-- Find the asset
	local originalAsset = Assets:FindFirstChild(assetName)
	if not originalAsset then
		return
	end

	-- Create new geometry
	local newModel = originalAsset:Clone()

	-- Preserve essential attributes
	newModel:SetAttribute("Owner", currentWall:GetAttribute("Owner"))
	newModel:SetAttribute("BuildingType", currentWall:GetAttribute("BuildingType"))
	newModel:SetAttribute("AssetName", assetName)
	newModel:SetAttribute("Rotation", rotation)
	newModel:SetAttribute("ManualRotation", manualRotation) -- Preserve manual rotation
	if manualPieceType then
		newModel:SetAttribute("ManualPieceType", manualPieceType) -- Preserve manual piece type
	end
	newModel.Name = currentWall.Name

	-- Position - preserve the original position and only apply rotation
	local originalCFrame = currentWall:GetPivot()
	local position = originalCFrame.Position

	-- Create new CFrame with the same position but new rotation
	local newCFrame = CFrame.new(position) * CFrame.Angles(0, math.rad(rotation), 0)
	newModel:PivotTo(newCFrame)

	newModel.Parent = currentWall.Parent

	-- Update Grid Reference
	wallGrid[x][z] = newModel

	-- Destroy old model
	currentWall:Destroy()
end

-- Call this when a wall is placed
function WallSystem.registerWall(wallInstance: Instance)
	local wall = wallInstance :: Model
	local x, z = toGrid(wall:GetPivot().Position)

	if not wallGrid[x] then
		wallGrid[x] = {}
	end
	wallGrid[x][z] = wall

	-- Update self and all 4 neighbors
	updateWallVisuals(x, z)
	for _, dir in ipairs(DIRECTIONS) do
		updateWallVisuals(x + dir.x, z + dir.z)
	end
end

-- Call this when a wall is destroyed/sold
function WallSystem.unregisterWall(wallInstance: Instance)
	local wall = wallInstance :: Model
	local x, z = toGrid(wall:GetPivot().Position)

	if wallGrid[x] and wallGrid[x][z] == wallInstance then
		wallGrid[x][z] = nil

		-- Update neighbors to remove connections
		for _, dir in ipairs(DIRECTIONS) do
			updateWallVisuals(x + dir.x, z + dir.z)
		end
	end
end

-- Scan the workspace for existing walls and rebuild the grid
function WallSystem.initialize()
	local BuildingsFolder = Workspace:FindFirstChild("Buildings")
	if not BuildingsFolder then
		return
	end

	print("WallSystem: Initializing grid from existing save data...")

	-- 1. Populate Grid
	for _, child in BuildingsFolder:GetChildren() do
		if child:GetAttribute("BuildingType") == "Stone_Wall" and child:IsA("Model") then
			local x, z = toGrid(child:GetPivot().Position)
			if not wallGrid[x] then
				wallGrid[x] = {}
			end
			wallGrid[x][z] = child
		end
	end

	-- 2. Update Visuals
	for x, zRow in pairs(wallGrid) do
		for z, _ in pairs(zRow) do
			updateWallVisuals(x, z)
		end
	end
end

return WallSystem
