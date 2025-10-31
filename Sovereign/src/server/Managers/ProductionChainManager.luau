--!strict
-- ProductionChainManager: Manages buildings that consume resources to produce others (production chains)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuildingManager = require(script.Parent.BuildingManager)
local PlayerManager = require(script.Parent.PlayerManager)
local GameData = require(ReplicatedStorage.Shared.GameData)
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)

local ProductionChainDebug = DebugManager.createChannel("ProductionChain", true)

local ProductionChainManager = {}

-- Check if a building has enough input resources to produce
function ProductionChainManager.canProduce(building: Instance): boolean
	local buildingType = building:GetAttribute("BuildingType")
	if not buildingType then
		return false
	end

	local buildingData = GameData.Buildings[buildingType]
	if not buildingData or not buildingData.consumes_resource or not buildingData.consumption_rate then
		-- Building doesn't consume resources, so it can produce
		return true
	end

	-- Check if building has enough of the consumed resource in its storage
	local requiredResource = buildingData.consumes_resource
	local requiredAmount = buildingData.consumption_rate

	local storedAmount = BuildingManager.getStorageAmount(building, requiredResource)

	return storedAmount >= requiredAmount
end

-- Consume input resources for production
function ProductionChainManager.consumeInputs(building: Instance): boolean
	local buildingType = building:GetAttribute("BuildingType")
	if not buildingType then
		return false
	end

	local buildingData = GameData.Buildings[buildingType]
	if not buildingData or not buildingData.consumes_resource or not buildingData.consumption_rate then
		-- Building doesn't consume resources
		return true
	end

	local requiredResource = buildingData.consumes_resource
	local requiredAmount = buildingData.consumption_rate

	-- Check if we have enough
	if not ProductionChainManager.canProduce(building) then
		ProductionChainDebug:warn(`{buildingType} cannot produce - not enough {requiredResource}`)
		return false
	end

	-- Consume the input resources
	local consumed = BuildingManager.takeFromStorage(building, requiredResource, requiredAmount)

	if consumed > 0 then
		ProductionChainDebug:info(`{buildingType} consumed {consumed} {requiredResource} for production`)
		return true
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

-- Check if a building is a production chain building (consumes to produce)
function ProductionChainManager.isProductionChainBuilding(buildingType: string): boolean
	local buildingData = GameData.Buildings[buildingType]
	if not buildingData then
		return false
	end

	return buildingData.consumes_resource ~= nil and buildingData.produces_resource ~= nil
end

return ProductionChainManager
