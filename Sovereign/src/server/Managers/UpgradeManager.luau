--!strict
-- UpgradeManager: Handles building upgrades with 3-tier progression
-- Features: Building improvements, stat boosts, unlock new capabilities

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameData = require(ReplicatedStorage.Shared.GameData)
local PlayerManager = require(script.Parent.PlayerManager)
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)

local UpgradeDebug = DebugManager.createChannel("Upgrades", false)

local UpgradeManager = {}

-- ═══════════════════════════════════════════════════════════════════════════
-- TYPES
-- ═══════════════════════════════════════════════════════════════════════════

export type UpgradeTier = {
	level: number,
	cost: { [string]: number },
	productionBonus: number?,
	storageBonus: number?,
	healthBonus: number?,
	description: string,
}

export type BuildingUpgrade = {
	buildingType: string,
	maxLevel: number,
	tiers: { UpgradeTier },
}

-- Track building upgrade levels
local BuildingLevels: { [Instance]: number } = {}

-- ═══════════════════════════════════════════════════════════════════════════
-- UPGRADE DEFINITIONS
-- ═══════════════════════════════════════════════════════════════════════════

local UPGRADES: { [string]: BuildingUpgrade } = {
	Keep = {
		buildingType = "Keep",
		maxLevel = 3,
		tiers = {
			{
				level = 2,
				cost = { Wood = 500, Stone = 400, Gold = 300 },
				storageBonus = 1.5,
				healthBonus = 1.3,
				description = "Upgrade to Castle - Increase storage capacity by 50%",
			},
			{
				level = 3,
				cost = { Wood = 1000, Stone = 800, Gold = 600 },
				storageBonus = 2.0,
				healthBonus = 1.6,
				description = "Upgrade to Fortress - Double storage capacity",
			},
		},
	},

	Woodcutters_Post = {
		buildingType = "Woodcutters_Post",
		maxLevel = 3,
		tiers = {
			{
				level = 2,
				cost = { Wood = 150, Stone = 100 },
				productionBonus = 1.4,
				description = "Improved Woodcutter's Post - 40% faster wood production",
			},
			{
				level = 3,
				cost = { Wood = 300, Stone = 200, Gold = 100 },
				productionBonus = 1.8,
				description = "Master Woodcutter's Post - 80% faster wood production",
			},
		},
	},

	Stone_Quarry = {
		buildingType = "Stone_Quarry",
		maxLevel = 3,
		tiers = {
			{
				level = 2,
				cost = { Wood = 150, Stone = 100 },
				productionBonus = 1.4,
				description = "Improved Stone Quarry - 40% faster stone production",
			},
			{
				level = 3,
				cost = { Wood = 300, Stone = 200, Gold = 100 },
				productionBonus = 1.8,
				description = "Master Stone Quarry - 80% faster stone production",
			},
		},
	},

	Iron_Mine = {
		buildingType = "Iron_Mine",
		maxLevel = 3,
		tiers = {
			{
				level = 2,
				cost = { Wood = 200, Stone = 150, Gold = 50 },
				productionBonus = 1.5,
				description = "Deep Iron Mine - 50% faster iron production",
			},
			{
				level = 3,
				cost = { Wood = 400, Stone = 300, Gold = 150 },
				productionBonus = 2.0,
				description = "Master Iron Mine - Double iron production",
			},
		},
	},

	Farm = {
		buildingType = "Farm",
		maxLevel = 3,
		tiers = {
			{
				level = 2,
				cost = { Wood = 100, Stone = 50 },
				productionBonus = 1.3,
				description = "Improved Farm - 30% more food production",
			},
			{
				level = 3,
				cost = { Wood = 200, Stone = 100, Gold = 50 },
				productionBonus = 1.7,
				description = "Advanced Farm - 70% more food production",
			},
		},
	},

	Barracks = {
		buildingType = "Barracks",
		maxLevel = 3,
		tiers = {
			{
				level = 2,
				cost = { Wood = 300, Stone = 250, Gold = 200 },
				productionBonus = 1.3,
				description = "Advanced Barracks - 30% faster troop training",
			},
			{
				level = 3,
				cost = { Wood = 600, Stone = 500, Gold = 400 },
				productionBonus = 1.6,
				description = "Elite Barracks - 60% faster troop training, unlocks elite units",
			},
		},
	},

	Storehouse = {
		buildingType = "Storehouse",
		maxLevel = 3,
		tiers = {
			{
				level = 2,
				cost = { Wood = 200, Stone = 150 },
				storageBonus = 1.6,
				description = "Large Storehouse - 60% more storage capacity",
			},
			{
				level = 3,
				cost = { Wood = 400, Stone = 300, Gold = 100 },
				storageBonus = 2.2,
				description = "Warehouse - 120% more storage capacity",
			},
		},
	},

	Granary = {
		buildingType = "Granary",
		maxLevel = 3,
		tiers = {
			{
				level = 2,
				cost = { Wood = 200, Stone = 150 },
				storageBonus = 1.6,
				description = "Large Granary - 60% more food storage",
			},
			{
				level = 3,
				cost = { Wood = 400, Stone = 300, Gold = 100 },
				storageBonus = 2.2,
				description = "Silo - 120% more food storage",
			},
		},
	},
}

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPER FUNCTIONS
-- ═══════════════════════════════════════════════════════════════════════════

local function applyUpgradeEffects(building: Instance, tier: UpgradeTier)
	local buildingType = building:GetAttribute("BuildingType")
	local buildingInfo = GameData.Buildings[buildingType]

	if not buildingInfo then
		return
	end

	-- Apply production bonus
	if tier.productionBonus and buildingInfo.production then
		local currentRate = building:GetAttribute("ProductionRate") or 1.0
		building:SetAttribute("ProductionRate", tier.productionBonus)
		UpgradeDebug:info(`Applied production bonus: {tier.productionBonus}x to {buildingType}`)
	end

	-- Apply storage bonus
	if tier.storageBonus and buildingInfo.storage_capacity then
		building:SetAttribute("StorageMultiplier", tier.storageBonus)
		UpgradeDebug:info(`Applied storage bonus: {tier.storageBonus}x to {buildingType}`)
	end

	-- Apply health bonus
	if tier.healthBonus then
		local currentHealth = building:GetAttribute("Health") or 100
		local maxHealth = building:GetAttribute("MaxHealth") or 100
		local newMaxHealth = maxHealth * tier.healthBonus
		building:SetAttribute("MaxHealth", newMaxHealth)
		building:SetAttribute("Health", currentHealth * tier.healthBonus)
		UpgradeDebug:info(`Applied health bonus: {tier.healthBonus}x to {buildingType}`)
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- PUBLIC API
-- ═══════════════════════════════════════════════════════════════════════════

function UpgradeManager.canUpgrade(building: Instance): boolean
	local buildingType = building:GetAttribute("BuildingType")
	if not buildingType then
		return false
	end

	local upgrade = UPGRADES[buildingType]
	if not upgrade then
		return false
	end

	local currentLevel = BuildingLevels[building] or 1
	return currentLevel < upgrade.maxLevel
end

function UpgradeManager.getUpgradeInfo(building: Instance): UpgradeTier?
	local buildingType = building:GetAttribute("BuildingType")
	if not buildingType then
		return nil
	end

	local upgrade = UPGRADES[buildingType]
	if not upgrade then
		return nil
	end

	local currentLevel = BuildingLevels[building] or 1
	if currentLevel >= upgrade.maxLevel then
		return nil
	end

	-- Return the next tier
	return upgrade.tiers[currentLevel]
end

function UpgradeManager.upgradeBuilding(player: Player, building: Instance): boolean
	local buildingType = building:GetAttribute("BuildingType")
	if not buildingType then
		UpgradeDebug:warn("Building has no BuildingType attribute")
		return false
	end

	-- Check if player owns the building
	if building:GetAttribute("Owner") ~= player.UserId then
		UpgradeDebug:warn(`{player.Name} tried to upgrade building they don't own`)
		return false
	end

	local upgrade = UPGRADES[buildingType]
	if not upgrade then
		UpgradeDebug:warn(`No upgrades available for {buildingType}`)
		return false
	end

	local currentLevel = BuildingLevels[building] or 1
	if currentLevel >= upgrade.maxLevel then
		UpgradeDebug:warn(`{buildingType} already at max level`)
		return false
	end

	local tier = upgrade.tiers[currentLevel]
	if not tier then
		UpgradeDebug:warn(`No tier data for level {currentLevel + 1}`)
		return false
	end

	-- Check resources
	if not PlayerManager.hasEnoughResources(player, tier.cost) then
		UpgradeDebug:warn(`{player.Name} cannot afford upgrade for {buildingType}`)
		return false
	end

	-- Deduct resources
	PlayerManager.deductResources(player, tier.cost)

	-- Apply upgrade
	BuildingLevels[building] = tier.level
	building:SetAttribute("UpgradeLevel", tier.level)
	applyUpgradeEffects(building, tier)

	UpgradeDebug:info(`{player.Name} upgraded {buildingType} to level {tier.level}`)

	-- Notify client
	local remoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")
	if remoteEvents then
		local gameEvent = remoteEvents:FindFirstChild("GameEvent")
		if gameEvent and gameEvent:IsA("RemoteEvent") then
			gameEvent:FireClient(player, "BuildingUpgraded", {
				buildingId = building.Name,
				buildingType = buildingType,
				level = tier.level,
				description = tier.description,
			})
		end
	end

	return true
end

function UpgradeManager.getBuildingLevel(building: Instance): number
	return BuildingLevels[building] or 1
end

function UpgradeManager.getAvailableUpgrades(): { [string]: BuildingUpgrade }
	return UPGRADES
end

function UpgradeManager.init()
	UpgradeDebug:info("UpgradeManager initialized", {
		buildingsWithUpgrades = 0,
	})

	local count = 0
	for _ in pairs(UPGRADES) do
		count += 1
	end

	UpgradeDebug:info(`{count} building types have upgrade paths`)
end

return UpgradeManager
