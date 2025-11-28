--!strict
-- DashboardSystem: Handles periodic economy dashboard updates

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EconomyDashboardManager = require(script.Parent.Parent.Managers.EconomyDashboardManager)
local PlayerManager = require(script.Parent.Parent.Managers.PlayerManager)
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)

local DashboardSystemDebug = DebugManager.createChannel("DashboardSystem", true)

local DashboardSystem = {}

-- Dashboard update interval (in seconds)
local DASHBOARD_UPDATE_INTERVAL = 5 -- Update UI every 5 seconds

-- Send dashboard update for a player
local function updateDashboard(player: Player)
	local playerData = PlayerManager.get(player)
	if not playerData or playerData.GameState ~= "InGame" then
		return
	end

	-- Send economy snapshot to client
	EconomyDashboardManager.sendUpdate(player)
end

-- Initialize the dashboard system
function DashboardSystem.init()
	-- Send immediate update when player enters game
	Players.PlayerAdded:Connect(function(player)
		task.wait(0.5) -- Brief delay to ensure player data is ready
		updateDashboard(player)
	end)

	-- Update dashboard periodically for all players
	task.spawn(function()
		while true do
			task.wait(DASHBOARD_UPDATE_INTERVAL)
			for _, player in ipairs(Players:GetPlayers()) do
				updateDashboard(player)
			end
		end
	end)

	DashboardSystemDebug:info(`DashboardSystem initialized - updating every {DASHBOARD_UPDATE_INTERVAL} seconds`)
end

return DashboardSystem
