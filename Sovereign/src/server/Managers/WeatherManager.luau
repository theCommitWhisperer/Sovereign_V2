--!strict
-- WeatherManager: Manages weather conditions and their effects on production

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerManager = require(script.Parent.PlayerManager)
local SeasonManager = require(script.Parent.SeasonManager)
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)

local WeatherDebug = DebugManager.createChannel("WeatherManager", false)

local WeatherManager = {}

-- Track weather data per player
local weatherData = {}

export type WeatherType = "Clear" | "Rain" | "Drought" | "Storm"

export type WeatherData = {
	currentWeather: WeatherType,
	weatherStartTime: number,
	weatherDuration: number,
}

export type WeatherEffects = {
	farmProductionMultiplier: number,
	miningProductionMultiplier: number,
	description: string,
}

-- Weather effects
local WEATHER_EFFECTS: { [WeatherType]: WeatherEffects } = {
	Clear = {
		farmProductionMultiplier = 1.0,
		miningProductionMultiplier = 1.0,
		description = "Clear skies and good working conditions.",
	},
	Rain = {
		farmProductionMultiplier = 1.2, -- Rain helps farms
		miningProductionMultiplier = 0.7, -- Rain hinders mining
		description = "Rain nourishes crops but slows outdoor work.",
	},
	Drought = {
		farmProductionMultiplier = 0.6, -- Drought devastates farms
		miningProductionMultiplier = 1.1, -- Easier to mine in dry conditions
		description = "Drought withers crops and strains the settlement.",
	},
	Storm = {
		farmProductionMultiplier = 0.8,
		miningProductionMultiplier = 0.5, -- Storms halt all work
		description = "Severe storms disrupt all production!",
	},
}

-- Weather probability by season
local WEATHER_PROBABILITIES = {
	Spring = {
		Clear = 0.5,
		Rain = 0.4,
		Drought = 0.05,
		Storm = 0.05,
	},
	Summer = {
		Clear = 0.6,
		Rain = 0.2,
		Drought = 0.15,
		Storm = 0.05,
	},
	Autumn = {
		Clear = 0.4,
		Rain = 0.4,
		Drought = 0.1,
		Storm = 0.1,
	},
	Winter = {
		Clear = 0.3,
		Rain = 0.2,
		Drought = 0.05,
		Storm = 0.45, -- Lots of winter storms!
	},
}

-- Initialize weather data for a player
function WeatherManager.create(player: Player)
	weatherData[player.UserId] = {
		currentWeather = "Clear",
		weatherStartTime = tick(),
		weatherDuration = math.random(60, 120), -- Weather lasts 1-2 minutes
	}
	WeatherDebug:info(`Created weather data for {player.Name} - Starting with Clear weather`)
end

-- Get weather data for a player
function WeatherManager.get(player: Player): WeatherData?
	return weatherData[player.UserId]
end

-- Get current weather for a player
function WeatherManager.getCurrentWeather(player: Player): WeatherType
	local data = weatherData[player.UserId]
	if not data then
		return "Clear"
	end
	return data.currentWeather
end

-- Get weather effects for current weather
function WeatherManager.getWeatherEffects(player: Player): WeatherEffects
	local weather = WeatherManager.getCurrentWeather(player)
	return WEATHER_EFFECTS[weather]
end

-- Get farm production multiplier (combines weather + season)
function WeatherManager.getFarmProductionMultiplier(player: Player): number
	local weatherEffects = WeatherManager.getWeatherEffects(player)
	local seasonalMultiplier = SeasonManager.getFarmProductionMultiplier(player)

	-- Multiply seasonal and weather effects
	return weatherEffects.farmProductionMultiplier * seasonalMultiplier
end

-- Get mining production multiplier
function WeatherManager.getMiningProductionMultiplier(player: Player): number
	local weatherEffects = WeatherManager.getWeatherEffects(player)
	return weatherEffects.miningProductionMultiplier
end

-- Change weather based on seasonal probabilities
function WeatherManager.changeWeather(player: Player)
	local data = weatherData[player.UserId]
	if not data then
		return
	end

	local currentSeason = SeasonManager.getCurrentSeason(player)
	local probabilities = WEATHER_PROBABILITIES[currentSeason]

	-- Roll for new weather
	local roll = math.random()
	local cumulative = 0
	local newWeather: WeatherType = "Clear"

	for weather, probability in pairs(probabilities) do
		cumulative += probability
		if roll <= cumulative then
			newWeather = weather :: WeatherType
			break
		end
	end

	data.currentWeather = newWeather
	data.weatherStartTime = tick()
	data.weatherDuration = math.random(60, 120)

	WeatherDebug:info(`{player.Name} weather changed to {newWeather}`)

	-- Notify client
	local RemoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")
	if RemoteEvents then
		local GameEvent = RemoteEvents:FindFirstChild("GameEvent")
		if GameEvent then
			local effects = WEATHER_EFFECTS[newWeather]
			GameEvent:FireClient(player, "WeatherChanged", {
				weather = newWeather,
				description = effects.description,
				effects = {
					farmProduction = effects.farmProductionMultiplier,
					miningProduction = effects.miningProductionMultiplier,
				},
			})
		end
	end
end

-- Update weather progression
function WeatherManager.update(player: Player)
	local data = weatherData[player.UserId]
	if not data then
		return
	end

	local currentTime = tick()
	local timeInWeather = currentTime - data.weatherStartTime

	-- Check if weather should change
	if timeInWeather >= data.weatherDuration then
		WeatherManager.changeWeather(player)
	end
end

-- Initialize the weather system
function WeatherManager.init()
	Players.PlayerAdded:Connect(WeatherManager.create)

	WeatherDebug:info("WeatherManager initialized")
end

return WeatherManager
