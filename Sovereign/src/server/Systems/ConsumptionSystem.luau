--!strict
-- ConsumptionSystem: Handles periodic food consumption checks

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ConsumptionManager = require(script.Parent.Parent.Managers.ConsumptionManager)
local PlayerManager = require(script.Parent.Parent.Managers.PlayerManager)
local NotificationManager = require(script.Parent.Parent.Managers.NotificationManager)
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)

local ConsumptionSystemDebug = DebugManager.createChannel("ConsumptionSystem", true)

local ConsumptionSystem = {}

-- Consumption cycle time (in seconds)
local CONSUMPTION_CYCLE = 30 -- Food consumed every 30 seconds

-- Process food consumption for a player
local function processConsumption(player: Player)
	local playerData = PlayerManager.get(player)
	if not playerData or playerData.GameState ~= "InGame" then
		return
	end

	-- Consume food
	local success = ConsumptionManager.consumeFood(player)

	if success then
		ConsumptionSystemDebug:info(`{player.Name} consumed food successfully`)
	else
		ConsumptionSystemDebug:warn(`{player.Name} is STARVING - not enough food!`)

		-- Get starvation effects
		local starvationDuration = ConsumptionManager.getStarvationDuration(player)

		-- Send notifications based on starvation duration
		if starvationDuration == 30 then
			-- First starvation cycle
			NotificationManager.critical(player, "STARVATION!", "Your people are starving! Produce or buy food immediately!")
		elseif starvationDuration == 60 then
			NotificationManager.critical(player, "Prolonged Starvation", "Your people have been starving for 1 minute. Severe consequences imminent!")
		elseif starvationDuration >= 120 then
			-- Extreme starvation effects (after 120 seconds)
			ConsumptionSystemDebug:error(`{player.Name} has been starving for {starvationDuration}s - severe consequences!`)
			NotificationManager.critical(player, "Mass Starvation", "Your people are dying from starvation! This is catastrophic!")
		end
	end
end

-- Initialize the consumption system
function ConsumptionSystem.init()
	-- Process food consumption every 30 seconds for all players
	task.spawn(function()
		while true do
			task.wait(CONSUMPTION_CYCLE)
			for _, player in ipairs(Players:GetPlayers()) do
				processConsumption(player)
			end
		end
	end)

	ConsumptionSystemDebug:info(`ConsumptionSystem initialized - consuming food every {CONSUMPTION_CYCLE} seconds`)
end

return ConsumptionSystem
