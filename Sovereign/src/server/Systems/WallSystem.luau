--!nonstrict
-- WallSystem - Manages wall segment placement, connections, and visual updates

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local WallGridConfig = require(ReplicatedStorage.Shared.WallGridConfig)

local WallSystem = {}

-- Grid storage
local wallGrid: { [number]: { [number]: Instance } } = {}

-- Assets
local Assets = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Buildings")

-- Directions: N=1, E=2, S=4, W=8
local DIRECTIONS = {
	{ x = 0, z = -1, bit = 1 }, -- North
	{ x = 1, z = 0, bit = 2 }, -- East
	{ x = 0, z = 1, bit = 4 }, -- South
	{ x = -1, z = 0, bit = 8 }, -- West
}

-- Lookup Table [Bitmask] = { AssetName, Rotation }
local ADJACENCY_LOOKUP = {
	[0] = { "Wall Segment", 0 },
	[1] = { "Wall Segment", 90 },
	[2] = { "Wall Segment", 0 },
	[3] = { "Wall Corner", 0 },
	[4] = { "Wall Segment", 90 },
	[5] = { "Wall Segment", 90 },
	[6] = { "Wall Corner", 270 },
	[7] = { "Tower", 0 },
	[8] = { "Wall Segment", 0 },
	[9] = { "Wall Corner", 90 },
	[10] = { "Wall Segment", 0 },
	[11] = { "Tower", 180 },
	[12] = { "Wall Corner", 180 },
	[13] = { "Tower", 90 },
	[14] = { "Tower", 270 },
	[15] = { "Tower", 0 },
}

local function findConnectionPoints(model: Model): { BasePart }
	if not model then
		return {}
	end
	local folder = model:FindFirstChild("ConnectionPoints")
	if folder then
		return folder:GetChildren()
	end

	local connectionPoints = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.Name == "ConnectionPoint" then
			table.insert(connectionPoints, descendant)
		end
	end
	return connectionPoints
end

-- Calculates the Center Position of all Connection Points
local function getConnectionPointCenter(model: Model): Vector3
	local connectionPoints = findConnectionPoints(model)
	if #connectionPoints == 0 then
		return model:GetPivot().Position
	end

	local totalPos = Vector3.new(0, 0, 0)
	for _, cp in connectionPoints do
		totalPos = totalPos + cp.Position
	end
	return totalPos / #connectionPoints
end

local function toGrid(position: Vector3)
	return WallGridConfig.toGrid(position)
end

-- Converts Grid Coordinates back to World Position (Assuming Y=0 or existing Y)
local function fromGrid(gx: number, gz: number, yLevel: number)
	return WallGridConfig.fromGrid(gx, gz, yLevel)
end

local function updateWallVisuals(x: number, z: number)
	if not wallGrid[x] or not wallGrid[x][z] then
		return
	end

	local currentWall = wallGrid[x][z] :: Model
	local bitmask = 0

	-- 1. Calculate Neighbors
	for _, dir in ipairs(DIRECTIONS) do
		local nx, nz = x + dir.x, z + dir.z
		if wallGrid[nx] and wallGrid[nx][nz] then
			bitmask = bitmask + dir.bit
		end
	end

	-- 2. Determine Asset and Rotation
	local manualPiece = currentWall:GetAttribute("ManualPieceType")
	local manualRot = currentWall:GetAttribute("ManualRotation") or 0

	local assetName, rotation

	if manualPiece then
		assetName = manualPiece
		rotation = manualRot
	else
		-- Auto-calculate based on neighbors + manual offset
		local config = ADJACENCY_LOOKUP[bitmask] or ADJACENCY_LOOKUP[0]
		assetName = config[1]
		-- Note: You might need complex rotation logic here if manualRot affects auto-tiling
		-- For simplicity, we assume auto-tiling overrides manual rotation unless specific type set
		rotation = (config[2] + manualRot) % 360
	end

	-- 3. Check if update needed
	local currentAsset = currentWall:GetAttribute("AssetName") or currentWall.Name
	local currentRotAttr = currentWall:GetAttribute("Rotation")

	if currentAsset == assetName and currentRotAttr == rotation then
		return
	end

	-- 4. Create New Model
	local originalAsset = Assets:FindFirstChild(assetName)
	if not originalAsset then
		return
	end

	local newModel = originalAsset:Clone()

	-- 5. Calculate Absolute Target Position
	-- We want the new model to stay exactly where the placed wall currently is
	-- (i.e. keep the ConnectionPoint center in the same world position).

	-- A. Use the current wall's ConnectionPoint center as the absolute truth.
	local oldCPCenter = getConnectionPointCenter(currentWall)
	local targetWorldCenter = oldCPCenter

	-- B. Rotate the new model around that world-space center.
	newModel:PivotTo(CFrame.new(targetWorldCenter) * CFrame.Angles(0, math.rad(rotation), 0))

	-- C. Calculate offset of the new model's connection points relative to its pivot.
	local newCPCenter = getConnectionPointCenter(newModel)
	local diff = targetWorldCenter - newCPCenter

	-- D. Apply offset so the new model's CP center matches the original CP center.
	newModel:PivotTo(newModel:GetPivot() + diff)

	-- 6. Setup Properties
	newModel.Parent = currentWall.Parent
	newModel.Name = currentWall.Name
	newModel:SetAttribute("Owner", currentWall:GetAttribute("Owner"))
	newModel:SetAttribute("BuildingType", currentWall:GetAttribute("BuildingType"))
	newModel:SetAttribute("AssetName", assetName)
	newModel:SetAttribute("Rotation", rotation)
	newModel:SetAttribute("ManualRotation", manualRot)
	if manualPiece then
		newModel:SetAttribute("ManualPieceType", manualPiece)
	end

	-- Cleanup ConnectionPoints
	for _, cp in findConnectionPoints(newModel) do
		cp.Anchored = false
		cp.CanCollide = false
		cp.Transparency = 1
	end

	wallGrid[x][z] = newModel
	currentWall:Destroy()
end

function WallSystem.registerWall(wallInstance: Instance)
	local wall = wallInstance :: Model
	local position = getConnectionPointCenter(wall)
	local x, z = toGrid(position)

	if not wallGrid[x] then
		wallGrid[x] = {}
	end
	wallGrid[x][z] = wall

	-- Update neighbors
	updateWallVisuals(x, z)
	for _, dir in ipairs(DIRECTIONS) do
		updateWallVisuals(x + dir.x, z + dir.z)
	end
end

function WallSystem.unregisterWall(wallInstance: Instance)
	local wall = wallInstance :: Model
	local position = getConnectionPointCenter(wall)
	local x, z = toGrid(position)

	if wallGrid[x] and wallGrid[x][z] == wallInstance then
		wallGrid[x][z] = nil
		for _, dir in ipairs(DIRECTIONS) do
			updateWallVisuals(x + dir.x, z + dir.z)
		end
	end
end

function WallSystem.initialize()
	local BuildingsFolder = Workspace:FindFirstChild("Buildings")
	if not BuildingsFolder then
		return
	end

	for _, child in BuildingsFolder:GetChildren() do
		local bType = child:GetAttribute("BuildingType")
		if bType and (bType == "Stone_Wall" or string.find(bType, "Wall")) and child:IsA("Model") then
			local position = getConnectionPointCenter(child)
			local x, z = toGrid(position)
			if not wallGrid[x] then
				wallGrid[x] = {}
			end
			wallGrid[x][z] = child
		end
	end
end

return WallSystem
