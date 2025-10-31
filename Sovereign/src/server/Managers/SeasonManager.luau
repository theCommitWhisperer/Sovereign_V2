--!strict
-- SeasonManager: Manages seasons and their economic effects

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerManager = require(script.Parent.PlayerManager)
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)

local SeasonDebug = DebugManager.createChannel("SeasonManager", true)

local SeasonManager = {}

-- Track season data per player
local seasonData = {}

export type Season = "Spring" | "Summer" | "Autumn" | "Winter"

export type SeasonData = {
	currentSeason: Season,
	seasonStartTime: number,
	seasonDuration: number, -- seconds
	daysSinceStart: number,
}

export type SeasonEffects = {
	foodConsumptionMultiplier: number,
	farmProductionMultiplier: number,
	happinessModifier: number,
	description: string,
}

-- Season effects
local SEASON_EFFECTS: { [Season]: SeasonEffects } = {
	Spring = {
		foodConsumptionMultiplier = 1.0,
		farmProductionMultiplier = 1.2, -- Farms produce 20% more
		happinessModifier = 5, -- People are happy in spring
		description = "Spring brings growth and renewal. Farms produce more.",
	},
	Summer = {
		foodConsumptionMultiplier = 0.9, -- Less food needed in warm weather
		farmProductionMultiplier = 1.3, -- Peak harvest season
		happinessModifier = 10, -- People love summer
		description = "Summer is peak harvest season. Food production at maximum.",
	},
	Autumn = {
		foodConsumptionMultiplier = 1.1, -- Preparing for winter
		farmProductionMultiplier = 0.9, -- Harvest winding down
		happinessModifier = 0, -- Neutral
		description = "Autumn harvest dwindles. Prepare for winter.",
	},
	Winter = {
		foodConsumptionMultiplier = 1.4, -- Much more food needed for warmth
		farmProductionMultiplier = 0.5, -- Very little farm production
		happinessModifier = -10, -- People are cold and unhappy
		description = "Winter is harsh. Food consumption increases, production drops.",
	},
}

-- Season duration (in real-time seconds)
local SEASON_DURATION = 180 -- 3 minutes per season = 12 minutes per year

-- Initialize season data for a player
function SeasonManager.create(player: Player)
	seasonData[player.UserId] = {
		currentSeason = "Spring", -- Always start in Spring
		seasonStartTime = tick(),
		seasonDuration = SEASON_DURATION,
		daysSinceStart = 0,
	}
	SeasonDebug:info(`Created season data for {player.Name} - Starting in Spring`)
end

-- Get season data for a player
function SeasonManager.get(player: Player): SeasonData?
	return seasonData[player.UserId]
end

-- Get current season for a player
function SeasonManager.getCurrentSeason(player: Player): Season
	local data = seasonData[player.UserId]
	if not data then
		return "Spring"
	end
	return data.currentSeason
end

-- Get season effects for current season
function SeasonManager.getSeasonEffects(player: Player): SeasonEffects
	local season = SeasonManager.getCurrentSeason(player)
	return SEASON_EFFECTS[season]
end

-- Get food consumption multiplier for current season
function SeasonManager.getFoodConsumptionMultiplier(player: Player): number
	local effects = SeasonManager.getSeasonEffects(player)
	return effects.foodConsumptionMultiplier
end

-- Get farm production multiplier for current season
function SeasonManager.getFarmProductionMultiplier(player: Player): number
	local effects = SeasonManager.getSeasonEffects(player)
	return effects.farmProductionMultiplier
end

-- Get happiness modifier for current season
function SeasonManager.getHappinessModifier(player: Player): number
	local effects = SeasonManager.getSeasonEffects(player)
	return effects.happinessModifier
end

-- Advance to next season
function SeasonManager.advanceSeason(player: Player)
	local data = seasonData[player.UserId]
	if not data then
		return
	end

	-- Determine next season
	local seasonOrder: { Season } = { "Spring", "Summer", "Autumn", "Winter" }
	local currentIndex = 1
	for i, season in ipairs(seasonOrder) do
		if season == data.currentSeason then
			currentIndex = i
			break
		end
	end

	local nextIndex = (currentIndex % 4) + 1
	local nextSeason = seasonOrder[nextIndex]

	data.currentSeason = nextSeason
	data.seasonStartTime = tick()
	data.daysSinceStart = 0

	SeasonDebug:info(`{player.Name} advanced to {nextSeason}`)

	-- Notify client of season change
	local RemoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")
	if RemoteEvents then
		local GameEvent = RemoteEvents:FindFirstChild("GameEvent")
		if GameEvent then
			local effects = SEASON_EFFECTS[nextSeason]
			GameEvent:FireClient(player, "SeasonChanged", {
				season = nextSeason,
				description = effects.description,
				effects = {
					foodConsumption = effects.foodConsumptionMultiplier,
					farmProduction = effects.farmProductionMultiplier,
					happiness = effects.happinessModifier,
				},
			})
		end
	end
end

-- Update season progression
function SeasonManager.update(player: Player)
	local data = seasonData[player.UserId]
	if not data then
		return
	end

	local currentTime = tick()
	local timeInSeason = currentTime - data.seasonStartTime

	-- Check if season should advance
	if timeInSeason >= data.seasonDuration then
		SeasonManager.advanceSeason(player)
	else
		-- Calculate "days" for flavor (1 day = 15 seconds in-game)
		data.daysSinceStart = math.floor(timeInSeason / 15)
	end
end

-- Get time remaining in current season (in seconds)
function SeasonManager.getTimeRemainingInSeason(player: Player): number
	local data = seasonData[player.UserId]
	if not data then
		return 0
	end

	local currentTime = tick()
	local timeInSeason = currentTime - data.seasonStartTime
	return math.max(0, data.seasonDuration - timeInSeason)
end

-- Initialize the season system
function SeasonManager.init()
	Players.PlayerAdded:Connect(SeasonManager.create)

	SeasonDebug:info("SeasonManager initialized")
end

return SeasonManager
