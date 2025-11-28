--!strict
-- CaravanSystem: Handles periodic caravan updates

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CaravanManager = require(script.Parent.Parent.Managers.CaravanManager)
local PlayerManager = require(script.Parent.Parent.Managers.PlayerManager)
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)

local CaravanSystemDebug = DebugManager.createChannel("CaravanSystem", true)

local CaravanSystem = {}

-- Caravan update interval (in seconds)
local CARAVAN_UPDATE_INTERVAL = 5 -- Check caravans every 5 seconds

-- Update caravans for a player
local function updateCaravans(player: Player)
	local playerData = PlayerManager.get(player)
	if not playerData or playerData.GameState ~= "InGame" then
		return
	end

	-- Update caravan progress
	CaravanManager.update(player)
end

-- Initialize the caravan system
function CaravanSystem.init()
	-- Update caravans periodically for all players
	task.spawn(function()
		while true do
			task.wait(CARAVAN_UPDATE_INTERVAL)
			for _, player in ipairs(Players:GetPlayers()) do
				updateCaravans(player)
			end
		end
	end)

	CaravanSystemDebug:info(`CaravanSystem initialized - updating every {CARAVAN_UPDATE_INTERVAL} seconds`)
end

return CaravanSystem
