--!strict
-- MaintenanceManager: Manages building maintenance costs and upkeep

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerManager = require(script.Parent.PlayerManager)
local BuildingManager = require(script.Parent.BuildingManager)
local GameData = require(ReplicatedStorage.Shared.GameData)
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)

local MaintenanceDebug = DebugManager.createChannel("MaintenanceManager", false)

local MaintenanceManager = {}

-- Track maintenance data per player
local maintenanceData = {}

export type MaintenanceData = {
	lastMaintenanceTime: number,
	totalMaintenanceCost: { [string]: number },
	cannotAfford: boolean,
	buildingsInDisrepair: number,
}

-- Initialize maintenance data for a player
function MaintenanceManager.create(player: Player)
	maintenanceData[player.UserId] = {
		lastMaintenanceTime = tick(),
		totalMaintenanceCost = {},
		cannotAfford = false,
		buildingsInDisrepair = 0,
	}
	MaintenanceDebug:info(`Created maintenance data for {player.Name}`)
end

-- Get maintenance data for a player
function MaintenanceManager.get(player: Player): MaintenanceData?
	return maintenanceData[player.UserId]
end

-- Calculate total maintenance cost for all buildings
function MaintenanceManager.calculateMaintenanceCost(player: Player): { [string]: number }
	local playerData = PlayerManager.get(player)
	if not playerData then
		return {}
	end

	local totalCost: { [string]: number } = {}

	for _, building in playerData.Buildings do
		if building and building.Parent then
			local buildingType = building:GetAttribute("BuildingType")
			local buildingData = GameData.Buildings[buildingType]

			if buildingData and buildingData.maintenance_cost then
				-- Add maintenance costs
				for resource, amount in pairs(buildingData.maintenance_cost) do
					totalCost[resource] = (totalCost[resource] or 0) + amount
				end
			end
		end
	end

	return totalCost
end

-- Process maintenance payment for a player
function MaintenanceManager.payMaintenance(player: Player): boolean
	local playerData = PlayerManager.get(player)
	local maintData = maintenanceData[player.UserId]

	if not playerData or not maintData then
		return false
	end

	local maintenanceCost = MaintenanceManager.calculateMaintenanceCost(player)
	maintData.totalMaintenanceCost = maintenanceCost

	-- Check if player can afford maintenance
	local canAfford = true
	for resource, amount in pairs(maintenanceCost) do
		if (playerData.Resources[resource] or 0) < amount then
			canAfford = false
			break
		end
	end

	if canAfford then
		-- Deduct maintenance costs
		for resource, amount in pairs(maintenanceCost) do
			PlayerManager.deductResources(player, { [resource] = amount })
		end

		maintData.cannotAfford = false
		maintData.buildingsInDisrepair = 0
		maintData.lastMaintenanceTime = tick()

		MaintenanceDebug:info(`{player.Name} paid maintenance successfully`)

		-- Notify client
		local RemoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")
		if RemoteEvents then
			local GameEvent = RemoteEvents:FindFirstChild("GameEvent")
			if GameEvent then
				GameEvent:FireClient(player, "MaintenancePaid", {
					cost = maintenanceCost,
				})
			end
		end

		return true
	else
		-- Cannot afford maintenance!
		maintData.cannotAfford = true
		maintData.buildingsInDisrepair += 1

		MaintenanceDebug:warn(`{player.Name} CANNOT AFFORD MAINTENANCE!`)

		-- Notify client of maintenance failure
		local RemoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")
		if RemoteEvents then
			local GameEvent = RemoteEvents:FindFirstChild("GameEvent")
			if GameEvent then
				GameEvent:FireClient(player, "MaintenanceFailure", {
					needed = maintenanceCost,
					available = playerData.Resources,
					buildingsInDisrepair = maintData.buildingsInDisrepair,
				})
			end
		end

		return false
	end
end

-- Check if player is in disrepair (affects production)
function MaintenanceManager.isInDisrepair(player: Player): boolean
	local maintData = maintenanceData[player.UserId]
	if not maintData then
		return false
	end
	return maintData.cannotAfford
end

-- Get disrepair penalty multiplier (0.5 = 50% production if in disrepair)
function MaintenanceManager.getDisrepairPenalty(player: Player): number
	local maintData = maintenanceData[player.UserId]
	if not maintData then
		return 1.0
	end

	if maintData.buildingsInDisrepair >= 3 then
		return 0.25 -- Severe disrepair after 3 failed payments (3 minutes)
	elseif maintData.buildingsInDisrepair >= 2 then
		return 0.5 -- Major disrepair after 2 failed payments
	elseif maintData.buildingsInDisrepair >= 1 then
		return 0.75 -- Minor disrepair after 1 failed payment
	end

	return 1.0 -- No penalty
end

-- Get maintenance cost breakdown for UI
function MaintenanceManager.getMaintenanceBreakdown(player: Player): { [string]: number }
	return MaintenanceManager.calculateMaintenanceCost(player)
end

-- Initialize the maintenance system
function MaintenanceManager.init()
	Players.PlayerAdded:Connect(MaintenanceManager.create)

	MaintenanceDebug:info("MaintenanceManager initialized")
end

return MaintenanceManager
