--!strict
-- VictorySystem: Handles periodic victory/defeat checks

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VictoryConditionManager = require(script.Parent.Parent.Managers.VictoryConditionManager)
local PlayerManager = require(script.Parent.Parent.Managers.PlayerManager)
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)

local VictorySystemDebug = DebugManager.createChannel("VictorySystem", true)

local VictorySystem = {}

-- Victory check interval (in seconds)
local VICTORY_CHECK_INTERVAL = 10 -- Check every 10 seconds

-- Check victory/defeat conditions for a player
local function checkConditions(player: Player)
	local playerData = PlayerManager.get(player)
	if not playerData or playerData.GameState ~= "InGame" then
		return
	end

	-- Check for victory
	VictoryConditionManager.checkVictory(player)

	-- Check for defeat
	VictoryConditionManager.checkDefeat(player)
end

-- Initialize the victory system
function VictorySystem.init()
	-- Check conditions periodically for all players
	task.spawn(function()
		while true do
			task.wait(VICTORY_CHECK_INTERVAL)
			for _, player in ipairs(Players:GetPlayers()) do
				checkConditions(player)
			end
		end
	end)

	VictorySystemDebug:info(`VictorySystem initialized - checking every {VICTORY_CHECK_INTERVAL} seconds`)
end

return VictorySystem
