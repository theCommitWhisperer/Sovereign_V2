--!strict
-- SpawnManager: Handles player spawn point assignment for multiplayer estates
-- Divides the map into quadrants with neutral space between them (supports multiple maps)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)

local SpawnManagerDebug = DebugManager.createChannel("SpawnManager", false)

local SpawnManager = {}

-- Map configuration will be set by MapManager
local currentMapConfig: any = nil

-- Set the current map configuration (called by GameManager on game start)
function SpawnManager.setMapConfig(mapConfig: any)
	currentMapConfig = mapConfig
	SpawnManagerDebug:info(`Map config set: {mapConfig.Name} ({mapConfig.Size}x{mapConfig.Size})`)
end

-- Get current map config (with defaults if not set)
local function getMapConfig(): any
	if currentMapConfig then
		return currentMapConfig
	end

	-- Default fallback configuration
	return {
		Size = 1000,
		QuadrantSize = 400,
		NeutralZoneWidth = 100,
		SpawnHeight = 10,
		MaxPlayers = 4,
	}
end

-- Quadrant assignments (stores which players are in which quadrant)
local quadrantAssignments: { [number]: string } = {}
local playerQuadrants: { [number]: number } = {} -- Maps UserId to quadrant number

-- Calculate spawn points for each quadrant
-- Layout:
--   Quadrant 1 (NW)  |  NEUTRAL  |  Quadrant 2 (NE)
--   ------------------------------------------------
--        NEUTRAL     |  NEUTRAL  |     NEUTRAL
--   ------------------------------------------------
--   Quadrant 3 (SW)  |  NEUTRAL  |  Quadrant 4 (SE)

local function calculateQuadrantSpawnPoint(quadrantNumber: number): CFrame
	local mapConfig = getMapConfig()
	local halfEstate = mapConfig.QuadrantSize / 2
	local offset = halfEstate + (mapConfig.NeutralZoneWidth / 2)

	if quadrantNumber == 1 then
		-- Northwest quadrant
		return CFrame.new(-offset, mapConfig.SpawnHeight, offset)
	elseif quadrantNumber == 2 then
		-- Northeast quadrant
		return CFrame.new(offset, mapConfig.SpawnHeight, offset)
	elseif quadrantNumber == 3 then
		-- Southwest quadrant
		return CFrame.new(-offset, mapConfig.SpawnHeight, -offset)
	elseif quadrantNumber == 4 then
		-- Southeast quadrant
		return CFrame.new(offset, mapConfig.SpawnHeight, -offset)
	end

	-- Default to center (should never happen)
	return CFrame.new(0, mapConfig.SpawnHeight, 0)
end

-- Get estate boundaries for a quadrant
function SpawnManager.getEstateBounds(quadrantNumber: number): { min: Vector3, max: Vector3 }
	local mapConfig = getMapConfig()
	local halfEstate = mapConfig.QuadrantSize / 2
	local offset = halfEstate + (mapConfig.NeutralZoneWidth / 2)

	if quadrantNumber == 1 then
		-- Northwest quadrant
		return {
			min = Vector3.new(-offset - halfEstate, 0, offset - halfEstate),
			max = Vector3.new(-offset + halfEstate, 256, offset + halfEstate),
		}
	elseif quadrantNumber == 2 then
		-- Northeast quadrant
		return {
			min = Vector3.new(offset - halfEstate, 0, offset - halfEstate),
			max = Vector3.new(offset + halfEstate, 256, offset + halfEstate),
		}
	elseif quadrantNumber == 3 then
		-- Southwest quadrant
		return {
			min = Vector3.new(-offset - halfEstate, 0, -offset - halfEstate),
			max = Vector3.new(-offset + halfEstate, 256, -offset + halfEstate),
		}
	elseif quadrantNumber == 4 then
		-- Southeast quadrant
		return {
			min = Vector3.new(offset - halfEstate, 0, -offset - halfEstate),
			max = Vector3.new(offset + halfEstate, 256, -offset + halfEstate),
		}
	end

	-- Default bounds (should never happen)
	return {
		min = Vector3.new(-50, 0, -50),
		max = Vector3.new(50, 256, 50),
	}
end

-- Check if a position is within estate bounds
function SpawnManager.isPositionInEstate(position: Vector3, quadrantNumber: number): boolean
	local bounds = SpawnManager.getEstateBounds(quadrantNumber)

	return position.X >= bounds.min.X and position.X <= bounds.max.X
		and position.Z >= bounds.min.Z and position.Z <= bounds.max.Z
end

-- Assign a player to a quadrant (round-robin assignment)
function SpawnManager.assignPlayerToQuadrant(userId: number): number
	-- Check if player already has a quadrant
	if playerQuadrants[userId] then
		return playerQuadrants[userId]
	end

	-- Find the quadrant with the fewest players
	local quadrantCounts = { 0, 0, 0, 0 }
	for _, quadrant in pairs(playerQuadrants) do
		quadrantCounts[quadrant] = quadrantCounts[quadrant] + 1
	end

	-- Find minimum count quadrant
	local minQuadrant = 1
	local minCount = quadrantCounts[1]
	for i = 2, 4 do
		if quadrantCounts[i] < minCount then
			minQuadrant = i
			minCount = quadrantCounts[i]
		end
	end

	-- Assign player to this quadrant
	playerQuadrants[userId] = minQuadrant
	SpawnManagerDebug:info(`Assigned player {userId} to quadrant {minQuadrant}`)

	return minQuadrant
end

-- Get spawn point for a player
function SpawnManager.getPlayerSpawnPoint(userId: number): CFrame
	local quadrant = SpawnManager.assignPlayerToQuadrant(userId)
	return calculateQuadrantSpawnPoint(quadrant)
end

-- Get player's quadrant number
function SpawnManager.getPlayerQuadrant(userId: number): number?
	return playerQuadrants[userId]
end

-- Get estate build radius (half of estate size)
function SpawnManager.getBuildRadius(): number
	local mapConfig = getMapConfig()
	return mapConfig.QuadrantSize / 2
end

-- Get max players for current map
function SpawnManager.getMaxPlayers(): number
	local mapConfig = getMapConfig()
	return mapConfig.MaxPlayers or 4
end

-- Remove player from quadrant (when they leave)
function SpawnManager.removePlayer(userId: number)
	if playerQuadrants[userId] then
		SpawnManagerDebug:info(`Removed player {userId} from quadrant {playerQuadrants[userId]}`)
		playerQuadrants[userId] = nil
	end
end

-- Get all players in a quadrant
function SpawnManager.getPlayersInQuadrant(quadrantNumber: number): { number }
	local players = {}
	for userId, quadrant in pairs(playerQuadrants) do
		if quadrant == quadrantNumber then
			table.insert(players, userId)
		end
	end
	return players
end

-- Debug: Print current quadrant assignments
function SpawnManager.printAssignments()
	SpawnManagerDebug:info("=== Quadrant Assignments ===")
	for userId, quadrant in pairs(playerQuadrants) do
		SpawnManagerDebug:info(`  Player {userId}: Quadrant {quadrant}`)
	end
end

SpawnManagerDebug:info("SpawnManager loaded")

return SpawnManager
