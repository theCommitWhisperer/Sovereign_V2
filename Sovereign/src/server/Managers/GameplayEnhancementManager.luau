--!strict
-- GameplayEnhancementManager: Building-focused gameplay improvements
-- Features: Combo bonuses, production alerts, building notifications

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local GameData = require(ReplicatedStorage.Shared.GameData)
local PlayerManager = require(script.Parent.PlayerManager)
local NotificationManager = require(script.Parent.NotificationManager)
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)

local EnhancementDebug = DebugManager.createChannel("GameplayEnhance", false)

local GameplayEnhancementManager = {}

-- ═══════════════════════════════════════════════════════════════════════════
-- BUILDING COMBO BONUSES
-- ═══════════════════════════════════════════════════════════════════════════

local COMBO_DEFINITIONS = {
	-- Brewery + Tavern combo
	{
		name = "🍺 Irish Pub District",
		buildings = { "Brewery", "Tavern" },
		radius = 50,
		bonuses = {
			production = 1.25, -- +25% production
			happiness = 1.25, -- +25% happiness
		},
		message = "Brewery + Tavern = +25% production & happiness!",
	},

	-- Weaponsmith + Barracks combo
	{
		name = "⚔️ Military Complex",
		buildings = { "Weaponsmith", "Barracks" },
		radius = 50,
		bonuses = {
			trainingCost = 0.9, -- -10% training cost
			production = 1.15, -- +15% weapon production
		},
		message = "Weaponsmith + Barracks = -10% training cost, +15% weapon production!",
	},

	-- Smelter + Weaponsmith combo
	{
		name = "🔨 Industrial District",
		buildings = { "Smelter", "Weaponsmith" },
		radius = 50,
		bonuses = {
			production = 1.20, -- +20% production for both
		},
		message = "Smelter + Weaponsmith = +20% production!",
	},

	-- Windmill/Water Mill + Bakery combo
	{
		name = "🍞 Bakery District",
		buildings = { "Bakery", "Windmill" },
		radius = 50,
		bonuses = {
			production = 1.30, -- +30% production
		},
		message = "Bakery + Mill = +30% bread production!",
	},
	{
		name = "🍞 Bakery District",
		buildings = { "Bakery", "Water Mill" },
		radius = 50,
		bonuses = {
			production = 1.30,
		},
		message = "Bakery + Mill = +30% bread production!",
	},

	-- Church + Monastery combo
	{
		name = "✝️ Religious District",
		buildings = { "Church", "Monastery" },
		radius = 60,
		bonuses = {
			happiness = 1.30, -- +30% happiness
			production = 1.25, -- +25% manuscript production
		},
		message = "Church + Monastery = +30% happiness, +25% manuscript production!",
	},

	-- Inn + Tavern combo
	{
		name = "🏠 Hospitality District",
		buildings = { "Inn", "Tavern" },
		radius = 50,
		bonuses = {
			happiness = 1.20, -- +20% happiness
			gold = 1.15, -- +15% gold income
		},
		message = "Inn + Tavern = +20% happiness, +15% gold!",
	},

	-- Market + Trading Post combo
	{
		name = "💰 Trade Hub",
		buildings = { "Market", "Trading Post" },
		radius = 50,
		bonuses = {
			gold = 1.40, -- +40% gold income
		},
		message = "Market + Trading Post = +40% gold income!",
	},
}

-- Farm cluster bonus (special case - 3+ farms)
local FARM_CLUSTER_BONUS = {
	name = "🌾 Farming Community",
	buildingTypes = { "Potato Farm", "Sheep Farm", "Cow Farm" },
	minCount = 3,
	radius = 60,
	bonus = 1.15, -- +15% production for all farms
	message = "3+ Farms together = +15% food production!",
}

local function findBuildingsInRadius(position: Vector3, radius: number, ownerId: number): { Instance }
	local buildingsFolder = Workspace:FindFirstChild("Buildings")
	if not buildingsFolder then
		return {}
	end

	local nearbyBuildings = {}
	for _, building in buildingsFolder:GetChildren() do
		if building:GetAttribute("OwnerId") == ownerId then
			local buildingPos = building:GetPivot().Position
			local distance = (buildingPos - position).Magnitude
			if distance <= radius and distance > 0 then
				table.insert(nearbyBuildings, building)
			end
		end
	end

	return nearbyBuildings
end

local function checkComboBonuses(building: Instance, buildingType: string, ownerId: number)
	local position = building:GetPivot().Position
	local player = game.Players:GetPlayerByUserId(ownerId)

	-- Check standard combos
	for _, combo in COMBO_DEFINITIONS do
		-- Skip if this building isn't part of the combo
		local isPartOfCombo = false
		for _, comboBuilding in combo.buildings do
			if comboBuilding == buildingType then
				isPartOfCombo = true
				break
			end
		end

		if not isPartOfCombo then
			continue
		end

		-- Find nearby buildings
		local nearbyBuildings = findBuildingsInRadius(position, combo.radius, ownerId)

		-- Check if combo partner exists
		for _, partnerType in combo.buildings do
			if partnerType == buildingType then
				continue -- Skip self
			end

			for _, nearby in nearbyBuildings do
				local nearbyType = nearby:GetAttribute("BuildingType")
				if nearbyType == partnerType then
					-- COMBO FOUND!
					-- Apply bonuses to both buildings
					for bonusType, value in combo.bonuses do
						building:SetAttribute(`ComboBonus_{bonusType}`, value)
						nearby:SetAttribute(`ComboBonus_{bonusType}`, value)
					end

					-- Visual effect (golden particles)
					if building.PrimaryPart and not building:FindFirstChild("ComboEffect") then
						local effect = Instance.new("ParticleEmitter")
						effect.Name = "ComboEffect"
						effect.Parent = building.PrimaryPart
						effect.Color = ColorSequence.new(Color3.fromRGB(255, 215, 0))
						effect.Rate = 3
						effect.Lifetime = NumberRange.new(2)
						effect.Speed = NumberRange.new(2)
						effect.SpreadAngle = Vector2.new(45, 45)
					end

					-- Notify player
					if player then
						NotificationManager.success(player, combo.name, combo.message)
					end

					EnhancementDebug:info(`Combo activated: {combo.name}`)
				end
			end
		end
	end

	-- Check farm cluster bonus
	local isFarmBuilding = buildingType:find("Farm") ~= nil
	if isFarmBuilding then
		local nearbyBuildings = findBuildingsInRadius(position, FARM_CLUSTER_BONUS.radius, ownerId)
		local farmCount = 1 -- Include self

		local farmsInCluster = { building }

		for _, nearby in nearbyBuildings do
			local nearbyType = nearby:GetAttribute("BuildingType")
			for _, farmType in FARM_CLUSTER_BONUS.buildingTypes do
				if nearbyType == farmType then
					farmCount += 1
					table.insert(farmsInCluster, nearby)
					break
				end
			end
		end

		if farmCount >= FARM_CLUSTER_BONUS.minCount then
			-- Apply bonus to all farms in cluster
			for _, farm in farmsInCluster do
				farm:SetAttribute("ComboBonus_production", FARM_CLUSTER_BONUS.bonus)

				-- Visual effect
				if farm.PrimaryPart and not farm:FindFirstChild("ComboEffect") then
					local effect = Instance.new("ParticleEmitter")
					effect.Name = "ComboEffect"
					effect.Parent = farm.PrimaryPart
					effect.Color = ColorSequence.new(Color3.fromRGB(144, 238, 144)) -- Light green
					effect.Rate = 3
					effect.Lifetime = NumberRange.new(2)
					effect.Speed = NumberRange.new(2)
				end
			end

			-- Notify player
			if player then
				NotificationManager.success(
					player,
					FARM_CLUSTER_BONUS.name,
					`{farmCount} {FARM_CLUSTER_BONUS.message}`
				)
			end

			EnhancementDebug:info(`Farm cluster activated: {farmCount} farms`)
		end
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- PRODUCTION MONITORING
-- ═══════════════════════════════════════════════════════════════════════════

local productionCheckInterval = 5 -- Check every 5 seconds
local lastProductionCheck = 0

local function monitorProductionChains()
	local buildingsFolder = Workspace:FindFirstChild("Buildings")
	if not buildingsFolder then
		return
	end

	for _, building in buildingsFolder:GetChildren() do
		local buildingType = building:GetAttribute("BuildingType")
		if not buildingType then
			continue
		end

		local buildingData = GameData.Buildings[buildingType]
		if not buildingData or not buildingData.consumes_resource then
			continue -- Not a production chain building
		end

		-- Check if production is stopped (lazy-load to avoid circular dependency)
		local storedAmount = 0
		local success = pcall(function()
			local BuildingManager = require(script.Parent.BuildingManager)
			storedAmount = BuildingManager.getStorageAmount(building, buildingData.consumes_resource)
		end)

		if not success then
			-- If BuildingManager isn't loaded yet, skip this check
			continue
		end

		local canProduce = storedAmount >= (buildingData.consumption_rate or 0)

		if not canProduce then
			-- Production stopped
			if not building:GetAttribute("ProductionStoppedWarned") then
				building:SetAttribute("ProductionStoppedWarned", true)

				local owner = building:GetAttribute("OwnerId")
				local player = game.Players:GetPlayerByUserId(owner)

				if player then
					local resourceNeeded = buildingData.consumes_resource
					NotificationManager.warning(player, "⚠️ Production Stopped", `{buildingType} needs {resourceNeeded}!`)
				end

				EnhancementDebug:warn(`Production stopped: {buildingType}`)
			end
		else
			-- Production can run
			if building:GetAttribute("ProductionStoppedWarned") then
				building:SetAttribute("ProductionStoppedWarned", false)

				local owner = building:GetAttribute("OwnerId")
				local player = game.Players:GetPlayerByUserId(owner)

				if player then
					NotificationManager.success(player, "✅ Production Resumed", `{buildingType} is producing again!`)
				end

				EnhancementDebug:info(`Production resumed: {buildingType}`)
			end
		end
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- PUBLIC API
-- ═══════════════════════════════════════════════════════════════════════════

function GameplayEnhancementManager.onBuildingCreated(building: Instance, buildingType: string, ownerId: number)
	-- Check for combo bonuses
	checkComboBonuses(building, buildingType, ownerId)

	EnhancementDebug:info(`Building created with enhancements: {buildingType}`)
end

function GameplayEnhancementManager.getBuildingProductionBonus(building: Instance): number
	return building:GetAttribute("ComboBonus_production") or 1.0
end

function GameplayEnhancementManager.getBuildingHappinessBonus(building: Instance): number
	return building:GetAttribute("ComboBonus_happiness") or 1.0
end

function GameplayEnhancementManager.getBuildingGoldBonus(building: Instance): number
	return building:GetAttribute("ComboBonus_gold") or 1.0
end

function GameplayEnhancementManager.init()
	-- Monitor production chains periodically
	RunService.Heartbeat:Connect(function()
		local currentTime = tick()
		if currentTime - lastProductionCheck >= productionCheckInterval then
			monitorProductionChains()
			lastProductionCheck = currentTime
		end
	end)

	EnhancementDebug:info("GameplayEnhancementManager initialized", {
		combos = #COMBO_DEFINITIONS,
		productionCheckInterval = productionCheckInterval,
	})
end

return GameplayEnhancementManager
