--!strict
-- PathfindingController: Simplified pathfinding helper
-- Note: Roblox PathfindingModifiers don't support dynamic cost updates
-- Instead, we rely on LocalSteeringBehavior for dynamic obstacle avoidance

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)
local PathfindingDebug = DebugManager.createChannel("Pathfinding", false)

local PathfindingController = {}

-- Stub functions for compatibility with existing code
-- These are no-ops because PathfindingModifiers don't work as intended for this use case
function PathfindingController.createUnitModifier(_unit: Model)
	-- No-op: LocalSteeringBehavior handles unit avoidance
	return nil
end

function PathfindingController.createBuildingModifier(_building: Model)
	-- No-op: Buildings are avoided through PathfindingService's native collision detection
	return nil
end

function PathfindingController.updateUnitModifier(_unit: Model)
	-- No-op
end

function PathfindingController.removeUnitModifier(_unit: Model)
	-- No-op
end

function PathfindingController.removeBuildingModifier(_building: Model)
	-- No-op
end

function PathfindingController.initializeExistingUnits()
	PathfindingDebug:info("PathfindingController: Skipping unit modifiers (using LocalSteering instead)")
end

function PathfindingController.initializeExistingBuildings()
	PathfindingDebug:info("PathfindingController: Skipping building modifiers (native avoidance)")
end

function PathfindingController.updateAllUnitModifiers()
	-- No-op
end

function PathfindingController.getConfig()
	return {
		unitRadius = 6,
		buildingRadius = 8,
	}
end

PathfindingDebug:info("PathfindingController loaded (stub mode - using LocalSteering)")

return PathfindingController
