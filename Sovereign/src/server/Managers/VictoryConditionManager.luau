--!strict
-- VictoryConditionManager: Manages win/loss conditions and economic objectives

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerManager = require(script.Parent.PlayerManager)
local PopulationManager = require(script.Parent.PopulationManager)
local CaravanManager = require(script.Parent.CaravanManager)
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)

local VictoryDebug = DebugManager.createChannel("VictoryCondition", false)

local VictoryConditionManager = {}

-- Track victory/loss state per player
local victoryData = {}

-- Active victory mode (set from lobby settings)
-- "Conquest"  → military: destroy all enemy keeps (falls back to economic in solo play)
-- "Wonder"    → build the Wonder structure and hold it
-- "Score"     → reach economic targets (default economic conditions)
-- "Regicide"  → kill the enemy lord
local activeVictoryMode = "Score" -- default

export type VictoryData = {
	hasWon: boolean,
	hasLost: boolean,
	victoryType: string?,
	lossReason: string?,
	achievedConditions: { string },
	gameStartTime: number?,
	peaceTimeSeconds: number,
}

export type VictoryCondition = {
	name: string,
	description: string,
	check: (player: Player) -> boolean,
}

export type LossCondition = {
	name: string,
	description: string,
	check: (player: Player) -> boolean,
}

-- Define victory conditions
local VICTORY_CONDITIONS: { VictoryCondition } = {
	{
		name = "Economic Prosperity",
		description = "Accumulate 1000 Gold",
		check = function(player: Player)
			local playerData = PlayerManager.get(player)
			return playerData and (playerData.Resources.Gold or 0) >= 1000
		end,
	},
	{
		name = "Population Boom",
		description = "Reach 50 population",
		check = function(player: Player)
			return PopulationManager.getCurrentPopulation(player) >= 50
		end,
	},
	{
		name = "Trade Empire",
		description = "Complete 20 successful trade caravans",
		check = function(player: Player)
			local caravanData = CaravanManager.get(player)
			return caravanData and caravanData.completedTrades >= 20
		end,
	},
	{
		name = "Resource Hoarder",
		description = "Have 500+ of each basic resource (Wood, Stone, Food)",
		check = function(player: Player)
			local playerData = PlayerManager.get(player)
			if not playerData then
				return false
			end
			return (playerData.Resources.Wood or 0) >= 500
				and (playerData.Resources.Stone or 0) >= 500
				and (playerData.Resources.Food or 0) >= 500
		end,
	},
	{
		name = "Industrial Titan",
		description = "Have 100+ Weapons and 100+ Iron Bars",
		check = function(player: Player)
			local playerData = PlayerManager.get(player)
			if not playerData then
				return false
			end
			return (playerData.Resources.Weapons or 0) >= 100
				and (playerData.Resources.Iron_Bars or 0) >= 100
		end,
	},
}

-- Define loss conditions
local LOSS_CONDITIONS: { LossCondition } = {
	{
		name = "Economic Collapse",
		description = "Have 0 gold, 0 food, and cannot produce either",
		check = function(player: Player)
			local playerData = PlayerManager.get(player)
			if not playerData then
				return false
			end

			local noGold = (playerData.Resources.Gold or 0) == 0
			local noFood = (playerData.Resources.Food or 0) == 0

			-- Check if player has any farms or gold-generating buildings
			local hasFarms = false
			for _, building in playerData.Buildings do
				if building and building.Parent then
					local buildingType = building:GetAttribute("BuildingType")
					if buildingType == "Farm" then
						hasFarms = true
						break
					end
				end
			end

			return noGold and noFood and not hasFarms
		end,
	},
	{
		name = "Population Extinction",
		description = "All peasants have died or left",
		check = function(player: Player)
			local population = PopulationManager.getCurrentPopulation(player)
			return population == 0
		end,
	},
	{
		name = "Keep Destroyed",
		description = "Your Keep has been destroyed",
		check = function(player: Player)
			local playerData = PlayerManager.get(player)
			if not playerData then
				return false
			end

			-- Only fires when the player HAD a Keep (not nil) but it has been removed.
			-- Keep=nil means the Keep was never placed yet, which is not a loss.
			return playerData.Keep ~= nil and not playerData.Keep.Parent
		end,
	},
	{
		name = "Prolonged Starvation",
		description = "Starving for more than 5 minutes straight",
		check = function(player: Player)
			local ConsumptionManager = require(script.Parent.ConsumptionManager)
			local starvationDuration = ConsumptionManager.getStarvationDuration(player)
			return starvationDuration >= 300 -- 5 minutes
		end,
	},
}

-- Initialize victory data for a player
function VictoryConditionManager.create(player: Player)
	victoryData[player.UserId] = {
		hasWon = false,
		hasLost = false,
		victoryType = nil,
		lossReason = nil,
		achievedConditions = {},
		gameStartTime = nil,
		peaceTimeSeconds = 0,
	}
	VictoryDebug:info(`Created victory data for {player.Name}`)
end

-- Set the victory mode from the lobby setting
-- This determines which victory conditions are active
function VictoryConditionManager.setVictoryMode(mode: string)
	activeVictoryMode = mode or "Score"
	VictoryDebug:info(`Victory mode set to: {activeVictoryMode}`)
end

-- Get the subset of victory conditions active for the current mode
local function getActiveVictoryConditions(): { VictoryCondition }
	-- Score mode uses all economic victory conditions
	if activeVictoryMode == "Score" then
		return VICTORY_CONDITIONS
	end

	-- Conquest mode: win by destroying all enemy keeps
	-- In single-player/sandbox there are no enemies yet, so fall back to economic
	if activeVictoryMode == "Conquest" then
		-- Filter to military-relevant conditions; fall back to all if none apply
		local military = {}
		for _, c in VICTORY_CONDITIONS do
			if c.name == "Industrial Titan" then
				table.insert(military, c)
			end
		end
		return #military > 0 and military or VICTORY_CONDITIONS
	end

	-- Regicide mode: defeat the enemy lord (lord/hero unit kill)
	-- Not yet implemented - fall back to Score
	if activeVictoryMode == "Regicide" then
		return VICTORY_CONDITIONS
	end

	-- Wonder mode: build and hold a Wonder building
	-- Not yet implemented - fall back to Score
	if activeVictoryMode == "Wonder" then
		return VICTORY_CONDITIONS
	end

	return VICTORY_CONDITIONS
end

-- Called when the game actually starts so defeat checks respect the lobby's peace time setting
function VictoryConditionManager.setGameStarted(player: Player, peaceTimeSeconds: number)
	local data = victoryData[player.UserId]
	if data then
		data.gameStartTime = tick()
		data.peaceTimeSeconds = peaceTimeSeconds
		VictoryDebug:info(`{player.Name} game started — peace time: {peaceTimeSeconds}s`)
	end
end

-- Get victory data for a player
function VictoryConditionManager.get(player: Player): VictoryData?
	return victoryData[player.UserId]
end

-- Check all victory conditions
function VictoryConditionManager.checkVictory(player: Player)
	local data = victoryData[player.UserId]
	local playerData = PlayerManager.get(player)

	if not data or not playerData or playerData.GameState ~= "InGame" then
		return
	end

	-- Don't check if already won/lost
	if data.hasWon or data.hasLost then
		return
	end

	-- Check victory conditions (filtered by active mode)
	for _, condition in getActiveVictoryConditions() do
		if condition.check(player) and not table.find(data.achievedConditions, condition.name) then
			table.insert(data.achievedConditions, condition.name)

			-- First victory condition = win!
			if not data.hasWon then
				data.hasWon = true
				data.victoryType = condition.name

				VictoryDebug:info(`{player.Name} achieved VICTORY: {condition.name}!`)

				-- Notify client
				local RemoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")
				if RemoteEvents then
					local GameEvent = RemoteEvents:FindFirstChild("GameEvent")
					if GameEvent then
						pcall(function()
							local AchievementManager = require(script.Parent.AchievementManager) :: any
							GameEvent:FireClient(player, "Victory", {
								victoryType = condition.name,
								description = condition.description,
								stats = AchievementManager.getMatchSnapshot(player, data.gameStartTime),
							})
						end)
					end
				end
			end
		end
	end
end

-- Check all loss conditions
function VictoryConditionManager.checkDefeat(player: Player)
	local data = victoryData[player.UserId]
	local playerData = PlayerManager.get(player)

	if not data or not playerData or playerData.GameState ~= "InGame" then
		return
	end

	-- Don't check if already won/lost
	if data.hasWon or data.hasLost then
		return
	end

	-- Respect the lobby's peace time setting — no defeat checks until it expires
	if data.gameStartTime and data.peaceTimeSeconds > 0 then
		if tick() - data.gameStartTime < data.peaceTimeSeconds then
			return
		end
	end

	-- Check loss conditions
	for _, condition in LOSS_CONDITIONS do
		if condition.check(player) then
			data.hasLost = true
			data.lossReason = condition.name

			VictoryDebug:warn(`{player.Name} suffered DEFEAT: {condition.name}!`)

			-- Notify client
			local RemoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")
			if RemoteEvents then
				local GameEvent = RemoteEvents:FindFirstChild("GameEvent")
				if GameEvent then
					pcall(function()
						local AchievementManager = require(script.Parent.AchievementManager) :: any
						GameEvent:FireClient(player, "Defeat", {
							lossReason = condition.name,
							description = condition.description,
							stats = AchievementManager.getMatchSnapshot(player, data.gameStartTime),
						})
					end)
				end
			end

			break -- Only one loss reason
		end
	end
end

-- Get all victory conditions for UI display
function VictoryConditionManager.getVictoryConditions(): { VictoryCondition }
	return VICTORY_CONDITIONS
end

-- Get all loss conditions for UI display
function VictoryConditionManager.getLossConditions(): { LossCondition }
	return LOSS_CONDITIONS
end

-- Initialize the victory system
function VictoryConditionManager.init()
	Players.PlayerAdded:Connect(VictoryConditionManager.create)

	VictoryDebug:info("VictoryConditionManager initialized")
end

return VictoryConditionManager
