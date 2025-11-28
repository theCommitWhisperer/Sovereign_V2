--!strict
-- SeasonSystem: Handles periodic season updates and progression

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SeasonManager = require(script.Parent.Parent.Managers.SeasonManager)
local PlayerManager = require(script.Parent.Parent.Managers.PlayerManager)
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)

local SeasonSystemDebug = DebugManager.createChannel("SeasonSystem", false)

local SeasonSystem = {}

-- Season update interval (in seconds)
local SEASON_UPDATE_INTERVAL = 10 -- Check season progression every 10 seconds

-- Update seasons for a player
local function updateSeasons(player: Player)
	local playerData = PlayerManager.get(player)
	if not playerData or playerData.GameState ~= "InGame" then
		return
	end

	-- Update season progression
	SeasonManager.update(player)
end

-- Initialize the season system
function SeasonSystem.init()
	-- Update seasons periodically for all players
	task.spawn(function()
		while true do
			task.wait(SEASON_UPDATE_INTERVAL)
			for _, player in ipairs(Players:GetPlayers()) do
				updateSeasons(player)
			end
		end
	end)

	SeasonSystemDebug:info(`SeasonSystem initialized - updating every {SEASON_UPDATE_INTERVAL} seconds`)
end

return SeasonSystem
