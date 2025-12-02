--!strict
-- AchievementManager: Achievement tracking and rewards
-- Features: Permanent achievements, stat tracking, milestone rewards

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local GameData = require(ReplicatedStorage.Shared.GameData)
local PlayerManager = require(script.Parent.PlayerManager)
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)

local AchievementDebug = DebugManager.createChannel("Achievements", false)

local AchievementManager = {}

-- ═══════════════════════════════════════════════════════════════════════════
-- TYPES
-- ═══════════════════════════════════════════════════════════════════════════

export type Achievement = {
	id: string,
	name: string,
	description: string,
	category: string,
	requirement: number,
	statToTrack: string,
	reward: { [string]: number }?,
	isUnlocked: boolean,
}

-- Track player achievements
local PlayerAchievements: { [number]: { [string]: Achievement } } = {}
local PlayerStats: { [number]: { [string]: number } } = {}

-- ═══════════════════════════════════════════════════════════════════════════
-- ACHIEVEMENT DEFINITIONS
-- ═══════════════════════════════════════════════════════════════════════════

local ACHIEVEMENTS: { [string]: Achievement } = {
	-- BUILDING ACHIEVEMENTS
	FirstBuilder = {
		id = "FirstBuilder",
		name = "First Builder",
		description = "Build your first structure",
		category = "Building",
		requirement = 1,
		statToTrack = "BuildingsBuilt",
		reward = { Gold = 50 },
		isUnlocked = false,
	},

	ArchitectApprentice = {
		id = "ArchitectApprentice",
		name = "Architect Apprentice",
		description = "Build 25 structures",
		category = "Building",
		requirement = 25,
		statToTrack = "BuildingsBuilt",
		reward = { Wood = 500, Stone = 300, Gold = 200 },
		isUnlocked = false,
	},

	MasterBuilder = {
		id = "MasterBuilder",
		name = "Master Builder",
		description = "Build 100 structures",
		category = "Building",
		requirement = 100,
		statToTrack = "BuildingsBuilt",
		reward = { Wood = 2000, Stone = 1500, Gold = 1000 },
		isUnlocked = false,
	},

	-- MILITARY ACHIEVEMENTS
	FirstBlood = {
		id = "FirstBlood",
		name = "First Blood",
		description = "Defeat your first enemy",
		category = "Military",
		requirement = 1,
		statToTrack = "EnemiesKilled",
		reward = { Gold = 100 },
		isUnlocked = false,
	},

	Warrior = {
		id = "Warrior",
		name = "Warrior",
		description = "Defeat 50 enemies",
		category = "Military",
		requirement = 50,
		statToTrack = "EnemiesKilled",
		reward = { Weapons = 20, Gold = 300 },
		isUnlocked = false,
	},

	Conqueror = {
		id = "Conqueror",
		name = "Conqueror",
		description = "Defeat 200 enemies",
		category = "Military",
		requirement = 200,
		statToTrack = "EnemiesKilled",
		reward = { Weapons = 100, Gold = 1000 },
		isUnlocked = false,
	},

	VikingBane = {
		id = "VikingBane",
		name = "Viking Bane",
		description = "Defeat 100 Vikings",
		category = "Military",
		requirement = 100,
		statToTrack = "VikingsKilled",
		reward = { Gold = 800, Weapons = 50 },
		isUnlocked = false,
	},

	ArmyCommander = {
		id = "ArmyCommander",
		name = "Army Commander",
		description = "Train 100 units",
		category = "Military",
		requirement = 100,
		statToTrack = "UnitsTrained",
		reward = { Weapons = 50, Gold = 500 },
		isUnlocked = false,
	},

	-- ECONOMY ACHIEVEMENTS
	ResourceGatherer = {
		id = "ResourceGatherer",
		name = "Resource Gatherer",
		description = "Collect 10,000 total resources",
		category = "Economy",
		requirement = 10000,
		statToTrack = "ResourcesGathered",
		reward = { Gold = 300 },
		isUnlocked = false,
	},

	WealthyMerchant = {
		id = "WealthyMerchant",
		name = "Wealthy Merchant",
		description = "Accumulate 5,000 Gold",
		category = "Economy",
		requirement = 5000,
		statToTrack = "GoldEarned",
		reward = { Gold = 1000 },
		isUnlocked = false,
	},

	EconomicTitan = {
		id = "EconomicTitan",
		name = "Economic Titan",
		description = "Collect 100,000 total resources",
		category = "Economy",
		requirement = 100000,
		statToTrack = "ResourcesGathered",
		reward = { Wood = 3000, Stone = 2000, Gold = 2000 },
		isUnlocked = false,
	},

	-- POPULATION ACHIEVEMENTS
	Settler = {
		id = "Settler",
		name = "Settler",
		description = "Reach a population of 25",
		category = "Population",
		requirement = 25,
		statToTrack = "MaxPopulation",
		reward = { Food = 200, Gold = 100 },
		isUnlocked = false,
	},

	TownMayor = {
		id = "TownMayor",
		name = "Town Mayor",
		description = "Reach a population of 100",
		category = "Population",
		requirement = 100,
		statToTrack = "MaxPopulation",
		reward = { Food = 500, Gold = 300 },
		isUnlocked = false,
	},

	CityLord = {
		id = "CityLord",
		name = "City Lord",
		description = "Reach a population of 250",
		category = "Population",
		requirement = 250,
		statToTrack = "MaxPopulation",
		reward = { Food = 1000, Gold = 800 },
		isUnlocked = false,
	},

	-- SPECIAL ACHIEVEMENTS
	Survivor = {
		id = "Survivor",
		name = "Survivor",
		description = "Survive 10 Viking raids",
		category = "Special",
		requirement = 10,
		statToTrack = "RaidsSurvived",
		reward = { Gold = 500, Weapons = 30 },
		isUnlocked = false,
	},

	Researcher = {
		id = "Researcher",
		name = "Researcher",
		description = "Complete 5 technologies",
		category = "Special",
		requirement = 5,
		statToTrack = "TechnologiesResearched",
		reward = { Gold = 400 },
		isUnlocked = false,
	},

	QuestMaster = {
		id = "QuestMaster",
		name = "Quest Master",
		description = "Complete 10 quests",
		category = "Special",
		requirement = 10,
		statToTrack = "QuestsCompleted",
		reward = { Gold = 600 },
		isUnlocked = false,
	},

	Defender = {
		id = "Defender",
		name = "Defender",
		description = "Build 50 defensive structures",
		category = "Special",
		requirement = 50,
		statToTrack = "DefensesBuilt",
		reward = { Stone = 800, Iron_Bars = 100 },
		isUnlocked = false,
	},
}

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPER FUNCTIONS
-- ═══════════════════════════════════════════════════════════════════════════

local function unlockAchievement(player: Player, achievement: Achievement)
	achievement.isUnlocked = true

	-- Give rewards
	if achievement.reward then
		PlayerManager.addResources(player, achievement.reward)
	end

	AchievementDebug:info(`{player.Name} unlocked achievement: {achievement.name}`)

	-- Notify client
	local remoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")
	if remoteEvents then
		local gameEvent = remoteEvents:FindFirstChild("GameEvent")
		if gameEvent and gameEvent:IsA("RemoteEvent") then
			gameEvent:FireClient(player, "AchievementUnlocked", {
				achievementId = achievement.id,
				achievementName = achievement.name,
				description = achievement.description,
				reward = achievement.reward,
			})
		end
	end
end

local function checkAchievements(player: Player)
	local playerAchievements = PlayerAchievements[player.UserId]
	local playerStats = PlayerStats[player.UserId]

	if not playerAchievements or not playerStats then
		return
	end

	for _, achievement in playerAchievements do
		if not achievement.isUnlocked then
			local currentStat = playerStats[achievement.statToTrack] or 0
			if currentStat >= achievement.requirement then
				unlockAchievement(player, achievement)
			end
		end
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- PUBLIC API
-- ═══════════════════════════════════════════════════════════════════════════

function AchievementManager.initializePlayer(player: Player)
	if PlayerAchievements[player.UserId] then
		return
	end

	-- Clone all achievements for player
	PlayerAchievements[player.UserId] = {}
	for achievementId, achievement in pairs(ACHIEVEMENTS) do
		PlayerAchievements[player.UserId][achievementId] = table.clone(achievement)
	end

	-- Initialize stats
	PlayerStats[player.UserId] = {
		BuildingsBuilt = 0,
		EnemiesKilled = 0,
		VikingsKilled = 0,
		UnitsTrained = 0,
		ResourcesGathered = 0,
		GoldEarned = 0,
		MaxPopulation = 0,
		RaidsSurvived = 0,
		TechnologiesResearched = 0,
		QuestsCompleted = 0,
		DefensesBuilt = 0,
	}

	AchievementDebug:info(`Initialized achievements for {player.Name}`)
end

function AchievementManager.incrementStat(player: Player, statName: string, amount: number?)
	amount = amount or 1

	if not PlayerStats[player.UserId] then
		AchievementManager.initializePlayer(player)
	end

	if not PlayerStats[player.UserId][statName] then
		AchievementDebug:warn(`Unknown stat: {statName}`)
		return
	end

	PlayerStats[player.UserId][statName] = PlayerStats[player.UserId][statName] + amount

	-- Check for newly unlocked achievements
	checkAchievements(player)
end

function AchievementManager.setStat(player: Player, statName: string, value: number)
	if not PlayerStats[player.UserId] then
		AchievementManager.initializePlayer(player)
	end

	if not PlayerStats[player.UserId][statName] then
		AchievementDebug:warn(`Unknown stat: {statName}`)
		return
	end

	-- Only update if new value is higher (for "max" stats like population)
	if value > PlayerStats[player.UserId][statName] then
		PlayerStats[player.UserId][statName] = value
		checkAchievements(player)
	end
end

function AchievementManager.getUnlockedAchievements(player: Player): { Achievement }
	local playerAchievements = PlayerAchievements[player.UserId]
	if not playerAchievements then
		return {}
	end

	local unlocked = {}
	for _, achievement in playerAchievements do
		if achievement.isUnlocked then
			table.insert(unlocked, achievement)
		end
	end

	return unlocked
end

function AchievementManager.getLockedAchievements(player: Player): { Achievement }
	local playerAchievements = PlayerAchievements[player.UserId]
	if not playerAchievements then
		return {}
	end

	local locked = {}
	for _, achievement in playerAchievements do
		if not achievement.isUnlocked then
			table.insert(locked, achievement)
		end
	end

	return locked
end

function AchievementManager.getStats(player: Player): { [string]: number }
	return PlayerStats[player.UserId] or {}
end

function AchievementManager.init()
	local count = 0
	for _ in pairs(ACHIEVEMENTS) do
		count += 1
	end

	AchievementDebug:info("AchievementManager initialized", {
		achievementsCount = count,
	})

	-- Initialize for existing players
	for _, player in Players:GetPlayers() do
		AchievementManager.initializePlayer(player)
	end
end

return AchievementManager
