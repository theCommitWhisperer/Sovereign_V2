--!strict
-- ResearchManager: Technology tree and research system
-- Features: Unlockable upgrades, tech progression, strategic bonuses

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameData = require(ReplicatedStorage.Shared.GameData)
local PlayerManager = require(script.Parent.PlayerManager)
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)

local ResearchDebug = DebugManager.createChannel("Research", false)

local ResearchManager = {}

-- ═══════════════════════════════════════════════════════════════════════════
-- TYPES
-- ═══════════════════════════════════════════════════════════════════════════

export type Technology = {
	id: string,
	name: string,
	description: string,
	cost: { [string]: number },
	researchTime: number,
	prerequisites: { string }?,
	category: string,
	effects: { [string]: any },
}

type ResearchProgress = {
	techId: string,
	startTime: number,
	completeTime: number,
}

-- Track player research
local PlayerTechnologies: { [number]: { [string]: boolean } } = {}
local PlayerResearchQueue: { [number]: ResearchProgress? } = {}

-- ═══════════════════════════════════════════════════════════════════════════
-- TECHNOLOGY DEFINITIONS
-- ═══════════════════════════════════════════════════════════════════════════

local TECHNOLOGIES: { [string]: Technology } = {
	-- ECONOMY TECHS
	ImprovedTools = {
		id = "ImprovedTools",
		name = "Improved Tools",
		description = "Increase all resource gathering by 15%",
		cost = { Wood = 200, Stone = 100, Gold = 150 },
		researchTime = 60,
		category = "Economy",
		effects = {
			resourceGatheringBonus = 1.15,
		},
	},

	StoneMasonry = {
		id = "StoneMasonry",
		name = "Stone Masonry",
		description = "Increase stone production by 25%",
		cost = { Stone = 300, Gold = 200 },
		researchTime = 45,
		category = "Economy",
		effects = {
			stoneProductionBonus = 1.25,
		},
	},

	IronWorking = {
		id = "IronWorking",
		name = "Iron Working",
		description = "Unlock advanced iron processing, +30% iron production",
		cost = { Stone = 250, Iron_Ore = 100, Gold = 300 },
		researchTime = 90,
		prerequisites = { "StoneMasonry" },
		category = "Economy",
		effects = {
			ironProductionBonus = 1.30,
			unlocksBuildings = { "Advanced_Smithy" },
		},
	},

	Agriculture = {
		id = "Agriculture",
		name = "Agriculture",
		description = "Increase food production by 20%",
		cost = { Wood = 150, Gold = 100 },
		researchTime = 50,
		category = "Economy",
		effects = {
			foodProductionBonus = 1.20,
		},
	},

	AdvancedFarming = {
		id = "AdvancedFarming",
		name = "Advanced Farming",
		description = "Increase food production by 35%, reduces consumption by 10%",
		cost = { Wood = 300, Stone = 150, Gold = 250 },
		researchTime = 75,
		prerequisites = { "Agriculture" },
		category = "Economy",
		effects = {
			foodProductionBonus = 1.35,
			foodConsumptionReduction = 0.90,
		},
	},

	-- MILITARY TECHS
	BetterArmor = {
		id = "BetterArmor",
		name = "Better Armor",
		description = "Increase all unit armor by 2 points",
		cost = { Iron_Bars = 150, Gold = 250 },
		researchTime = 70,
		category = "Military",
		effects = {
			armorBonus = 2,
		},
	},

	WeaponForging = {
		id = "WeaponForging",
		name = "Weapon Forging",
		description = "Increase all unit attack damage by 15%",
		cost = { Iron_Bars = 200, Gold = 300 },
		researchTime = 80,
		category = "Military",
		effects = {
			damageBonus = 1.15,
		},
	},

	MasterWeaponsmithing = {
		id = "MasterWeaponsmithing",
		name = "Master Weaponsmithing",
		description = "Increase all unit attack damage by 30%",
		cost = { Iron_Bars = 400, Weapons = 50, Gold = 600 },
		researchTime = 120,
		prerequisites = { "WeaponForging" },
		category = "Military",
		effects = {
			damageBonus = 1.30,
		},
	},

	Tactics = {
		id = "Tactics",
		name = "Tactics",
		description = "Units start with +10 morale",
		cost = { Gold = 200 },
		researchTime = 60,
		category = "Military",
		effects = {
			startingMoraleBonus = 10,
		},
	},

	EliteTraining = {
		id = "EliteTraining",
		name = "Elite Training",
		description = "Reduce training time by 25%, +15 starting morale",
		cost = { Gold = 500, Weapons = 30 },
		researchTime = 100,
		prerequisites = { "Tactics" },
		category = "Military",
		effects = {
			trainingSpeedBonus = 0.75,
			startingMoraleBonus = 15,
		},
	},

	Conscription = {
		id = "Conscription",
		name = "Conscription",
		description = "Reduce unit training cost by 20%",
		cost = { Gold = 300 },
		researchTime = 70,
		category = "Military",
		effects = {
			unitCostReduction = 0.80,
		},
	},

	-- BUILDING TECHS
	Architecture = {
		id = "Architecture",
		name = "Architecture",
		description = "Reduce building costs by 15%",
		cost = { Wood = 250, Stone = 200, Gold = 200 },
		researchTime = 80,
		category = "Building",
		effects = {
			buildingCostReduction = 0.85,
		},
	},

	Fortification = {
		id = "Fortification",
		name = "Fortification",
		description = "Increase all building health by 30%",
		cost = { Stone = 400, Gold = 300 },
		researchTime = 90,
		category = "Building",
		effects = {
			buildingHealthBonus = 1.30,
		},
	},

	AdvancedFortification = {
		id = "AdvancedFortification",
		name = "Advanced Fortification",
		description = "Increase building health by 60%, unlock advanced defenses",
		cost = { Stone = 800, Iron_Bars = 200, Gold = 600 },
		researchTime = 150,
		prerequisites = { "Fortification" },
		category = "Building",
		effects = {
			buildingHealthBonus = 1.60,
			unlocksBuildings = { "Round_Tower", "Arrow_Tower" },
		},
	},

	-- SPECIAL TECHS
	TradeRoutes = {
		id = "TradeRoutes",
		name = "Trade Routes",
		description = "Increase gold income by 25%",
		cost = { Gold = 400 },
		researchTime = 75,
		category = "Special",
		effects = {
			goldIncomeBonus = 1.25,
		},
	},

	CelticHeritage = {
		id = "CelticHeritage",
		name = "Celtic Heritage",
		description = "Irish units gain +20% morale and +10% damage",
		cost = { Gold = 500 },
		researchTime = 100,
		category = "Special",
		effects = {
			irishMoraleBonus = 1.20,
			irishDamageBonus = 1.10,
		},
	},
}

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPER FUNCTIONS
-- ═══════════════════════════════════════════════════════════════════════════

local function hasPrerequisites(player: Player, tech: Technology): boolean
	if not tech.prerequisites then
		return true
	end

	local playerTechs = PlayerTechnologies[player.UserId]
	if not playerTechs then
		return false
	end

	for _, prereqId in tech.prerequisites do
		if not playerTechs[prereqId] then
			return false
		end
	end

	return true
end

local function applyTechnologyEffects(player: Player, tech: Technology)
	local playerData = PlayerManager.get(player)
	if not playerData then
		return
	end

	-- Create research bonuses table if it doesn't exist
	if not playerData.ResearchBonuses then
		playerData.ResearchBonuses = {}
	end

	-- Store effects for later use
	for effectName, value in pairs(tech.effects) do
		playerData.ResearchBonuses[effectName] = value
	end

	ResearchDebug:info(`Applied effects for {tech.name} to {player.Name}`)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- PUBLIC API
-- ═══════════════════════════════════════════════════════════════════════════

function ResearchManager.canResearch(player: Player, techId: string): boolean
	local tech = TECHNOLOGIES[techId]
	if not tech then
		return false
	end

	-- Check if already researched
	local playerTechs = PlayerTechnologies[player.UserId]
	if playerTechs and playerTechs[techId] then
		return false
	end

	-- Check if already researching something
	if PlayerResearchQueue[player.UserId] then
		return false
	end

	-- Check prerequisites
	if not hasPrerequisites(player, tech) then
		return false
	end

	-- Check resources
	return PlayerManager.hasEnoughResources(player, tech.cost)
end

function ResearchManager.startResearch(player: Player, techId: string): boolean
	local tech = TECHNOLOGIES[techId]
	if not tech then
		ResearchDebug:warn(`Unknown technology: {techId}`)
		return false
	end

	if not ResearchManager.canResearch(player, techId) then
		ResearchDebug:warn(`{player.Name} cannot research {techId}`)
		return false
	end

	-- Deduct resources
	PlayerManager.deductResources(player, tech.cost)

	-- Start research
	local currentTime = tick()
	PlayerResearchQueue[player.UserId] = {
		techId = techId,
		startTime = currentTime,
		completeTime = currentTime + tech.researchTime,
	}

	ResearchDebug:info(`{player.Name} started researching {tech.name} ({tech.researchTime}s)`)

	-- Notify client
	local remoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")
	if remoteEvents then
		local gameEvent = remoteEvents:FindFirstChild("GameEvent")
		if gameEvent and gameEvent:IsA("RemoteEvent") then
			gameEvent:FireClient(player, "ResearchStarted", {
				techId = techId,
				techName = tech.name,
				completeTime = currentTime + tech.researchTime,
			})
		end
	end

	-- Schedule completion
	task.delay(tech.researchTime, function()
		ResearchManager.completeResearch(player, techId)
	end)

	return true
end

function ResearchManager.completeResearch(player: Player, techId: string)
	local tech = TECHNOLOGIES[techId]
	if not tech then
		return
	end

	-- Remove from queue
	PlayerResearchQueue[player.UserId] = nil

	-- Mark as researched
	if not PlayerTechnologies[player.UserId] then
		PlayerTechnologies[player.UserId] = {}
	end
	PlayerTechnologies[player.UserId][techId] = true

	-- Apply effects
	applyTechnologyEffects(player, tech)

	ResearchDebug:info(`{player.Name} completed research: {tech.name}`)

	-- Notify client
	local remoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")
	if remoteEvents then
		local gameEvent = remoteEvents:FindFirstChild("GameEvent")
		if gameEvent and gameEvent:IsA("RemoteEvent") then
			gameEvent:FireClient(player, "ResearchCompleted", {
				techId = techId,
				techName = tech.name,
				description = tech.description,
			})
		end
	end
end

function ResearchManager.hasResearched(player: Player, techId: string): boolean
	local playerTechs = PlayerTechnologies[player.UserId]
	return playerTechs and playerTechs[techId] or false
end

function ResearchManager.getResearchedTechnologies(player: Player): { string }
	local researched = {}
	local playerTechs = PlayerTechnologies[player.UserId]

	if not playerTechs then
		return researched
	end

	for techId, _ in pairs(playerTechs) do
		table.insert(researched, techId)
	end

	return researched
end

function ResearchManager.getCurrentResearch(player: Player): ResearchProgress?
	return PlayerResearchQueue[player.UserId]
end

function ResearchManager.getAllTechnologies(): { [string]: Technology }
	return TECHNOLOGIES
end

function ResearchManager.getBonus(player: Player, bonusName: string): any
	local playerData = PlayerManager.get(player)
	if not playerData or not playerData.ResearchBonuses then
		return nil
	end

	return playerData.ResearchBonuses[bonusName]
end

function ResearchManager.init()
	local count = 0
	for _ in pairs(TECHNOLOGIES) do
		count += 1
	end

	ResearchDebug:info("ResearchManager initialized", {
		technologiesCount = count,
	})
end

return ResearchManager
