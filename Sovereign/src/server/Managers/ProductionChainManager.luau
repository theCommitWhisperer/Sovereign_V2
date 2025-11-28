--!strict
-- ProductionChainManager: Manages buildings that consume resources to produce others (production chains)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuildingManager = require(script.Parent.BuildingManager)
local PlayerManager = require(script.Parent.PlayerManager)
local GameData = require(ReplicatedStorage.Shared.GameData)
local BuildingTypeHelper = require(ReplicatedStorage.Shared.BuildingTypeHelper)
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)

local ProductionChainDebug = DebugManager.createChannel("ProductionChain", true)

local ProductionChainManager = {}

-- Check if a building has enough input resources to produce
function ProductionChainManager.canProduce(building: Instance): boolean
	local buildingType = building:GetAttribute("BuildingType")
	if not buildingType then
		return false
	end

	-- Use BuildingTypeHelper to check if building needs inputs
	-- Passive producers (Farm, Woodcutters, etc.) can always produce
	if BuildingTypeHelper.isPassiveProducer(buildingType) then
		return true
	end

	-- Production chain buildings need to check input availability
	if BuildingTypeHelper.isProductionChain(buildingType) then
		local buildingData = GameData.Buildings[buildingType]
		if not buildingData or not buildingData.consumes_resource or not buildingData.consumption_rate then
			return false
		end

		local storedAmount = BuildingManager.getStorageAmount(building, buildingData.consumes_resource)
		return storedAmount >= buildingData.consumption_rate
	end

	return false
end

-- Consume input resources for production
function ProductionChainManager.consumeInputs(building: Instance): boolean
	local buildingType = building:GetAttribute("BuildingType")
	if not buildingType then
		return false
	end

	-- Passive producers don't consume anything - always succeed
	if BuildingTypeHelper.isPassiveProducer(buildingType) then
		return true
	end

	-- Production chain buildings need to consume inputs
	if BuildingTypeHelper.isProductionChain(buildingType) then
		local buildingData = GameData.Buildings[buildingType]
		if not buildingData or not buildingData.consumes_resource or not buildingData.consumption_rate then
			return false
		end

		-- Check if we have enough
		if not ProductionChainManager.canProduce(building) then
			ProductionChainDebug:warn(`{buildingType} cannot produce - not enough {buildingData.consumes_resource}`)
			return false
		end

		-- Consume the input resources
		local consumed = BuildingManager.takeFromStorage(building, buildingData.consumes_resource, buildingData.consumption_rate)

		if consumed > 0 then
			ProductionChainDebug:info(`{buildingType} consumed {consumed} {buildingData.consumes_resource} for production`)
			return true
		end

		return false
	end

	return false
end

-- Get production status for a building (for UI display)
function ProductionChainManager.getProductionStatus(building: Instance): {
	canProduce: boolean,
	inputResource: string?,
	inputNeeded: number?,
	inputAvailable: number?,
	outputResource: string?,
	productionRate: number?,
}
	local buildingType = building:GetAttribute("BuildingType")
	if not buildingType then
		return {
			canProduce = false,
		}
	end

	local buildingData = GameData.Buildings[buildingType]
	if not buildingData then
		return {
			canProduce = false,
		}
	end

	local status = {
		canProduce = true,
		inputResource = buildingData.consumes_resource,
		inputNeeded = buildingData.consumption_rate,
		inputAvailable = nil,
		outputResource = buildingData.produces_resource,
		productionRate = buildingData.production_rate,
	}

	-- If building consumes resources, check availability
	if buildingData.consumes_resource then
		local storedAmount = BuildingManager.getStorageAmount(building, buildingData.consumes_resource)
		status.inputAvailable = storedAmount
		status.canProduce = storedAmount >= (buildingData.consumption_rate or 0)
	end

	return status
end

-- Check if a building is a resource producer (includes both passive and production chain)
-- This replaces the old isProductionChainBuilding to support all production types
function ProductionChainManager.isProductionChainBuilding(buildingType: string): boolean
	-- Now includes ALL buildings that produce resources (Farm, Woodcutters, AND production chains)
	return BuildingTypeHelper.isResourceProducer(buildingType)
end

return ProductionChainManager
