--!strict
-- TrainingManager: Handles unit training queues and production

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameData = require(ReplicatedStorage.Shared.GameData)
local PlayerManager = require(script.Parent.PlayerManager)
local UnitManager = require(script.Parent.UnitManager)
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)

-- Lazy-load to avoid circular dependencies
local AchievementManager = nil
local QuestManager = nil

local TrainingDebug = DebugManager.createChannel("Training", false)

local TrainingManager = {}

-- Training queue entry
export type TrainingQueueEntry = {
	unitType: string,
	buildingId: string,
	ownerId: number,
	timeRemaining: number,
	totalTime: number,
}

-- Training queues per building
local TrainingQueues: { [string]: { TrainingQueueEntry } } = {}

-- Get building ID
local function getBuildingId(building: Instance): string
	return building.Name
end

-- Check if player can afford unit
local function canAffordUnit(player: Player, unitType: string): boolean
	local unitInfo = GameData.Units[unitType]
	if not unitInfo or not unitInfo.cost then
		return false
	end

	local playerData = PlayerManager.get(player)
	if not playerData then
		return false
	end

	for resource, cost in unitInfo.cost do
		local available = playerData.Resources[resource] or 0
		if available < cost then
			return false
		end
	end

	return true
end

-- Deduct resources for unit
local function deductResources(player: Player, unitType: string): boolean
	local unitInfo = GameData.Units[unitType]
	if not unitInfo or not unitInfo.cost then
		return false
	end

	local playerData = PlayerManager.get(player)
	if not playerData then
		return false
	end

	-- Deduct resources
	for resource, cost in unitInfo.cost do
		playerData.Resources[resource] = (playerData.Resources[resource] or 0) - cost
	end

	-- Update client
	local RemoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")
	if RemoteEvents then
		local gameEvent = RemoteEvents:FindFirstChild("GameEvent")
		if gameEvent then
			gameEvent:FireClient(player, "UpdateResources", {
				resources = playerData.Resources,
			})
		end
	end

	return true
end

-- Start training a unit
function TrainingManager.startTraining(building: Instance, unitType: string, ownerId: number): boolean
	local buildingId = getBuildingId(building)
	local buildingType = building:GetAttribute("BuildingType")

	if not buildingType then
		TrainingDebug:warn("Building has no type")
		return false
	end

	local buildingInfo = GameData.Buildings[buildingType]
	if not buildingInfo or not buildingInfo.can_train_units then
		TrainingDebug:warn(`{buildingType} cannot train units`)
		return false
	end

	-- Check if building can train this unit type
	local canTrain = false
	for _, trainableUnit in buildingInfo.can_train_units do
		if trainableUnit == unitType then
			canTrain = true
			break
		end
	end

	if not canTrain then
		TrainingDebug:warn(`{buildingType} cannot train {unitType}`)
		return false
	end

	-- Check queue size
	if not TrainingQueues[buildingId] then
		TrainingQueues[buildingId] = {}
	end

	local maxQueueSize = buildingInfo.max_queue_size or 5
	if #TrainingQueues[buildingId] >= maxQueueSize then
		TrainingDebug:warn("Training queue is full")
		return false
	end

	-- Check if player can afford
	local player = game.Players:GetPlayerByUserId(ownerId)
	if not player then
		return false
	end

	if not canAffordUnit(player, unitType) then
		TrainingDebug:warn(`Player cannot afford {unitType}`)
		return false
	end

	-- Deduct resources
	if not deductResources(player, unitType) then
		return false
	end

	-- Get training time
	local unitInfo = GameData.Units[unitType]
	local trainingTime = unitInfo.training_time_seconds or 10

	-- Add to queue
	local queueEntry: TrainingQueueEntry = {
		unitType = unitType,
		buildingId = buildingId,
		ownerId = ownerId,
		timeRemaining = trainingTime,
		totalTime = trainingTime,
	}

	table.insert(TrainingQueues[buildingId], queueEntry)

	TrainingDebug:info(`Started training {unitType}`, {
		buildingId = buildingId,
		queueSize = #TrainingQueues[buildingId],
		trainingTime = trainingTime,
	})

	return true
end

-- Get training queue for a building
function TrainingManager.getQueue(building: Instance): { TrainingQueueEntry }
	local buildingId = getBuildingId(building)
	return TrainingQueues[buildingId] or {}
end

-- Update training queues
local function updateTraining(deltaTime: number)
	for buildingId, queue in TrainingQueues do
		if #queue > 0 then
			local currentEntry = queue[1] -- Process first in queue

			-- Update time
			currentEntry.timeRemaining = currentEntry.timeRemaining - deltaTime

			if currentEntry.timeRemaining <= 0 then
				-- Training complete!
				TrainingDebug:info(`Training complete: {currentEntry.unitType}`)

				-- Find the building
				local building = workspace:FindFirstChild("Buildings")
					and workspace.Buildings:FindFirstChild(buildingId)

				if building then
					-- Spawn the unit near the building
					local player = game.Players:GetPlayerByUserId(currentEntry.ownerId)
					if player then
						local spawnPosition = building.Position
							+ Vector3.new(math.random(-10, 10), 5, math.random(-10, 10))

						-- Get the player's faction
						local playerData = PlayerManager.get(player)
						local faction = playerData and playerData.Faction or "Kingdom"

						TrainingDebug:info(`About to spawn trained unit`, {
							unitType = currentEntry.unitType,
							faction = faction,
							hasFaction = faction ~= nil,
						})

						UnitManager.createUnit(currentEntry.unitType, currentEntry.ownerId, spawnPosition, faction)

						-- Track achievements and quests (lazy-load to avoid circular deps)
						if not AchievementManager then
							AchievementManager = require(script.Parent.AchievementManager)
						end
						if not QuestManager then
							QuestManager = require(script.Parent.QuestManager)
						end

						AchievementManager.incrementStat(player, "UnitsTrained", 1)
						QuestManager.updateQuestProgress(player, "TrainUnits", "Any", 1)
					end
				end

				-- Remove from queue
				table.remove(queue, 1)
			end
		end
	end
end

-- Start update loop
RunService.Heartbeat:Connect(function(deltaTime)
	updateTraining(deltaTime)
end)

TrainingDebug:info("Initialized")

return TrainingManager
