--!strict
-- PopulationManager: Manages population, housing, and population growth

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerManager = require(script.Parent.PlayerManager)
local BuildingManager = require(script.Parent.BuildingManager)
local GameData = require(ReplicatedStorage.Shared.GameData)
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)

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
function PopulationManager.create(player: Player)
	local playerData = PlayerManager.get(player)
	if playerData then
		populationData[player.UserId] = {
			currentPopulation = 0, -- Will be calculated from units
			housingCapacity = 0, -- Will be calculated from buildings
			lastGrowthCheck = tick(),
			isOvercrowded = false,
		}
		PopulationDebug:info(`Created population data for {player.Name}`)
	end
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

	-- Spawn a new peasant near the Keep
	local UnitManager = require(script.Parent.UnitManager)
	local keepPos = keep.PrimaryPart.Position
	local randomOffset = Vector3.new(
		math.random(-10, 10),
		0,
		math.random(-10, 10)
	)
	local spawnPos = keepPos + randomOffset

	local faction = playerData.Faction or "Kingdom"
	UnitManager.createUnit("Peasant", player.UserId, spawnPos, faction)

	PopulationDebug:info(`{player.Name} grew population! New peasant spawned.`)

	-- Update population stats
	PopulationManager.update(player)

	return true
end

-- Initialize the population system
function PopulationManager.init()
	Players.PlayerAdded:Connect(PopulationManager.create)

	-- Periodically update population for all players
	task.spawn(function()
		while true do
			task.wait(5) -- Update every 5 seconds
			for _, player in ipairs(Players:GetPlayers()) do
				PopulationManager.update(player)
			end
		end
	end)

	PopulationDebug:info("PopulationManager initialized")
end

return PopulationManager
