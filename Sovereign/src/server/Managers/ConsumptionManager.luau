--!strict
-- ConsumptionManager: Manages food consumption for population and buildings

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerManager = require(script.Parent.PlayerManager)
local PopulationManager = require(script.Parent.PopulationManager)
local BuildingManager = require(script.Parent.BuildingManager)
local SeasonManager = require(script.Parent.SeasonManager)
local GameData = require(ReplicatedStorage.Shared.GameData)
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)

local ConsumptionDebug = DebugManager.createChannel("ConsumptionManager", true)

local ConsumptionManager = {}

-- Track consumption data per player
local consumptionData = {}

export type ConsumptionData = {
	lastConsumptionTime: number,
	totalConsumedThisCycle: number,
	isStarving: boolean,
	starvationDuration: number, -- How long (in seconds) they've been starving
}

-- Initialize consumption data for a player
function ConsumptionManager.create(player: Player)
	consumptionData[player.UserId] = {
		lastConsumptionTime = tick(),
		totalConsumedThisCycle = 0,
		isStarving = false,
		starvationDuration = 0,
	}
	ConsumptionDebug:info(`Created consumption data for {player.Name}`)
end

-- Get consumption data for a player
function ConsumptionManager.get(player: Player): ConsumptionData?
	return consumptionData[player.UserId]
end

-- Calculate food consumption rate for population
-- Base: 0.1 food per peasant per consumption cycle (30 seconds)
function ConsumptionManager.getPopulationConsumption(player: Player): number
	local population = PopulationManager.getCurrentPopulation(player)
	local consumptionRate = 0.1 -- food per person per 30 seconds
	return population * consumptionRate
end

-- Calculate food consumption for buildings (Kitchen, Restaurant)
function ConsumptionManager.getBuildingConsumption(player: Player): number
	local playerData = PlayerManager.get(player)
	if not playerData then
		return 0
	end

	local totalConsumption = 0

	for _, building in playerData.Buildings do
		if building and building.Parent then
			local buildingType = building:GetAttribute("BuildingType")
			local buildingData = GameData.Buildings[buildingType]

			-- Check if building consumes resources
			if buildingData and buildingData.consumes_resource == "Food" then
				local consumptionRate = buildingData.consumption_rate or 0

				-- Only consume if building has a worker assigned
				local hasWorker = building:GetAttribute("HasWorker") or false
				if hasWorker then
					totalConsumption += consumptionRate
				end
			end
		end
	end

	return totalConsumption
end

-- Get total food consumption for this cycle
function ConsumptionManager.getTotalConsumption(player: Player): number
	local popConsumption = ConsumptionManager.getPopulationConsumption(player)
	local buildingConsumption = ConsumptionManager.getBuildingConsumption(player)
	local baseConsumption = popConsumption + buildingConsumption

	-- Apply seasonal multiplier
	local seasonalMultiplier = SeasonManager.getFoodConsumptionMultiplier(player)
	local totalConsumption = baseConsumption * seasonalMultiplier

	return totalConsumption
end

-- Process food consumption for a player
function ConsumptionManager.consumeFood(player: Player): boolean
	local playerData = PlayerManager.get(player)
	local consData = consumptionData[player.UserId]

	if not playerData or not consData then
		return false
	end

	local totalConsumption = ConsumptionManager.getTotalConsumption(player)
	local currentFood = playerData.Resources.Food or 0

	ConsumptionDebug:info(`{player.Name} needs {totalConsumption} food (has {currentFood})`)

	-- Check if we have enough food
	if currentFood >= totalConsumption then
		-- Deduct food
		PlayerManager.deductResources(player, { Food = totalConsumption })

		consData.totalConsumedThisCycle = totalConsumption
		consData.isStarving = false
		consData.starvationDuration = 0
		consData.lastConsumptionTime = tick()

		ConsumptionDebug:info(`{player.Name} consumed {totalConsumption} food successfully`)

		-- Notify client
		local RemoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")
		if RemoteEvents then
			local GameEvent = RemoteEvents:FindFirstChild("GameEvent")
			if GameEvent then
				GameEvent:FireClient(player, "FoodConsumed", {
					amount = totalConsumption,
					remaining = playerData.Resources.Food,
				})
			end
		end

		return true
	else
		-- Not enough food - STARVATION!
		consData.isStarving = true
		consData.starvationDuration += 30 -- Add 30 seconds (consumption cycle time)

		-- Consume whatever food is available
		if currentFood > 0 then
			PlayerManager.deductResources(player, { Food = currentFood })
			consData.totalConsumedThisCycle = currentFood
		else
			consData.totalConsumedThisCycle = 0
		end

		ConsumptionDebug:warn(`{player.Name} is STARVING! (Duration: {consData.starvationDuration}s)`)

		-- Notify client of starvation
		local RemoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")
		if RemoteEvents then
			local GameEvent = RemoteEvents:FindFirstChild("GameEvent")
			if GameEvent then
				GameEvent:FireClient(player, "Starvation", {
					needed = totalConsumption,
					available = currentFood,
					duration = consData.starvationDuration,
				})
			end
		end

		return false
	end
end

-- Check if player is currently starving
function ConsumptionManager.isStarving(player: Player): boolean
	local consData = consumptionData[player.UserId]
	if not consData then
		return false
	end
	return consData.isStarving
end

-- Get starvation duration in seconds
function ConsumptionManager.getStarvationDuration(player: Player): number
	local consData = consumptionData[player.UserId]
	if not consData then
		return 0
	end
	return consData.starvationDuration
end

-- Get consumption breakdown for UI display
function ConsumptionManager.getConsumptionBreakdown(player: Player): { [string]: number }
	return {
		Population = ConsumptionManager.getPopulationConsumption(player),
		Buildings = ConsumptionManager.getBuildingConsumption(player),
		Total = ConsumptionManager.getTotalConsumption(player),
	}
end

-- Initialize the consumption system
function ConsumptionManager.init()
	Players.PlayerAdded:Connect(ConsumptionManager.create)

	ConsumptionDebug:info("ConsumptionManager initialized")
end

return ConsumptionManager
