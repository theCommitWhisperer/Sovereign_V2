--!strict
-- IdlePeasantManager: Manages idle peasant behavior (campfire gathering + roaming)
-- Peasants not assigned to work tasks will either:
-- 1. Gather around a campfire near the Keep SpawnPoint (60% of idle peasants)
-- 2. Roam around the Keep area (40% of idle peasants)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)
local SpawnPointSystem = require(script.Parent.Parent.Systems.SpawnPointSystem)

local IdlePeasantManager = {}

-- Debug channel
local IdleDebug = DebugManager.createChannel("IdlePeasant", false)

-- Idle peasant behavior tracking
export type IdleBehavior = {
	peasant: Model,
	behaviorType: "Campfire" | "Roaming",
	ownerId: number,
	campfirePosition: Vector3?, -- Position to gather at (for Campfire behavior)
	roamCenter: Vector3?, -- Center point for roaming (for Roaming behavior)
	roamRadius: number, -- Roaming radius (default: 30 studs)
	nextRoamTime: number, -- When to pick a new roaming destination
	targetPosition: Vector3?, -- Current roaming target
}

local IdlePeasants: { IdleBehavior } = {}
local lastBehaviorUpdate = 0
local BEHAVIOR_UPDATE_INTERVAL = 2 -- Update behaviors every 2 seconds
local ROAM_RADIUS = 30 -- Peasants roam within 30 studs of Keep
local CAMPFIRE_POSITIONS_COUNT = 6 -- 6 positions around the campfire
local CAMPFIRE_RADIUS = 8 -- 8 studs from SpawnPoint

-- Get campfire positions in a circle around Keep's SpawnPoint
local function getCampfirePositions(keepSpawnPoint: Vector3, count: number): { Vector3 }
	local positions = {}

	for i = 1, count do
		local angle = (math.pi * 2 * (i - 1)) / count
		local xOffset = math.cos(angle) * CAMPFIRE_RADIUS
		local zOffset = math.sin(angle) * CAMPFIRE_RADIUS
		local position = keepSpawnPoint + Vector3.new(xOffset, 0, zOffset)
		table.insert(positions, position)
	end

	return positions
end

-- Find Keep for a player
local function findPlayerKeep(ownerId: number): Model?
	local PlayerManager = require(script.Parent.PlayerManager)
	local Players = game:GetService("Players")

	for _, player in ipairs(Players:GetPlayers()) do
		if player.UserId == ownerId then
			local playerData = PlayerManager.get(player)
			if playerData and playerData.Keep then
				return playerData.Keep
			end
			break
		end
	end

	return nil
end

-- Add a peasant to idle behavior
function IdlePeasantManager.addIdlePeasant(peasant: Model, ownerId: number)
	-- Remove if already exists
	for i = #IdlePeasants, 1, -1 do
		if IdlePeasants[i].peasant == peasant then
			table.remove(IdlePeasants, i)
			break
		end
	end

	-- Find the player's Keep
	local keep = findPlayerKeep(ownerId)
	if not keep then
		IdleDebug:warn(`Cannot add idle peasant - no Keep found for owner {ownerId}`)
		return
	end

	-- Get Keep's SpawnPoint
	local spawnPoint = SpawnPointSystem.getSpawnPosition(keep)
	if not spawnPoint then
		IdleDebug:warn(`Keep has no SpawnPoint - using Keep center`)
		spawnPoint = keep.PrimaryPart and keep.PrimaryPart.Position or Vector3.new(0, 0, 0)
	end

	-- Randomly assign behavior type (60% campfire, 40% roaming)
	local behaviorType: "Campfire" | "Roaming" = math.random() < 0.6 and "Campfire" or "Roaming"

	local behavior: IdleBehavior

	if behaviorType == "Campfire" then
		-- Assign to one of the campfire positions
		local campfirePositions = getCampfirePositions(spawnPoint, CAMPFIRE_POSITIONS_COUNT)
		local randomPosition = campfirePositions[math.random(1, #campfirePositions)]

		behavior = {
			peasant = peasant,
			behaviorType = "Campfire",
			ownerId = ownerId,
			campfirePosition = randomPosition,
			roamCenter = nil,
			roamRadius = ROAM_RADIUS,
			nextRoamTime = 0,
			targetPosition = randomPosition,
		}

		IdleDebug:info(`Peasant {peasant.Name} assigned to Campfire at {randomPosition}`)
	else
		-- Roaming behavior
		behavior = {
			peasant = peasant,
			behaviorType = "Roaming",
			ownerId = ownerId,
			campfirePosition = nil,
			roamCenter = spawnPoint,
			roamRadius = ROAM_RADIUS,
			nextRoamTime = tick() + math.random(2, 5), -- Random initial delay
			targetPosition = nil,
		}

		IdleDebug:info(`Peasant {peasant.Name} assigned to Roaming around {spawnPoint}`)
	end

	table.insert(IdlePeasants, behavior)
	peasant:SetAttribute("IsIdle", true)
end

-- Remove a peasant from idle behavior (when assigned to work/hauling)
function IdlePeasantManager.removeIdlePeasant(peasant: Model)
	for i = #IdlePeasants, 1, -1 do
		if IdlePeasants[i].peasant == peasant then
			table.remove(IdlePeasants, i)
			peasant:SetAttribute("IsIdle", false)
			IdleDebug:info(`Removed {peasant.Name} from idle behavior`)
			return true
		end
	end
	return false
end

-- Check if a peasant is idle
function IdlePeasantManager.isIdle(peasant: Model): boolean
	for _, behavior in ipairs(IdlePeasants) do
		if behavior.peasant == peasant then
			return true
		end
	end
	return false
end

-- Get all idle peasants for a specific owner
function IdlePeasantManager.getIdlePeasantsForOwner(ownerId: number): { Model }
	local peasants = {}
	for _, behavior in ipairs(IdlePeasants) do
		if behavior.ownerId == ownerId then
			table.insert(peasants, behavior.peasant)
		end
	end
	return peasants
end

-- Pathfind peasant to a position
local function pathfindToPosition(unit: Model, targetPos: Vector3, threshold: number): boolean
	if not unit.PrimaryPart then
		return false
	end

	local currentPos = unit.PrimaryPart.Position
	local distance2D = (Vector3.new(targetPos.X, 0, targetPos.Z) - Vector3.new(currentPos.X, 0, currentPos.Z)).Magnitude

	-- Check if arrived
	if distance2D <= threshold then
		unit:SetAttribute("IsMoving", false)
		unit:SetAttribute("TargetPosition", nil)
		return true
	end

	-- Set pathfinding target (MovementSystem will handle the actual pathfinding)
	local currentTarget = unit:GetAttribute("TargetPosition")
	if not currentTarget or (currentTarget - targetPos).Magnitude > 1 then
		unit:SetAttribute("TargetPosition", targetPos)
		unit:SetAttribute("IsMoving", true)
	end

	return false
end

-- Update idle behaviors
local function updateIdleBehaviors(dt: number)
	for i = #IdlePeasants, 1, -1 do
		local behavior = IdlePeasants[i]

		-- Check if peasant still exists
		if not behavior.peasant or not behavior.peasant.Parent then
			table.remove(IdlePeasants, i)
			continue
		end

		-- Check if peasant was assigned to work (should have been removed)
		if behavior.peasant:GetAttribute("IsWorking") or behavior.peasant:GetAttribute("IsHauling") then
			table.remove(IdlePeasants, i)
			behavior.peasant:SetAttribute("IsIdle", false)
			continue
		end

		if behavior.behaviorType == "Campfire" then
			-- Campfire behavior: Stay at assigned campfire position
			if behavior.campfirePosition then
				pathfindToPosition(behavior.peasant, behavior.campfirePosition, 2)
			end

		elseif behavior.behaviorType == "Roaming" then
			-- Roaming behavior: Pick random positions within radius
			if behavior.roamCenter then
				-- Time to pick a new roaming target?
				if tick() >= behavior.nextRoamTime then
					-- Pick a random position within roam radius
					local angle = math.random() * math.pi * 2
					local distance = math.random() * behavior.roamRadius
					local xOffset = math.cos(angle) * distance
					local zOffset = math.sin(angle) * distance

					behavior.targetPosition = behavior.roamCenter + Vector3.new(xOffset, 0, zOffset)
					behavior.nextRoamTime = tick() + math.random(5, 10) -- Next roam in 5-10 seconds

					IdleDebug:info(`Peasant {behavior.peasant.Name} roaming to {behavior.targetPosition}`)
				end

				-- Pathfind to current roaming target
				if behavior.targetPosition then
					local arrived = pathfindToPosition(behavior.peasant, behavior.targetPosition, 3)
					if arrived then
						-- Reached target, pick a new one soon
						behavior.nextRoamTime = tick() + math.random(2, 4)
					end
				end
			end
		end
	end
end

-- Update loop
function IdlePeasantManager.update(dt: number)
	lastBehaviorUpdate = lastBehaviorUpdate + dt

	if lastBehaviorUpdate >= BEHAVIOR_UPDATE_INTERVAL then
		updateIdleBehaviors(dt)
		lastBehaviorUpdate = 0
	end
end

return IdlePeasantManager
