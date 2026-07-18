--!strict
-- PopulationManager: Manages population, housing, and population growth

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerManager = require(script.Parent.PlayerManager)
local BuildingManager = require(script.Parent.BuildingManager)
local GameData = require(ReplicatedStorage.Shared.GameData)
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)
local IdlePeasantManager = require(script.Parent.IdlePeasantManager)

local PopulationDebug = DebugManager.createChannel("PopulationManager", false)

local PopulationManager = {}

-- Track population data per player
local populationData = {}

export type PopulationData = {
	currentPopulation: number,
	housingCapacity: number,
	lastGrowthCheck: number,
	isOvercrowded: boolean,
}

-- Initialize population data for a player
function PopulationManager.create(player)
	local playerData = PlayerManager.get(player)
	if playerData then
		populationData[player.UserId] = {
			currentPopulation = 0, -- Will be calculated from units
			housingCapacity = 0, -- Will be calculated from buildings
			lastGrowthCheck = tick(),
			isOvercrowded = false,
			isAI = false,
		}
		PopulationDebug:info("Created population data for " .. player.Name)
	end
end

-- Initialize population data for an AI player
function PopulationManager.createAI(ownerId, ownerName)
	populationData[ownerId] = {
		currentPopulation = 0,
		housingCapacity = 0,
		lastGrowthCheck = tick(),
		isOvercrowded = false,
		isAI = true,
		aiName = ownerName,
	}
	PopulationDebug:info("Created population data for AI: " .. ownerName)
end

-- Get population data for a player
function PopulationManager.get(player: Player): PopulationData?
	return populationData[player.UserId]
end

-- Calculate current population (non-military units)
function PopulationManager.getCurrentPopulation(player: Player): number
	local playerData = PlayerManager.get(player)
	if not playerData then
		return 0
	end

	local count = 0
	for _, unit in playerData.Units do
		if unit and unit.Parent then
			local unitType = unit:GetAttribute("UnitType")
			-- Count civilian units (peasants, workers, etc.)
			-- Don't count military units
			if unitType == "Peasant" or unitType == "Ox" then
				count += 1
			end
		end
	end

	return count
end

-- Calculate total housing capacity from all housing buildings
function PopulationManager.getHousingCapacity(player: Player): number
	local playerData = PlayerManager.get(player)
	if not playerData then
		return 0
	end

	local capacity = 0
	for _, building in playerData.Buildings do
		if building and building.Parent then
			local buildingType = building:GetAttribute("BuildingType")
			local buildingData = GameData.Buildings[buildingType]

			if buildingData and buildingData.housing_capacity then
				capacity += buildingData.housing_capacity
			end
		end
	end

	-- Keep always provides base housing for starting population
	local hasKeep = false
	for _, building in playerData.Buildings do
		if building and building.Parent then
			local buildingType = building:GetAttribute("BuildingType")
			if buildingType == "Keep" then
				hasKeep = true
				break
			end
		end
	end

	if hasKeep then
		capacity += 10 -- Keep provides base housing for 10 people
	end

	return capacity
end

-- Update population stats for a player
function PopulationManager.update(player: Player)
	local popData = populationData[player.UserId]
	if not popData then
		return
	end

	local currentPop = PopulationManager.getCurrentPopulation(player)
	local housingCap = PopulationManager.getHousingCapacity(player)

	popData.currentPopulation = currentPop
	popData.housingCapacity = housingCap
	popData.isOvercrowded = currentPop > housingCap

	-- Send update to client
	local RemoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")
	if RemoteEvents then
		local GameEvent = RemoteEvents:FindFirstChild("GameEvent")
		if GameEvent then
			GameEvent:FireClient(player, "UpdatePopulation", {
				current = currentPop,
				capacity = housingCap,
				isOvercrowded = popData.isOvercrowded,
			})
		end
	end

	PopulationDebug:info(`{player.Name} population: {currentPop}/{housingCap} (Overcrowded: {popData.isOvercrowded})`)
end

-- Check if player can support more population
function PopulationManager.canGrowPopulation(player: Player): boolean
	local popData = populationData[player.UserId]
	if not popData then
		return false
	end

	-- Can only grow if we have housing space
	return popData.currentPopulation < popData.housingCapacity
end

-- Check if player is overcrowded (affects happiness)
function PopulationManager.isOvercrowded(player: Player): boolean
	local popData = populationData[player.UserId]
	if not popData then
		return false
	end

	return popData.isOvercrowded
end

-- Get population growth rate based on conditions
function PopulationManager.getGrowthRate(player: Player): number
	local playerData = PlayerManager.get(player)
	if not playerData then
		return 0
	end

	-- Base growth rate: 1 peasant per 60 seconds if conditions are met
	local baseRate = 60 -- seconds per new peasant

	-- Factors that affect growth
	local hasFood = (playerData.Resources.Food or 0) > 50
	local hasHousing = PopulationManager.canGrowPopulation(player)
	local isHappy = (playerData.Happiness or 0) > 40

	-- No growth if basic needs aren't met
	if not hasFood or not hasHousing or not isHappy then
		return 0
	end

	-- Bonus growth with abundant food
	if (playerData.Resources.Food or 0) > 200 then
		baseRate = 45 -- Faster growth with abundant food
	end

	return baseRate
end

-- Attempt to grow population (spawn a new peasant)
function PopulationManager.tryGrowPopulation(player: Player): boolean
	if not PopulationManager.canGrowPopulation(player) then
		PopulationDebug:info(`{player.Name} cannot grow - no housing capacity`)
		return false
	end

	local playerData = PlayerManager.get(player)
	if not playerData then
		return false
	end

	-- Find the Keep to spawn near
	local keep = playerData.Keep
	if not keep or not keep.Parent then
		PopulationDebug:warn(`{player.Name} has no Keep - cannot spawn peasant`)
		return false
	end

	-- Spawn a new peasant at the Keep's SpawnPoint (or near it if no SpawnPoint)
	local UnitManager = require(script.Parent.UnitManager)
	local SpawnPointSystem = require(script.Parent.Parent.Systems.SpawnPointSystem)

	-- Try to use SpawnPoint first
	local spawnPos = SpawnPointSystem.getSpawnPosition(keep)

	if not spawnPos then
		-- Fallback to Keep center with random offset if no SpawnPoint
		PopulationDebug:warn(`Keep has no SpawnPoint, using center with random offset`)
		local keepPos = keep.PrimaryPart.Position
		local randomOffset = Vector3.new(
			math.random(-10, 10),
			0,
			math.random(-10, 10)
		)
		spawnPos = keepPos + randomOffset
	end

	local faction = playerData.Faction or "Kingdom"
	local peasant = UnitManager.createUnit("Peasant", player.UserId, spawnPos, faction)

	if peasant then
		-- Add new peasant to idle behavior
		IdlePeasantManager.addIdlePeasant(peasant, player.UserId)
	end

	PopulationDebug:info(`{player.Name} grew population! New peasant spawned.`)

	-- Update population stats
	PopulationManager.update(player)

	return true
end

-- AI-specific functions for population management

-- Get population data by ownerId (works for both AI and players)
function PopulationManager.getByOwnerId(ownerId)
	return populationData[ownerId]
end

-- Check if AI can grow population
function PopulationManager.canGrowPopulationAI(ownerId)
	local popData = populationData[ownerId]
	if not popData then
		return false
	end

	return popData.currentPopulation < popData.housingCapacity
end

-- Attempt to grow AI population (spawn a new peasant)
function PopulationManager.tryGrowPopulationAI(ownerId)
	if not PopulationManager.canGrowPopulationAI(ownerId) then
		return false
	end

	local popData = populationData[ownerId]
	if not popData or not popData.isAI then
		return false
	end

	-- Get AI state from AIManager
	local AIManager = require(script.Parent.AIManager)
	local aiState = AIManager.getState(ownerId)
	if not aiState or not aiState.hasKeep then
		return false
	end

	-- Check if AI has enough food
	if (aiState.resources.Food or 0) < 50 then
		return false
	end

	-- Spawn a new peasant 70-90 studs from Keep (Keep is 94x110 studs, must spawn outside)
	local UnitManager = require(script.Parent.UnitManager)
	local angle = math.random() * math.pi * 2
	local distance = math.random(70, 90)
	local spawnOffset = Vector3.new(
		math.cos(angle) * distance,
		0,
		math.sin(angle) * distance
	)
	local basePos = aiState.spawnPoint.Position + spawnOffset
	local spawnPos = Vector3.new(basePos.X, 10, basePos.Z)

	PopulationDebug:info("[PEASANT SPAWN] PopulationManager - " .. popData.aiName .. " attempting to spawn peasant at " .. tostring(spawnPos))
	local peasant = UnitManager.createUnit("Peasant", ownerId, spawnPos, aiState.faction)
	if peasant then
		PopulationDebug:info("[PEASANT SPAWN] PopulationManager - " .. popData.aiName .. " grew population! New peasant spawned (automatic)")

		-- Update AI unit tracking
		table.insert(aiState.units, peasant)
		aiState.unitCount = aiState.unitCount + 1

		-- Update population count
		popData.currentPopulation = popData.currentPopulation + 1
		return true
	end

	return false
end

-- Update AI population stats
function PopulationManager.updateAI(ownerId)
	local popData = populationData[ownerId]
	if not popData or not popData.isAI then
		return
	end

	local AIManager = require(script.Parent.AIManager)
	local aiState = AIManager.getState(ownerId)
	if not aiState then
		return
	end

	-- Count current peasants
	local count = 0
	for _, unit in ipairs(aiState.units) do
		if unit and unit.Parent then
			local unitType = unit:GetAttribute("UnitType")
			if unitType == "Peasant" or unitType == "Ox" then
				count = count + 1
			end
		end
	end

	-- Calculate housing capacity from buildings
	local capacity = 0
	for _, building in ipairs(aiState.buildings) do
		if building and building.Parent then
			local buildingType = building:GetAttribute("BuildingType")
			local GameData = require(game.ReplicatedStorage.Shared.GameData)
			local buildingData = GameData.Buildings[buildingType]

			if buildingData and buildingData.housing_capacity then
				capacity = capacity + buildingData.housing_capacity
			end
		end
	end

	-- Keep provides base housing
	if aiState.hasKeep then
		capacity = capacity + 10
	end

	popData.currentPopulation = count
	popData.housingCapacity = capacity
	popData.isOvercrowded = count > capacity
end

-- Initialize the population system
function PopulationManager.init()
	Players.PlayerAdded:Connect(PopulationManager.create)

	PopulationDebug:info("PopulationManager initialized with AI support")
end

function PopulationManager.startLoop()
	-- Periodically update population for all players
	task.spawn(function()
		while true do
			task.wait(5)
			for _, player in ipairs(Players:GetPlayers()) do
				PopulationManager.update(player)
			end
		end
	end)

	-- Periodically update AI populations
	task.spawn(function()
		while true do
			task.wait(5)
			for ownerId, popData in pairs(populationData) do
				if popData.isAI then
					PopulationManager.updateAI(ownerId)
				end
			end
		end
	end)

	-- Automatic population growth for both players and AI
	task.spawn(function()
		while true do
			task.wait(60)

			for _, player in ipairs(Players:GetPlayers()) do
				if PopulationManager.canGrowPopulation(player) then
					local growthRate = PopulationManager.getGrowthRate(player)
					if growthRate > 0 then
						PopulationManager.tryGrowPopulation(player)
					end
				end
			end

			for ownerId, popData in pairs(populationData) do
				if popData.isAI then
					if PopulationManager.canGrowPopulationAI(ownerId) then
						local AIManager = require(script.Parent.AIManager)
						local aiState = AIManager.getState(ownerId)
						if aiState and (aiState.resources.Food or 0) > 50 then
							PopulationManager.tryGrowPopulationAI(ownerId)
						end
					end
				end
			end
		end
	end)
end

return PopulationManager
