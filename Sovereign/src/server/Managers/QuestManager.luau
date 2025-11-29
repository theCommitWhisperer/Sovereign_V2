--!strict
-- QuestManager: Quest and mission system for structured objectives
-- Features: Quest tracking, rewards, progression

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local GameData = require(ReplicatedStorage.Shared.GameData)
local PlayerManager = require(script.Parent.PlayerManager)
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)

local QuestDebug = DebugManager.createChannel("Quests", false)

local QuestManager = {}

-- ═══════════════════════════════════════════════════════════════════════════
-- TYPES
-- ═══════════════════════════════════════════════════════════════════════════

export type QuestObjective = {
	type: string,
	target: string | number,
	current: number,
	required: number,
	description: string,
}

export type QuestReward = {
	resources: { [string]: number }?,
	unlocks: { string }?,
	experience: number?,
}

export type Quest = {
	id: string,
	name: string,
	description: string,
	objectives: { QuestObjective },
	rewards: QuestReward,
	isCompleted: boolean,
	isActive: boolean,
}

-- Track player quests
local PlayerQuests: { [number]: { [string]: Quest } } = {}

-- ═══════════════════════════════════════════════════════════════════════════
-- QUEST DEFINITIONS
-- ═══════════════════════════════════════════════════════════════════════════

local QUEST_TEMPLATES: { [string]: Quest } = {
	FirstSteps = {
		id = "FirstSteps",
		name = "First Steps",
		description = "Build your first structures",
		objectives = {
			{
				type = "BuildBuilding",
				target = "Farm",
				current = 0,
				required = 1,
				description = "Build a Farm",
			},
			{
				type = "BuildBuilding",
				target = "Woodcutters_Post",
				current = 0,
				required = 1,
				description = "Build a Woodcutter's Post",
			},
		},
		rewards = {
			resources = { Wood = 200, Stone = 100, Gold = 150 },
		},
		isCompleted = false,
		isActive = true,
	},

	GrowYourKingdom = {
		id = "GrowYourKingdom",
		name = "Grow Your Kingdom",
		description = "Expand your population",
		objectives = {
			{
				type = "ReachPopulation",
				target = 50,
				current = 0,
				required = 50,
				description = "Reach a population of 50",
			},
			{
				type = "BuildBuilding",
				target = "Hovel",
				current = 0,
				required = 3,
				description = "Build 3 Hovels",
			},
		},
		rewards = {
			resources = { Wood = 300, Stone = 200, Gold = 250 },
		},
		isCompleted = false,
		isActive = true,
	},

	MilitaryMight = {
		id = "MilitaryMight",
		name = "Military Might",
		description = "Build a strong army",
		objectives = {
			{
				type = "TrainUnits",
				target = "Any",
				current = 0,
				required = 10,
				description = "Train 10 military units",
			},
			{
				type = "BuildBuilding",
				target = "Barracks",
				current = 0,
				required = 1,
				description = "Build a Barracks",
			},
		},
		rewards = {
			resources = { Wood = 400, Stone = 300, Gold = 400, Weapons = 20 },
		},
		isCompleted = false,
		isActive = true,
	},

	VikingSlayer = {
		id = "VikingSlayer",
		name = "Viking Slayer",
		description = "Defend against Viking raids",
		objectives = {
			{
				type = "KillEnemies",
				target = "Viking",
				current = 0,
				required = 10,
				description = "Defeat 10 Vikings",
			},
		},
		rewards = {
			resources = { Gold = 500, Weapons = 30 },
		},
		isCompleted = false,
		isActive = true,
	},

	EconomicPowerhouse = {
		id = "EconomicPowerhouse",
		name = "Economic Powerhouse",
		description = "Accumulate wealth",
		objectives = {
			{
				type = "AccumulateResource",
				target = "Gold",
				current = 0,
				required = 2000,
				description = "Accumulate 2000 Gold",
			},
			{
				type = "AccumulateResource",
				target = "Wood",
				current = 0,
				required = 3000,
				description = "Accumulate 3000 Wood",
			},
		},
		rewards = {
			resources = { Gold = 1000 },
		},
		isCompleted = false,
		isActive = true,
	},

	Fortify = {
		id = "Fortify",
		name = "Fortify Your Borders",
		description = "Build strong defenses",
		objectives = {
			{
				type = "BuildBuilding",
				target = "Stone_Wall",
				current = 0,
				required = 20,
				description = "Build 20 Wall segments",
			},
			{
				type = "BuildBuilding",
				target = "Wall_Tower",
				current = 0,
				required = 2,
				description = "Build 2 Wall Towers",
			},
		},
		rewards = {
			resources = { Stone = 500, Iron_Bars = 100, Gold = 300 },
		},
		isCompleted = false,
		isActive = true,
	},

	MasterCrafter = {
		id = "MasterCrafter",
		name = "Master Crafter",
		description = "Develop your production",
		objectives = {
			{
				type = "BuildBuilding",
				target = "Smithy",
				current = 0,
				required = 1,
				description = "Build a Smithy",
			},
			{
				type = "ProduceResource",
				target = "Iron_Bars",
				current = 0,
				required = 100,
				description = "Produce 100 Iron Bars",
			},
		},
		rewards = {
			resources = { Iron_Bars = 50, Weapons = 25, Gold = 200 },
		},
		isCompleted = false,
		isActive = true,
	},
}

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPER FUNCTIONS
-- ═══════════════════════════════════════════════════════════════════════════

local function checkQuestCompletion(player: Player, quest: Quest): boolean
	for _, objective in quest.objectives do
		if objective.current < objective.required then
			return false
		end
	end
	return true
end

local function giveQuestRewards(player: Player, quest: Quest)
	local rewards = quest.rewards

	-- Give resource rewards
	if rewards.resources then
		PlayerManager.addResources(player, rewards.resources)
		QuestDebug:info(`Gave resources to {player.Name}`, rewards.resources)
	end

	-- Handle unlocks
	if rewards.unlocks then
		local playerData = PlayerManager.get(player)
		if playerData then
			if not playerData.Unlocks then
				playerData.Unlocks = {}
			end
			for _, unlock in rewards.unlocks do
				playerData.Unlocks[unlock] = true
			end
		end
	end
end

local function notifyQuestProgress(player: Player, quest: Quest)
	local remoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")
	if not remoteEvents then
		return
	end

	local gameEvent = remoteEvents:FindFirstChild("GameEvent")
	if not gameEvent or not gameEvent:IsA("RemoteEvent") then
		return
	end

	gameEvent:FireClient(player, "QuestProgress", {
		questId = quest.id,
		questName = quest.name,
		objectives = quest.objectives,
		isCompleted = quest.isCompleted,
	})
end

-- ═══════════════════════════════════════════════════════════════════════════
-- PUBLIC API
-- ═══════════════════════════════════════════════════════════════════════════

function QuestManager.initializePlayerQuests(player: Player)
	if PlayerQuests[player.UserId] then
		return
	end

	PlayerQuests[player.UserId] = {}

	-- Give starter quests
	local starterQuests = { "FirstSteps", "GrowYourKingdom" }
	for _, questId in starterQuests do
		local template = QUEST_TEMPLATES[questId]
		if template then
			PlayerQuests[player.UserId][questId] = table.clone(template)
			-- Deep clone objectives
			local objectives = {}
			for _, obj in template.objectives do
				table.insert(objectives, table.clone(obj))
			end
			PlayerQuests[player.UserId][questId].objectives = objectives
		end
	end

	QuestDebug:info(`Initialized quests for {player.Name}`)
end

function QuestManager.updateQuestProgress(
	player: Player,
	objectiveType: string,
	target: string | number,
	amount: number?
)
	local playerQuests = PlayerQuests[player.UserId]
	if not playerQuests then
		return
	end

	amount = amount or 1

	for questId, quest in playerQuests do
		if quest.isCompleted or not quest.isActive then
			continue
		end

		local progressMade = false
		for _, objective in quest.objectives do
			if objective.type == objectiveType then
				-- Check if target matches
				local targetMatches = objective.target == target or objective.target == "Any"

				if targetMatches then
					objective.current = math.min(objective.current + amount, objective.required)
					progressMade = true
				end
			end
		end

		if progressMade then
			-- Check if quest is completed
			if checkQuestCompletion(player, quest) then
				quest.isCompleted = true
				giveQuestRewards(player, quest)

				QuestDebug:info(`{player.Name} completed quest: {quest.name}`)

				-- Notify client
				local remoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")
				if remoteEvents then
					local gameEvent = remoteEvents:FindFirstChild("GameEvent")
					if gameEvent and gameEvent:IsA("RemoteEvent") then
						gameEvent:FireClient(player, "QuestCompleted", {
							questId = quest.id,
							questName = quest.name,
							rewards = quest.rewards,
						})
					end
				end
			else
				-- Send progress update
				notifyQuestProgress(player, quest)
			end
		end
	end
end

function QuestManager.getActiveQuests(player: Player): { Quest }
	local playerQuests = PlayerQuests[player.UserId]
	if not playerQuests then
		return {}
	end

	local activeQuests = {}
	for _, quest in playerQuests do
		if quest.isActive and not quest.isCompleted then
			table.insert(activeQuests, quest)
		end
	end

	return activeQuests
end

function QuestManager.getCompletedQuests(player: Player): { Quest }
	local playerQuests = PlayerQuests[player.UserId]
	if not playerQuests then
		return {}
	end

	local completedQuests = {}
	for _, quest in playerQuests do
		if quest.isCompleted then
			table.insert(completedQuests, quest)
		end
	end

	return completedQuests
end

function QuestManager.unlockQuest(player: Player, questId: string): boolean
	local template = QUEST_TEMPLATES[questId]
	if not template then
		QuestDebug:warn(`Unknown quest: {questId}`)
		return false
	end

	local playerQuests = PlayerQuests[player.UserId]
	if not playerQuests then
		QuestManager.initializePlayerQuests(player)
		playerQuests = PlayerQuests[player.UserId]
	end

	-- Check if already has quest
	if playerQuests[questId] then
		return false
	end

	-- Clone template
	playerQuests[questId] = table.clone(template)
	local objectives = {}
	for _, obj in template.objectives do
		table.insert(objectives, table.clone(obj))
	end
	playerQuests[questId].objectives = objectives

	QuestDebug:info(`Unlocked quest {questId} for {player.Name}`)

	-- Notify client
	local remoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")
	if remoteEvents then
		local gameEvent = remoteEvents:FindFirstChild("GameEvent")
		if gameEvent and gameEvent:IsA("RemoteEvent") then
			gameEvent:FireClient(player, "QuestUnlocked", {
				questId = questId,
				questName = template.name,
				description = template.description,
			})
		end
	end

	return true
end

function QuestManager.init()
	local count = 0
	for _ in pairs(QUEST_TEMPLATES) do
		count += 1
	end

	QuestDebug:info("QuestManager initialized", {
		questTemplatesCount = count,
	})

	-- Initialize quests for existing players
	for _, player in Players:GetPlayers() do
		QuestManager.initializePlayerQuests(player)
	end
end

return QuestManager
