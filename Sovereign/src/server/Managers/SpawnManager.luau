--!strict
-- SpawnManager: Handles player spawn point assignment for multiplayer estates
-- Divides the map into spawn zones with neutral space between them (supports multiple maps)

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
		SpawnZoneSize = 400,
		NeutralZoneWidth = 100,
		SpawnHeight = 10,
		MaxPlayers = 4,
	}
end

-- Spawn assignments (stores which players are in which spawn zone)
local playerSpawns: { [number]: number } = {} -- Maps UserId to spawn number

-- Number of distinct kingdoms (spawn zones) the current map supports.
-- Hand-placed KeepSpawnZones take priority; otherwise the map's MaxPlayers.
local function getMaxSpawnZones(): number
	local mapConfig = getMapConfig()
	if mapConfig.KeepSpawnZones and #mapConfig.KeepSpawnZones > 0 then
		return #mapConfig.KeepSpawnZones
	end
	return mapConfig.MaxPlayers or 4
end

-- Calculate spawn points for each zone
-- Layout:
--   Zone 1 (NW)  |  NEUTRAL  |  Zone 2 (NE)
--   -----------------------------------------------
--      NEUTRAL   |  NEUTRAL  |    NEUTRAL
--   -----------------------------------------------
--   Zone 3 (SW)  |  NEUTRAL  |  Zone 4 (SE)

local function calculateSpawnPoint(spawnNumber: number): CFrame
	local mapConfig = getMapConfig()

	-- If the map has hand-placed KeepSpawnZones, use those positions directly.
	if mapConfig.KeepSpawnZones then
		for _, zone in ipairs(mapConfig.KeepSpawnZones) do
			if zone.Zone == spawnNumber then
				return CFrame.new(zone.X, zone.Y, zone.Z)
			end
		end
	end

	-- Fallback: calculate from quadrant dimensions (procedural / player-made maps).
	local halfEstate = (mapConfig.SpawnZoneSize or mapConfig.QuadrantSize) / 2
	local offset = halfEstate + (mapConfig.NeutralZoneWidth / 2)

	if spawnNumber == 1 then
		return CFrame.new(-offset, mapConfig.SpawnHeight, -offset)
	elseif spawnNumber == 2 then
		return CFrame.new(offset, mapConfig.SpawnHeight, -offset)
	elseif spawnNumber == 3 then
		return CFrame.new(-offset, mapConfig.SpawnHeight, offset)
	elseif spawnNumber == 4 then
		return CFrame.new(offset, mapConfig.SpawnHeight, offset)
	elseif spawnNumber > 4 then
		-- Maps with more than 4 kingdoms and no hand-placed zones: distribute
		-- the extra kingdoms evenly on a circle inside the map bounds.
		local maxZones = getMaxSpawnZones()
		local angle = (math.pi * 2 * (spawnNumber - 1)) / math.max(maxZones, 1)
		local ringRadius = offset * math.sqrt(2)
		return CFrame.new(
			math.cos(angle) * ringRadius,
			mapConfig.SpawnHeight,
			math.sin(angle) * ringRadius
		)
	end

	return CFrame.new(0, mapConfig.SpawnHeight, 0)
end

-- Get the keep spawn radius for a zone (used to define where the Keep can be placed).
function SpawnManager.getKeepSpawnRadius(spawnNumber: number): number
	local mapConfig = getMapConfig()
	if mapConfig.KeepSpawnZones then
		for _, zone in ipairs(mapConfig.KeepSpawnZones) do
			if zone.Zone == spawnNumber then
				return zone.Radius
			end
		end
	end
	-- Fallback: use a sensible default
	return (mapConfig.SpawnZoneSize or mapConfig.QuadrantSize) / 2
end

-- Get the keep spawn center for a zone (XZ only, for building placement validation).
function SpawnManager.getKeepSpawnCenter(spawnNumber: number): Vector3?
	local mapConfig = getMapConfig()
	if mapConfig.KeepSpawnZones then
		for _, zone in ipairs(mapConfig.KeepSpawnZones) do
			if zone.Zone == spawnNumber then
				return Vector3.new(zone.X, zone.Y, zone.Z)
			end
		end
	end
	return nil
end

-- Get estate boundaries for a spawn zone
function SpawnManager.getEstateBounds(spawnNumber: number): { min: Vector3, max: Vector3 }
	local mapConfig = getMapConfig()
	local halfEstate = (mapConfig.SpawnZoneSize or mapConfig.QuadrantSize) / 2
	local offset = halfEstate + (mapConfig.NeutralZoneWidth / 2)

	if spawnNumber == 1 then
		return {
			min = Vector3.new(-offset - halfEstate, 0, offset - halfEstate),
			max = Vector3.new(-offset + halfEstate, 256, offset + halfEstate),
		}
	elseif spawnNumber == 2 then
		return {
			min = Vector3.new(offset - halfEstate, 0, offset - halfEstate),
			max = Vector3.new(offset + halfEstate, 256, offset + halfEstate),
		}
	elseif spawnNumber == 3 then
		return {
			min = Vector3.new(-offset - halfEstate, 0, -offset - halfEstate),
			max = Vector3.new(-offset + halfEstate, 256, -offset + halfEstate),
		}
	elseif spawnNumber == 4 then
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
function SpawnManager.isPositionInEstate(position: Vector3, spawnNumber: number): boolean
	-- For maps with KeepSpawnZones, use radius-based check from zone center
	local mapConfig = getMapConfig()
	if mapConfig.KeepSpawnZones then
		for _, zone in ipairs(mapConfig.KeepSpawnZones) do
			if zone.Zone == spawnNumber then
				local dx = position.X - zone.X
				local dz = position.Z - zone.Z
				local radius = zone.Radius or 150
				return (dx * dx + dz * dz) <= (radius * radius)
			end
		end
	end

	-- Fallback: procedural quadrant bounding box
	local bounds = SpawnManager.getEstateBounds(spawnNumber)
	return position.X >= bounds.min.X and position.X <= bounds.max.X
		and position.Z >= bounds.min.Z and position.Z <= bounds.max.Z
end

-- Assign a player to a specific spawn zone (from lobby selection)
function SpawnManager.assignPlayerToExplicitSpawn(userId: number, spawnNumber: number): number
	if spawnNumber < 1 or spawnNumber > getMaxSpawnZones() then
		SpawnManagerDebug:warn(`Invalid spawn {spawnNumber} for player {userId}, falling back to auto-assign`)
		return SpawnManager.assignPlayerToSpawn(userId)
	end

	-- Check if spawn is already taken by someone else
	for existingUserId, existingSpawn in pairs(playerSpawns) do
		if existingSpawn == spawnNumber and existingUserId ~= userId then
			SpawnManagerDebug:warn(`Spawn {spawnNumber} already taken by {existingUserId}, falling back to auto-assign`)
			return SpawnManager.assignPlayerToSpawn(userId)
		end
	end

	playerSpawns[userId] = spawnNumber
	SpawnManagerDebug:info(`Explicitly assigned player {userId} to spawn {spawnNumber}`)
	return spawnNumber
end

-- Assign a player to a spawn zone (round-robin assignment, skips already-taken zones)
function SpawnManager.assignPlayerToSpawn(userId: number): number
	-- Check if player already has a spawn
	if playerSpawns[userId] then
		return playerSpawns[userId]
	end

	-- Find the spawn zone with the fewest players (one zone per kingdom)
	local maxZones = getMaxSpawnZones()
	local spawnCounts: { number } = table.create(maxZones, 0)
	for _, spawn in pairs(playerSpawns) do
		if spawn >= 1 and spawn <= maxZones then
			spawnCounts[spawn] = spawnCounts[spawn] + 1
		end
	end

	-- Find minimum count spawn
	local minSpawn = 1
	local minCount = spawnCounts[1]
	for i = 2, maxZones do
		if spawnCounts[i] < minCount then
			minSpawn = i
			minCount = spawnCounts[i]
		end
	end

	-- Assign player to this spawn
	playerSpawns[userId] = minSpawn
	SpawnManagerDebug:info(`Assigned player {userId} to spawn {minSpawn}`)

	return minSpawn
end

-- Get spawn point for a player
function SpawnManager.getPlayerSpawnPoint(userId: number): CFrame
	local spawn = SpawnManager.assignPlayerToSpawn(userId)
	return calculateSpawnPoint(spawn)
end

-- Get player's spawn number
function SpawnManager.getPlayerSpawn(userId: number): number?
	return playerSpawns[userId]
end

-- Get estate build radius (half of estate size)
function SpawnManager.getBuildRadius(): number
	local mapConfig = getMapConfig()
	return (mapConfig.SpawnZoneSize or mapConfig.QuadrantSize) / 2
end

-- Get max players (kingdoms) for current map
function SpawnManager.getMaxPlayers(): number
	return getMaxSpawnZones()
end

-- Remove player from spawn zone (when they leave)
function SpawnManager.removePlayer(userId: number)
	if playerSpawns[userId] then
		SpawnManagerDebug:info(`Removed player {userId} from spawn {playerSpawns[userId]}`)
		playerSpawns[userId] = nil
	end
end

-- Full state wipe for a new match: clears every zone assignment (players and
-- AI alike — both are just numeric userIds in this table). Called once from
-- GameManager's LeaveGame teardown when the last player leaves.
function SpawnManager.resetMatch()
	playerSpawns = {}
	SpawnManagerDebug:info("SpawnManager match state reset — cleared all zone assignments")
end

-- Get all players in a spawn zone
function SpawnManager.getPlayersInSpawn(spawnNumber: number): { number }
	local players = {}
	for userId, spawn in pairs(playerSpawns) do
		if spawn == spawnNumber then
			table.insert(players, userId)
		end
	end
	return players
end

-- Backwards compatibility aliases
SpawnManager.assignPlayerToQuadrant = SpawnManager.assignPlayerToSpawn
SpawnManager.assignPlayerToExplicitQuadrant = SpawnManager.assignPlayerToExplicitSpawn
SpawnManager.getPlayerQuadrant = SpawnManager.getPlayerSpawn
SpawnManager.getPlayersInQuadrant = SpawnManager.getPlayersInSpawn

-- Debug: Print current spawn assignments
function SpawnManager.printAssignments()
	SpawnManagerDebug:info("=== Spawn Assignments ===")
	for userId, spawn in pairs(playerSpawns) do
		SpawnManagerDebug:info(`  Player {userId}: Spawn {spawn}`)
	end
end

SpawnManagerDebug:info("SpawnManager loaded")

return SpawnManager
