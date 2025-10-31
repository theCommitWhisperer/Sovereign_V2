--!strict
-- WeatherSystem: Handles periodic weather updates

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeatherManager = require(script.Parent.Parent.Managers.WeatherManager)
local PlayerManager = require(script.Parent.Parent.Managers.PlayerManager)
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)

local WeatherSystemDebug = DebugManager.createChannel("WeatherSystem", true)

local WeatherSystem = {}

-- Weather update interval (in seconds)
local WEATHER_UPDATE_INTERVAL = 15 -- Check weather every 15 seconds

-- Update weather for a player
local function updateWeather(player: Player)
	local playerData = PlayerManager.get(player)
	if not playerData or playerData.GameState ~= "InGame" then
		return
	end

	-- Update weather progression
	WeatherManager.update(player)
end

-- Initialize the weather system
function WeatherSystem.init()
	-- Update weather periodically for all players
	task.spawn(function()
		while true do
			task.wait(WEATHER_UPDATE_INTERVAL)
			for _, player in ipairs(Players:GetPlayers()) do
				updateWeather(player)
			end
		end
	end)

	WeatherSystemDebug:info(`WeatherSystem initialized - updating every {WEATHER_UPDATE_INTERVAL} seconds`)
end

return WeatherSystem
