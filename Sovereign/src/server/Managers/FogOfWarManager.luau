--!strict
-- FogOfWarManager: Controls visibility of units and buildings based on vision range
-- Can be toggled on/off by admins for testing

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local DebugManager = require(ReplicatedStorage.Shared.DebugManager)
local FogDebug = DebugManager.createChannel("FogOfWar", false) -- Enable debug

local FogOfWarManager = {}

-- Default vision ranges (in studs)
local VISION_RANGES = {
	Unit = 100,
	Building = 150,
	Keep = 300,
}

-- Player-specific fog of war state
type FogOfWarData = {
	enabled: boolean,
	visibleUnits: { [Model]: boolean },
	visibleBuildings: { [Model]: boolean },
}

local playerFogData: { [Player]: FogOfWarData } = {}

-- Initialize fog of war for a player
function FogOfWarManager.init(player: Player)
	playerFogData[player] = {
		enabled = true, -- Fog of war ON by default
		visibleUnits = {},
		visibleBuildings = {},
	}
	FogDebug:info(`Initialized fog of war for {player.Name}`)
end

-- Clean up when player leaves
function FogOfWarManager.cleanup(player: Player)
	playerFogData[player] = nil
	FogDebug:info(`Cleaned up fog of war for {player.Name}`)
end

-- Toggle fog of war for a player (admin command)
function FogOfWarManager.toggle(player: Player, enabled: boolean)
	local data = playerFogData[player]
	if not data then
		return
	end

	data.enabled = enabled
	FogDebug:info(`Fog of war {enabled and "enabled" or "disabled"} for {player.Name}`)

	-- If disabled, reveal everything
	if not enabled then
		data.visibleUnits = {}
		data.visibleBuildings = {}
	end
end

-- Check if fog of war is enabled for a player
function FogOfWarManager.isEnabled(player: Player): boolean
	local data = playerFogData[player]
	return data and data.enabled or false
end

-- Check if a position is visible to a player
local function isPositionVisible(player: Player, position: Vector3): boolean
	local data = playerFogData[player]
	if not data or not data.enabled then
		return true -- If fog disabled, everything is visible
	end

	-- Check vision from player's units
	local unitsFolder = workspace:FindFirstChild("Units")
	if unitsFolder then
		for _, unit in unitsFolder:GetChildren() do
			if unit:IsA("Model") and unit.PrimaryPart then
				local owner = unit:GetAttribute("Owner")
				if owner == player.UserId then
					local unitType = unit:GetAttribute("UnitType") or "Unit"
					local visionRange = VISION_RANGES[unitType] or VISION_RANGES.Unit
					local distance = (unit.PrimaryPart.Position - position).Magnitude

					if distance <= visionRange then
						return true
					end
				end
			end
		end
	end

	-- Check vision from player's buildings
	local buildingsFolder = workspace:FindFirstChild("Buildings")
	if buildingsFolder then
		for _, building in buildingsFolder:GetChildren() do
			if building:IsA("Model") and building.PrimaryPart then
				local owner = building:GetAttribute("Owner")
				if owner == player.UserId then
					local buildingType = building:GetAttribute("BuildingType") or "Building"
					local visionRange = VISION_RANGES[buildingType] or VISION_RANGES.Building
					local distance = (building.PrimaryPart.Position - position).Magnitude

					if distance <= visionRange then
						return true
					end
				end
			end
		end
	end

	return false
end

-- Check if a unit is visible to a player
function FogOfWarManager.isUnitVisible(player: Player, unit: Model): boolean
	if not unit or not unit.PrimaryPart then
		return false
	end

	-- Always see your own units
	local owner = unit:GetAttribute("Owner")
	if owner == player.UserId then
		return true
	end

	-- Check fog of war
	return isPositionVisible(player, unit.PrimaryPart.Position)
end

-- Check if a building is visible to a player
function FogOfWarManager.isBuildingVisible(player: Player, building: Model): boolean
	if not building or not building.PrimaryPart then
		return false
	end

	-- Always see your own buildings
	local owner = building:GetAttribute("Owner")
	if owner == player.UserId then
		return true
	end

	-- Check fog of war
	return isPositionVisible(player, building.PrimaryPart.Position)
end

-- Get list of visible units for a player (for minimap)
function FogOfWarManager.getVisibleUnits(player: Player): { Model }
	local visibleUnits = {}

	local unitsFolder = workspace:FindFirstChild("Units")
	if not unitsFolder then
		return visibleUnits
	end

	for _, unit in unitsFolder:GetChildren() do
		if unit:IsA("Model") and FogOfWarManager.isUnitVisible(player, unit) then
			table.insert(visibleUnits, unit)
		end
	end

	return visibleUnits
end

-- Get list of visible buildings for a player (for minimap)
function FogOfWarManager.getVisibleBuildings(player: Player): { Model }
	local visibleBuildings = {}

	local buildingsFolder = workspace:FindFirstChild("Buildings")
	if not buildingsFolder then
		return visibleBuildings
	end

	for _, building in buildingsFolder:GetChildren() do
		if building:IsA("Model") and FogOfWarManager.isBuildingVisible(player, building) then
			table.insert(visibleBuildings, building)
		end
	end

	return visibleBuildings
end

-- Update visibility data (called periodically)
function FogOfWarManager.updateVisibility(player: Player)
	local data = playerFogData[player]
	if not data or not data.enabled then
		return
	end

	-- Update visible units
	data.visibleUnits = {}
	for _, unit in FogOfWarManager.getVisibleUnits(player) do
		data.visibleUnits[unit] = true
	end

	-- Update visible buildings
	data.visibleBuildings = {}
	for _, building in FogOfWarManager.getVisibleBuildings(player) do
		data.visibleBuildings[building] = true
	end
end

-- Start periodic visibility updates (called once on server start)
function FogOfWarManager.startUpdates()
	-- Update visibility every 0.5 seconds (same as minimap update rate)
	task.spawn(function()
		while true do
			task.wait(0.5)

			for player, _ in playerFogData do
				if player and player.Parent then
					FogOfWarManager.updateVisibility(player)
				end
			end
		end
	end)

	FogDebug:info("Started fog of war visibility updates")
end

FogDebug:info("FogOfWarManager loaded")

return FogOfWarManager
