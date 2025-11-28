--!strict
-- BuildingTypeHelper: Unified system for classifying and categorizing buildings
-- This eliminates special-casing throughout the codebase and makes adding new buildings simple

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameData = require(ReplicatedStorage.Shared.GameData)

local BuildingTypeHelper = {}

-- ========================================
-- BUILDING CLASSIFICATION FUNCTIONS
-- These determine what category a building belongs to based on its data
-- ========================================

-- Check if building can produce resources (with workers)
function BuildingTypeHelper.isResourceProducer(buildingType: string): boolean
	local buildingData = GameData.Buildings[buildingType]
	if not buildingData then
		return false
	end

	return buildingData.produces_resource ~= nil and buildingData.requires_worker == true
end

-- Check if building is a passive resource producer (no input needed, just workers)
function BuildingTypeHelper.isPassiveProducer(buildingType: string): boolean
	local buildingData = GameData.Buildings[buildingType]
	if not buildingData then
		return false
	end

	-- Produces resources but doesn't consume any (Farm, Woodcutters, Quarry, Mine)
	return buildingData.produces_resource ~= nil
		and buildingData.consumes_resource == nil
		and buildingData.requires_worker == true
end

-- Check if building is part of a production chain (consumes to produce)
function BuildingTypeHelper.isProductionChain(buildingType: string): boolean
	local buildingData = GameData.Buildings[buildingType]
	if not buildingData then
		return false
	end

	-- Both consumes AND produces (Smithy, Weaponsmith, Bakery, Brewery)
	return buildingData.consumes_resource ~= nil
		and buildingData.produces_resource ~= nil
end

-- Check if building is a pure consumer (consumes but doesn't produce)
function BuildingTypeHelper.isResourceConsumer(buildingType: string): boolean
	local buildingData = GameData.Buildings[buildingType]
	if not buildingData then
		return false
	end

	-- Consumes but doesn't produce (Kitchen, Restaurant)
	return buildingData.consumes_resource ~= nil
		and buildingData.produces_resource == nil
end

-- Check if building can train units
function BuildingTypeHelper.isTrainingBuilding(buildingType: string): boolean
	local buildingData = GameData.Buildings[buildingType]
	if not buildingData then
		return false
	end

	return buildingData.can_train_units ~= nil and #buildingData.can_train_units > 0
end

-- Check if building provides storage
function BuildingTypeHelper.isStorageBuilding(buildingType: string): boolean
	local buildingData = GameData.Buildings[buildingType]
	if not buildingData then
		return false
	end

	return buildingData.storage_capacity ~= nil
		and next(buildingData.storage_capacity) ~= nil
end

-- Check if building provides housing
function BuildingTypeHelper.isHousingBuilding(buildingType: string): boolean
	local buildingData = GameData.Buildings[buildingType]
	if not buildingData then
		return false
	end

	return buildingData.housing_capacity ~= nil and buildingData.housing_capacity > 0
end

-- Check if building requires workers to function
function BuildingTypeHelper.requiresWorker(buildingType: string): boolean
	local buildingData = GameData.Buildings[buildingType]
	if not buildingData then
		return false
	end

	return buildingData.requires_worker == true
end

-- Check if building affects popularity
function BuildingTypeHelper.affectsPopularity(buildingType: string): boolean
	local buildingData = GameData.Buildings[buildingType]
	if not buildingData then
		return false
	end

	return buildingData.popularity_impact ~= nil and buildingData.popularity_impact ~= 0
end

-- Check if building provides defense
function BuildingTypeHelper.isDefensiveBuilding(buildingType: string): boolean
	local buildingData = GameData.Buildings[buildingType]
	if not buildingData then
		return false
	end

	return buildingData.defense_value ~= nil and buildingData.defense_value > 0
end

-- Check if building can attack (towers, etc.)
function BuildingTypeHelper.canAttack(buildingType: string): boolean
	local buildingData = GameData.Buildings[buildingType]
	if not buildingData then
		return false
	end

	return buildingData.attack_range ~= nil and buildingData.attack_damage ~= nil
end

-- ========================================
-- BUILDING CAPABILITY QUERIES
-- These help determine what operations a building can perform
-- ========================================

-- Get all capabilities of a building as a list
function BuildingTypeHelper.getBuildingCapabilities(buildingType: string): { string }
	local capabilities = {}

	if BuildingTypeHelper.isPassiveProducer(buildingType) then
		table.insert(capabilities, "PassiveProduction")
	end

	if BuildingTypeHelper.isProductionChain(buildingType) then
		table.insert(capabilities, "ProductionChain")
	end

	if BuildingTypeHelper.isResourceConsumer(buildingType) then
		table.insert(capabilities, "ResourceConsumer")
	end

	if BuildingTypeHelper.isTrainingBuilding(buildingType) then
		table.insert(capabilities, "UnitTraining")
	end

	if BuildingTypeHelper.isStorageBuilding(buildingType) then
		table.insert(capabilities, "Storage")
	end

	if BuildingTypeHelper.isHousingBuilding(buildingType) then
		table.insert(capabilities, "Housing")
	end

	if BuildingTypeHelper.affectsPopularity(buildingType) then
		table.insert(capabilities, "PopularityImpact")
	end

	if BuildingTypeHelper.isDefensiveBuilding(buildingType) then
		table.insert(capabilities, "Defense")
	end

	if BuildingTypeHelper.canAttack(buildingType) then
		table.insert(capabilities, "Attack")
	end

	return capabilities
end

-- Check if building has a specific capability
function BuildingTypeHelper.hasCapability(buildingType: string, capability: string): boolean
	local capabilities = BuildingTypeHelper.getBuildingCapabilities(buildingType)

	for _, cap in capabilities do
		if cap == capability then
			return true
		end
	end

	return false
end

-- Get the building's production info (if any)
function BuildingTypeHelper.getProductionInfo(buildingType: string): {
	producesResource: string?,
	productionRate: number?,
	consumesResource: string?,
	consumptionRate: number?,
	requiresWorker: boolean,
}?
	local buildingData = GameData.Buildings[buildingType]
	if not buildingData then
		return nil
	end

	if not BuildingTypeHelper.isResourceProducer(buildingType) then
		return nil
	end

	return {
		producesResource = buildingData.produces_resource,
		productionRate = buildingData.production_rate,
		consumesResource = buildingData.consumes_resource,
		consumptionRate = buildingData.consumption_rate,
		requiresWorker = buildingData.requires_worker or false,
	}
end

-- ========================================
-- HELPER FUNCTIONS FOR COMMON OPERATIONS
-- ========================================

-- Determine if a building can currently produce (has inputs if needed)
function BuildingTypeHelper.canProduceNow(building: Instance, checkInputs: (Instance, string, number) -> boolean): boolean
	local buildingType = building:GetAttribute("BuildingType")
	if not buildingType then
		return false
	end

	local buildingData = GameData.Buildings[buildingType]
	if not buildingData or not buildingData.produces_resource then
		return false
	end

	-- Passive producers can always produce (no inputs needed)
	if BuildingTypeHelper.isPassiveProducer(buildingType) then
		return true
	end

	-- Production chain buildings need inputs
	if BuildingTypeHelper.isProductionChain(buildingType) then
		if not buildingData.consumes_resource or not buildingData.consumption_rate then
			return false
		end

		-- Use the provided checkInputs function to verify
		return checkInputs(building, buildingData.consumes_resource, buildingData.consumption_rate)
	end

	return false
end

return BuildingTypeHelper
