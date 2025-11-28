--!strict
-- MaintenanceSystem: Handles periodic building maintenance payments

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MaintenanceManager = require(script.Parent.Parent.Managers.MaintenanceManager)
local PlayerManager = require(script.Parent.Parent.Managers.PlayerManager)
local WorkerManager = require(script.Parent.Parent.Managers.WorkerManager)
local NotificationManager = require(script.Parent.Parent.Managers.NotificationManager)
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)

local MaintenanceSystemDebug = DebugManager.createChannel("MaintenanceSystem", false)

local MaintenanceSystem = {}

-- Maintenance cycle time (in seconds) - pay maintenance every 60 seconds
local MAINTENANCE_CYCLE = 60

-- Process maintenance for a player
local function processMaintenance(player: Player)
	local playerData = PlayerManager.get(player)
	if not playerData or playerData.GameState ~= "InGame" then
		return
	end

	-- Pay maintenance
	local success = MaintenanceManager.payMaintenance(player)

	if success then
		MaintenanceSystemDebug:info(`{player.Name} paid maintenance successfully`)

		-- Restore production if it was penalized
		local penalty = MaintenanceManager.getDisrepairPenalty(player)
		if penalty == 1.0 then
			-- Full production restored (if not affected by happiness/revolts)
			-- Note: We don't override production modifier here since HappinessManager might have set it
			MaintenanceSystemDebug:info(`{player.Name} buildings are in good repair`)
		end
	else
		MaintenanceSystemDebug:warn(`{player.Name} FAILED to pay maintenance!`)

		-- Apply disrepair penalty to production
		local penalty = MaintenanceManager.getDisrepairPenalty(player)
		local disrepairLevel = MaintenanceManager.get(player).buildingsInDisrepair
		MaintenanceSystemDebug:warn(`{player.Name} production reduced to {penalty * 100}% due to disrepair`)

		-- Send notifications based on disrepair severity
		if disrepairLevel == 1 then
			NotificationManager.warning(player, "Maintenance Failed", "Buildings are starting to fall into disrepair. Production reduced to 75%.")
		elseif disrepairLevel == 2 then
			NotificationManager.alert(player, "Major Disrepair", "Buildings are in bad condition! Production reduced to 50%.")
		elseif disrepairLevel >= 3 then
			NotificationManager.critical(player, "Severe Disrepair!", "Buildings are crumbling! Production at 25%. Fix immediately!")
		end

		-- Apply penalty to worker production
		WorkerManager.setProductionModifier(player, penalty)
	end
end

-- Initialize the maintenance system
function MaintenanceSystem.init()
	-- Process maintenance every 60 seconds for all players
	task.spawn(function()
		while true do
			task.wait(MAINTENANCE_CYCLE)
			for _, player in ipairs(Players:GetPlayers()) do
				processMaintenance(player)
			end
		end
	end)

	MaintenanceSystemDebug:info(`MaintenanceSystem initialized - collecting maintenance every {MAINTENANCE_CYCLE} seconds`)
end

return MaintenanceSystem
