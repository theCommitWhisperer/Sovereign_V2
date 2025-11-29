--!strict
-- EconomyDashboardManager: Provides consolidated economy stats for UI display

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerManager = require(script.Parent.PlayerManager)
local PopulationManager = require(script.Parent.PopulationManager)
local ConsumptionManager = require(script.Parent.ConsumptionManager)
local MaintenanceManager = require(script.Parent.MaintenanceManager)
local TaxManager = require(script.Parent.TaxManager)
local SeasonManager = require(script.Parent.SeasonManager)
local WeatherManager = require(script.Parent.WeatherManager)
local TradeManager = require(script.Parent.TradeManager)
local CaravanManager = require(script.Parent.CaravanManager)
local HappinessManager = require(script.Parent.HappinessManager)
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)

local DashboardDebug = DebugManager.createChannel("EconomyDashboard", false)

local EconomyDashboardManager = {}

export type EconomySnapshot = {
	-- Resources
	resources: { [string]: number },

	-- Population
	currentPopulation: number,
	housingCapacity: number,
	populationGrowthRate: number,

	-- Consumption
	foodConsumptionRate: number,
	isStarving: boolean,
	starvationDuration: number,

	-- Production
	totalMaintenanceCost: { [string]: number },
	canAffordMaintenance: boolean,
	productionModifier: number,

	-- Taxes
	taxRate: number,
	taxRevenue: number,

	-- Happiness
	happiness: number,
	happinessFactors: { [string]: number },

	-- Environment
	currentSeason: string,
	currentWeather: string,
	seasonTimeRemaining: number,

	-- Trade
	marketPrices: { [string]: number },
	hasMarketAccess: boolean,
	activeCaravans: number,

	-- Overall Economy Health
	economyHealth: number, -- 0-100 score
	economyStatus: string, -- "Thriving", "Stable", "Struggling", "Crisis"
}

-- Calculate overall economy health score (0-100)
local function calculateEconomyHealth(player: Player): number
	local playerData = PlayerManager.get(player)
	if not playerData then
		return 50
	end

	local health = 50 -- Start neutral

	-- Resource reserves (+/- 20 points)
	local foodScore = math.clamp((playerData.Resources.Food or 0) / 100, 0, 2) * 10
	local goldScore = math.clamp((playerData.Resources.Gold or 0) / 50, 0, 2) * 10
	health = health + foodScore + goldScore

	-- Happiness (+/- 20 points)
	local happiness = playerData.Happiness or 50
	health = health + (happiness - 50) * 0.4

	-- Starvation penalty (-30 points)
	if ConsumptionManager.isStarving(player) then
		health = health - 30
	end

	-- Maintenance penalty (-15 points)
	if MaintenanceManager.isInDisrepair(player) then
		health = health - 15
	end

	-- Population bonus (+10 points if growing)
	if PopulationManager.canGrowPopulation(player) then
		health = health + 10
	end

	return math.clamp(health, 0, 100)
end

-- Get economy status string
local function getEconomyStatus(health: number): string
	if health >= 75 then
		return "Thriving"
	elseif health >= 50 then
		return "Stable"
	elseif health >= 25 then
		return "Struggling"
	else
		return "Crisis"
	end
end

-- Get full economy snapshot for a player
function EconomyDashboardManager.getSnapshot(player: Player): EconomySnapshot
	local playerData = PlayerManager.get(player)
	if not playerData then
		return {
			resources = {},
			currentPopulation = 0,
			housingCapacity = 0,
			populationGrowthRate = 0,
			foodConsumptionRate = 0,
			isStarving = false,
			starvationDuration = 0,
			totalMaintenanceCost = {},
			canAffordMaintenance = true,
			productionModifier = 1.0,
			taxRate = 0,
			taxRevenue = 0,
			happiness = 50,
			happinessFactors = {},
			currentSeason = "Spring",
			currentWeather = "Clear",
			seasonTimeRemaining = 0,
			marketPrices = {},
			hasMarketAccess = false,
			activeCaravans = 0,
			economyHealth = 50,
			economyStatus = "Stable",
		}
	end

	-- Calculate happiness factors breakdown
	local happinessFactors = {}
	local baseHappiness = 50

	-- Food factor
	local food = playerData.Resources.Food or 0
	if food > 200 then
		happinessFactors["Abundant Food"] = 25
	elseif food > 100 then
		happinessFactors["Good Food Supply"] = 15
	elseif food > 50 then
		happinessFactors["Adequate Food"] = 5
	elseif food < 10 then
		happinessFactors["Food Shortage"] = -30
	elseif food < 25 then
		happinessFactors["Low Food"] = -15
	end

	-- Starvation
	if ConsumptionManager.isStarving(player) then
		local duration = ConsumptionManager.getStarvationDuration(player)
		if duration > 120 then
			happinessFactors["Severe Starvation"] = -50
		elseif duration > 60 then
			happinessFactors["Major Starvation"] = -35
		else
			happinessFactors["Starvation"] = -20
		end
	end

	-- Overcrowding
	if PopulationManager.isOvercrowded(player) then
		happinessFactors["Overcrowding"] = -25
	end

	-- Taxes
	local taxInfo = TaxManager.get(player)
	if taxInfo then
		if taxInfo.taxRate > 0.5 then
			happinessFactors["High Taxes"] = -30
		elseif taxInfo.taxRate > 0.2 then
			happinessFactors["Moderate Taxes"] = -15
		end
	end

	-- Season
	local seasonMod = SeasonManager.getHappinessModifier(player)
	if seasonMod > 0 then
		happinessFactors["Pleasant Season"] = seasonMod
	elseif seasonMod < 0 then
		happinessFactors["Harsh Season"] = seasonMod
	end

	-- Build snapshot
	local health = calculateEconomyHealth(player)

	return {
		resources = playerData.Resources,

		currentPopulation = PopulationManager.getCurrentPopulation(player),
		housingCapacity = PopulationManager.getHousingCapacity(player),
		populationGrowthRate = PopulationManager.getGrowthRate(player),

		foodConsumptionRate = ConsumptionManager.getTotalConsumption(player),
		isStarving = ConsumptionManager.isStarving(player),
		starvationDuration = ConsumptionManager.getStarvationDuration(player),

		totalMaintenanceCost = MaintenanceManager.getMaintenanceBreakdown(player),
		canAffordMaintenance = not MaintenanceManager.isInDisrepair(player),
		productionModifier = MaintenanceManager.getDisrepairPenalty(player),

		taxRate = taxInfo and taxInfo.taxRate or 0,
		taxRevenue = taxInfo and math.floor(PopulationManager.getCurrentPopulation(player) * (taxInfo.taxRate or 0)) or 0,

		happiness = playerData.Happiness or 50,
		happinessFactors = happinessFactors,

		currentSeason = SeasonManager.getCurrentSeason(player),
		currentWeather = WeatherManager.getCurrentWeather(player),
		seasonTimeRemaining = SeasonManager.getTimeRemainingInSeason(player),

		marketPrices = TradeManager.getAllPrices(player),
		hasMarketAccess = TradeManager.hasMarketAccess(player),
		activeCaravans = #CaravanManager.getActiveCaravans(player),

		economyHealth = health,
		economyStatus = getEconomyStatus(health),
	}
end

-- Send dashboard update to client
function EconomyDashboardManager.sendUpdate(player: Player)
	local snapshot = EconomyDashboardManager.getSnapshot(player)

	-- Format data for UI
	local uiSnapshot = {
		season = snapshot.currentSeason,
		weather = snapshot.currentWeather,
		economyHealth = snapshot.economyHealth,
		foodConsumptionRate = snapshot.foodConsumptionRate,
		taxRate = math.floor((snapshot.taxRate or 0) * 100), -- Convert to percentage
		population = snapshot.currentPopulation,
		housingCapacity = snapshot.housingCapacity,
		isStarving = snapshot.isStarving,
		happiness = snapshot.happiness,
		-- Include full snapshot for advanced displays
		fullSnapshot = snapshot,
	}

	local RemoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")
	if RemoteEvents then
		local GameEvent = RemoteEvents:FindFirstChild("GameEvent")
		if GameEvent then
			GameEvent:FireClient(player, "EconomyDashboardUpdate", { snapshot = uiSnapshot })
			DashboardDebug:info(`Sent dashboard update to {player.Name}`)
		end
	end
end

-- Initialize the dashboard system
function EconomyDashboardManager.init()
	DashboardDebug:info("EconomyDashboardManager initialized")
end

return EconomyDashboardManager
