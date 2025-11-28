--!strict
-- WallManager: Handles wall placement, merging, and optimization
-- Manages grid-based wall tracking and automatic piece selection based on connections

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameData = require(ReplicatedStorage.Shared.GameData)

local DebugManager = require(ReplicatedStorage.Shared.DebugManager)
local channel = DebugManager.createChannel("WallManager", true) -- Enable debug for testing

local WallManager = {}

-- Grid configuration
local GRID_SIZE = 8 -- Wall grid is 8 studs (larger than building grid)
local WALL_HEIGHT_OFFSET = 3 -- Half of wall height for proper Y positioning

-- Wall piece types based on connections
export type WallType = "straight" | "corner" | "t_junction" | "cross"

-- Grid storage: stores wall instances by their grid coordinates
-- Key format: "x,z" where x and z are grid coordinates
type WallGrid = { [string]: WallInstance }

type WallInstance = {
	part: Part,
	gridX: number,
	gridZ: number,
	owner: number, -- UserId
	buildingType: string,
	connections: { -- Which directions have adjacent walls
		north: boolean,
		south: boolean,
		east: boolean,
		west: boolean,
	},
}

-- Track all walls by player
local PlayerWalls: { [number]: WallGrid } = {}

-- Helper: Convert world position to grid coordinates
local function worldToGrid(position: Vector3): (number, number)
	local gridX = math.floor(position.X / GRID_SIZE + 0.5)
	local gridZ = math.floor(position.Z / GRID_SIZE + 0.5)
	return gridX, gridZ
end

-- Helper: Convert grid coordinates to world position
local function gridToWorld(gridX: number, gridZ: number, yPosition: number?): Vector3
	return Vector3.new(gridX * GRID_SIZE, yPosition or WALL_HEIGHT_OFFSET, gridZ * GRID_SIZE)
end

-- Helper: Create grid key from coordinates
local function gridKey(gridX: number, gridZ: number): string
	return `{gridX},{gridZ}`
end

-- Helper: Get wall at grid position
local function getWallAt(userId: number, gridX: number, gridZ: number): WallInstance?
	local playerGrid = PlayerWalls[userId]
	if not playerGrid then
		return nil
	end
	return playerGrid[gridKey(gridX, gridZ)]
end

-- Update connections for a wall instance
local function updateWallConnections(wallInstance: WallInstance)
	local userId = wallInstance.owner
	local gridX = wallInstance.gridX
	local gridZ = wallInstance.gridZ

	-- Check all 4 directions
	wallInstance.connections.north = getWallAt(userId, gridX, gridZ - 1) ~= nil
	wallInstance.connections.south = getWallAt(userId, gridX, gridZ + 1) ~= nil
	wallInstance.connections.east = getWallAt(userId, gridX + 1, gridZ) ~= nil
	wallInstance.connections.west = getWallAt(userId, gridX - 1, gridZ) ~= nil
end

-- Determine wall type based on connections
local function getWallType(connections: { north: boolean, south: boolean, east: boolean, west: boolean }): WallType
	local connectionCount = 0
	if connections.north then
		connectionCount += 1
	end
	if connections.south then
		connectionCount += 1
	end
	if connections.east then
		connectionCount += 1
	end
	if connections.west then
		connectionCount += 1
	end

	if connectionCount == 0 then
		-- No connections - default to straight wall
		return "straight"
	elseif connectionCount == 1 then
		-- Single connection - end piece (acts as straight)
		return "straight"
	elseif connectionCount == 2 then
		-- Check if opposite connections (straight wall) or adjacent (corner)
		if (connections.north and connections.south) or (connections.east and connections.west) then
			return "straight" -- Opposite sides
		else
			return "corner" -- Adjacent sides (L-shape)
		end
	elseif connectionCount == 3 then
		return "t_junction"
	else -- connectionCount == 4
		return "cross"
	end
end

-- Calculate rotation based on connections
local function getWallRotation(connections: { north: boolean, south: boolean, east: boolean, west: boolean }, wallType: WallType): number
	-- Rotation in degrees (will be converted to CFrame)
	if wallType == "straight" then
		-- North-South is 0°, East-West is 90°
		-- Default to 0° (North-South orientation) if no connections
		if connections.east or connections.west then
			return 90 -- East-West orientation
		else
			return 0 -- North-South orientation (default)
		end
	elseif wallType == "corner" then
		-- Corner pieces: determine which two sides are connected
		if connections.north and connections.east then
			return 0 -- NE corner
		elseif connections.east and connections.south then
			return 90 -- SE corner
		elseif connections.south and connections.west then
			return 180 -- SW corner
		elseif connections.west and connections.north then
			return 270 -- NW corner
		-- Handle single connections (end pieces)
		elseif connections.north then
			return 180 -- Open to north
		elseif connections.east then
			return 270 -- Open to east
		elseif connections.south then
			return 0 -- Open to south
		else -- connections.west
			return 90 -- Open to west
		end
	elseif wallType == "t_junction" then
		-- T-junction: determine which side is NOT connected
		if not connections.north then
			return 180 -- Open to north
		elseif not connections.east then
			return 270 -- Open to east
		elseif not connections.south then
			return 0 -- Open to south
		else -- not connections.west
			return 90 -- Open to west
		end
	else -- cross
		return 0 -- Cross junction doesn't need rotation
	end

	return 0
end

-- Get the appropriate building name for wall type
local function getWallBuildingName(wallType: WallType, baseMaterial: string): string
	-- baseMaterial is "Stone" or "Wooden"
	local prefix = baseMaterial == "Stone" and "Stone_Wall" or "Wooden_Palisade"

	if wallType == "straight" then
		return `{prefix}_Straight`
	elseif wallType == "corner" then
		return `{prefix}_Corner`
	elseif wallType == "t_junction" then
		return `{prefix}_T`
	else -- cross
		return `{prefix}_Cross`
	end
end

-- Update wall visual based on its connections
local function updateWallVisual(wallInstance: WallInstance)
	local wallType = getWallType(wallInstance.connections)
	local rotation = getWallRotation(wallInstance.connections, wallType)

	-- Determine base material from building type
	local baseMaterial = "Stone"
	if string.find(wallInstance.buildingType, "Wooden") or string.find(wallInstance.buildingType, "Palisade") then
		baseMaterial = "Wooden"
	end

	-- Get the new building type
	local newBuildingType = getWallBuildingName(wallType, baseMaterial)
	local buildingInfo = GameData.Buildings[newBuildingType]

	if not buildingInfo then
		channel:warn(`Building info not found for {newBuildingType}`)
		return
	end

	-- Store old part info
	local oldPart = wallInstance.part
	local position = if oldPart:IsA("Model") then oldPart:GetPivot().Position else oldPart.Position
	local owner = oldPart:GetAttribute("Owner")
	local isConstructed = oldPart:GetAttribute("IsConstructed")
	local parent = oldPart.Parent

	-- Try to load new model if available
	local newPart: Instance? = nil

	if buildingInfo.model_asset_name then
		-- Try multiple possible paths for assets
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
				newPart = modelAsset:Clone()
				newPart.Name = oldPart.Name

				-- Scale straight walls slightly for overlap
				if newPart:IsA("Model") and wallType == "straight" then
					-- Scale model by 1.06 in the direction it extends to create 0.5 stud overlap
					local scaleAmount = 1.06
					for _, descendant in newPart:GetDescendants() do
						if descendant:IsA("BasePart") then
							-- Scale the part size
							local originalSize = descendant.Size
							-- For north-south walls (0° or 180°), scale Z axis
							-- For east-west walls (90° or 270°), scale X axis
							if rotation == 0 or rotation == 180 then
								descendant.Size = Vector3.new(originalSize.X, originalSize.Y, originalSize.Z * scaleAmount)
							else
								descendant.Size = Vector3.new(originalSize.X * scaleAmount, originalSize.Y, originalSize.Z)
							end
						end
					end
				end

				-- Set position and rotation
				local yRotation = CFrame.Angles(0, math.rad(rotation), 0) -- Y-axis rotation for wall orientation
				if newPart:IsA("Model") then
					-- Models need upright correction + Y rotation
					local uprightRotation = CFrame.Angles(math.rad(-90), 0, 0) -- Fix model being on its side
					newPart:PivotTo(CFrame.new(position) * yRotation * uprightRotation)
				else
					newPart.CFrame = CFrame.new(position) * yRotation
				end

				channel:info(`Swapped wall model to {buildingInfo.model_asset_name}`)
			end
		end
	end

	-- If no model found, just update existing part
	if not newPart then
		-- Update rotation
		local rotationCFrame = CFrame.Angles(0, math.rad(rotation), 0)
		if oldPart:IsA("Model") then
			oldPart:PivotTo(CFrame.new(position) * rotationCFrame)
		else
			oldPart.CFrame = CFrame.new(position) * rotationCFrame
			oldPart.Size = buildingInfo.size
		end

		oldPart:SetAttribute("BuildingType", newBuildingType)
		wallInstance.buildingType = newBuildingType
		channel:info(`Updated wall at ({wallInstance.gridX}, {wallInstance.gridZ}) to {wallType} with rotation {rotation}°`)
		return
	end

	-- Set attributes on new part
	newPart:SetAttribute("Owner", owner)
	newPart:SetAttribute("BuildingType", newBuildingType)
	newPart:SetAttribute("IsConstructed", isConstructed)

	-- Parent new part
	newPart.Parent = parent

	-- Update PlayerManager's building reference
	local Players = game:GetService("Players")
	local player = Players:GetPlayerByUserId(owner)
	if player then
		local PlayerManager = require(script.Parent.PlayerManager)
		local playerData = PlayerManager.get(player)
		if playerData then
			-- Find and replace old reference in buildings array
			for i, building in playerData.Buildings do
				if building == oldPart then
					playerData.Buildings[i] = newPart
					break
				end
			end
		end
	end

	-- Update wall instance reference
	wallInstance.part = newPart
	wallInstance.buildingType = newBuildingType

	-- Destroy old part
	oldPart:Destroy()

	channel:info(`Replaced wall model at ({wallInstance.gridX}, {wallInstance.gridZ}) to {wallType} with rotation {rotation}°`)
end

-- Register a new wall in the grid
function WallManager.registerWall(wallPart: Instance, userId: number, buildingType: string)
	channel:info(`Registering wall: {buildingType} for user {userId}`)

	-- Initialize player grid if needed
	if not PlayerWalls[userId] then
		PlayerWalls[userId] = {}
	end

	-- Get position (handle both Model and Part)
	local position = if wallPart:IsA("Model") then wallPart:GetPivot().Position else wallPart.Position

	-- Convert position to grid coordinates
	local gridX, gridZ = worldToGrid(position)

	-- Check if wall already exists at this position
	local existingKey = gridKey(gridX, gridZ)
	if PlayerWalls[userId][existingKey] then
		channel:warn(`Wall already exists at ({gridX}, {gridZ}) for user {userId}`)
		return
	end

	-- Create wall instance
	local wallInstance: WallInstance = {
		part = wallPart,
		gridX = gridX,
		gridZ = gridZ,
		owner = userId,
		buildingType = buildingType,
		connections = {
			north = false,
			south = false,
			east = false,
			west = false,
		},
	}

	-- Add to grid
	PlayerWalls[userId][existingKey] = wallInstance

	-- Update this wall's connections
	updateWallConnections(wallInstance)

	-- Update neighboring walls' connections
	local neighbors = {
		{ gridX, gridZ - 1 }, -- north
		{ gridX, gridZ + 1 }, -- south
		{ gridX + 1, gridZ }, -- east
		{ gridX - 1, gridZ }, -- west
	}

	for _, neighbor in neighbors do
		local neighborWall = getWallAt(userId, neighbor[1], neighbor[2])
		if neighborWall then
			updateWallConnections(neighborWall)
			updateWallVisual(neighborWall)
		end
	end

	-- Update this wall's visual
	updateWallVisual(wallInstance)

	channel:info(`Wall registered at grid ({gridX}, {gridZ})`)
end

-- Remove a wall from the grid
function WallManager.removeWall(wallPart: Instance)
	local userId = wallPart:GetAttribute("Owner")
	if not userId or not PlayerWalls[userId] then
		return
	end

	-- Get position (handle both Model and Part)
	local position = if wallPart:IsA("Model") then wallPart:GetPivot().Position else wallPart.Position
	local gridX, gridZ = worldToGrid(position)
	local key = gridKey(gridX, gridZ)

	local wallInstance = PlayerWalls[userId][key]
	if not wallInstance then
		return
	end

	channel:info(`Removing wall at grid ({gridX}, {gridZ}) for user {userId}`)

	-- Remove from grid
	PlayerWalls[userId][key] = nil

	-- Update neighboring walls
	local neighbors = {
		{ gridX, gridZ - 1 }, -- north
		{ gridX, gridZ + 1 }, -- south
		{ gridX + 1, gridZ }, -- east
		{ gridX - 1, gridZ }, -- west
	}

	for _, neighbor in neighbors do
		local neighborWall = getWallAt(userId, neighbor[1], neighbor[2])
		if neighborWall then
			updateWallConnections(neighborWall)
			updateWallVisual(neighborWall)
		end
	end
end

-- Get nearby walls for highlighting (client preview)
function WallManager.getNearbyWalls(position: Vector3, userId: number): { Part }
	local walls = {}
	local gridX, gridZ = worldToGrid(position)

	if not PlayerWalls[userId] then
		return walls
	end

	-- Check all adjacent positions
	local checkPositions = {
		{ gridX, gridZ - 1 }, -- north
		{ gridX, gridZ + 1 }, -- south
		{ gridX + 1, gridZ }, -- east
		{ gridX - 1, gridZ }, -- west
	}

	for _, pos in checkPositions do
		local wall = getWallAt(userId, pos[1], pos[2])
		if wall then
			table.insert(walls, wall.part)
		end
	end

	return walls
end

-- Check if position is valid for wall placement
function WallManager.isValidWallPosition(position: Vector3, userId: number): boolean
	local gridX, gridZ = worldToGrid(position)

	-- Check if wall already exists
	if getWallAt(userId, gridX, gridZ) then
		return false -- Already occupied
	end

	return true
end

-- Snap position to wall grid
function WallManager.snapToWallGrid(position: Vector3): Vector3
	local gridX, gridZ = worldToGrid(position)
	return gridToWorld(gridX, gridZ, position.Y)
end

-- Get wall grid size
function WallManager.getGridSize(): number
	return GRID_SIZE
end

return WallManager
