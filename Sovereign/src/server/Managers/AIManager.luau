--!strict
-- AIManager: Controls AI player behavior - building, resource management, unit training, and combat

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local DebugManager = require(ReplicatedStorage.Shared.DebugManager)
local AIDebug = DebugManager.createChannel("AIManager", true)

local GameData = require(ReplicatedStorage.Shared.GameData)
local UnitManager = require(script.Parent.UnitManager)
local BuildingManager = require(script.Parent.BuildingManager)

local AIManager = {}

-- AI Difficulty settings
export type AIDifficulty = "Easy" | "Medium" | "Hard"

type DifficultyConfig = {
	buildInterval: number,
	trainInterval: number,
	resourceMultiplier: number,
	maxConcurrentBuildings: number,
	aggressiveness: number, -- 0-1, affects unit training frequency
	startDelay: number,
	retreatThreshold: number, -- How many enemies before retreating
	attackWaveSize: number, -- Minimum units needed to attack
}

local DIFFICULTY_CONFIGS: { [AIDifficulty]: DifficultyConfig } = {
	Easy = {
		buildInterval = 60, -- Builds every 60 seconds
		trainInterval = 40, -- Trains units every 40 seconds
		resourceMultiplier = 0.5, -- Gets 50% normal resources
		maxConcurrentBuildings = 2, -- Max 2 buildings at once
		aggressiveness = 0.3, -- 30% chance to train aggressive units
		startDelay = 15, -- Waits 15 seconds before starting
		retreatThreshold = 3, -- Retreats when 3+ enemies nearby
		attackWaveSize = 5, -- Needs 5 units to attack
	},
	Medium = {
		buildInterval = 35, -- Builds every 35 seconds
		trainInterval = 25, -- Trains units every 25 seconds
		resourceMultiplier = 1.0, -- Gets 100% normal resources
		maxConcurrentBuildings = 3, -- Max 3 buildings at once
		aggressiveness = 0.6, -- 60% chance to train aggressive units
		startDelay = 8, -- Waits 8 seconds before starting
		retreatThreshold = 5, -- Retreats when 5+ enemies nearby
		attackWaveSize = 3, -- Needs 3 units to attack
	},
	Hard = {
		buildInterval = 20, -- Builds every 20 seconds
		trainInterval = 15, -- Trains units every 15 seconds
		resourceMultiplier = 1.5, -- Gets 150% normal resources (cheats more)
		maxConcurrentBuildings = 5, -- Max 5 buildings at once
		aggressiveness = 0.9, -- 90% chance to train aggressive units
		startDelay = 3, -- Waits only 3 seconds before starting
		retreatThreshold = 8, -- Only retreats when 8+ enemies nearby (brave)
		attackWaveSize = 2, -- Needs only 2 units to attack (aggressive)
	},
}

-- AI player state tracking
type AIState = {
	ownerId: number,
	ownerName: string,
	faction: string,
	spawnPoint: CFrame,
	difficulty: AIDifficulty,
	hasKeep: boolean,
	hasStorehouse: boolean,
	hasGranary: boolean,
	lastBuildTime: number,
	lastTrainTime: number,
	resources: { [string]: number },
	buildings: { Instance },
	units: { Instance },
	buildingCount: number,
	-- AI Personality (adds randomness between AI players)
	preferredUnitType: string, -- Favorite unit to train
	buildingBias: string, -- "economy" or "military" - what to prioritize
	aggressionBonus: number, -- Extra aggression modifier (0.0 to 0.3)
}

local aiStates: { [number]: AIState } = {}
local AI_BASE_RESOURCE_AMOUNT = 50 -- Base resources AI gets periodically

-- Register an AI player with difficulty
function AIManager.registerAI(
	ownerId: number,
	ownerName: string,
	faction: string,
	spawnPoint: CFrame,
	difficulty: AIDifficulty?
)
	local aiDifficulty: AIDifficulty = difficulty or "Medium" -- Default to Medium

	-- Generate random AI personality for variety
	local unitTypes = { "Archer", "Knight", "Swordsman", "Macemen", "Light_Cavalry" }
	local preferredUnit = unitTypes[math.random(1, #unitTypes)]
	local buildingBias = if math.random() > 0.5 then "economy" else "military"
	local aggressionBonus = math.random() * 0.3 -- 0.0 to 0.3 extra aggression

	aiStates[ownerId] = {
		ownerId = ownerId,
		ownerName = ownerName,
		faction = faction,
		spawnPoint = spawnPoint,
		difficulty = aiDifficulty,
		hasKeep = false,
		hasStorehouse = false,
		hasGranary = false,
		lastBuildTime = 0,
		lastTrainTime = 0,
		resources = {
			Wood = 100,
			Stone = 100,
			Gold = 50,
			Food = 100,
			Iron_Bars = 20,
			Weapons = 10,
		},
		buildings = {},
		units = {},
		buildingCount = 0,
		-- Personality traits
		preferredUnitType = preferredUnit,
		buildingBias = buildingBias,
		aggressionBonus = aggressionBonus,
	}

	AIDebug:info(
		`Registered AI player: {ownerName} ({faction}) - Difficulty: {aiDifficulty}, Prefers: {preferredUnit}, Bias: {buildingBias}, Aggression: +{math.floor(aggressionBonus * 100)}%`
	)

	-- Start AI behavior loop
	task.spawn(function()
		AIManager.runAILoop(ownerId)
	end)
end

-- Main AI behavior loop
function AIManager.runAILoop(ownerId: number)
	local state = aiStates[ownerId]
	if not state then
		return
	end

	local config = DIFFICULTY_CONFIGS[state.difficulty]
	AIDebug:info(`Starting AI loop for {state.ownerName} - Difficulty: {state.difficulty}`)

	-- Initial setup delay to ensure units are spawned and settled
	task.wait(math.max(config.startDelay, 5)) -- At least 5 seconds delay

	-- Build Keep first (at spawn point - units are 50+ studs away)
	AIManager.buildKeep(ownerId)
	task.wait(2)

	-- Build Storehouse (40 studs from Keep for Wood/Stone/Iron)
	AIManager.buildStorehouse(ownerId)
	task.wait(2)

	-- Build Granary (for Food storage)
	AIManager.buildGranary(ownerId)
	task.wait(3)

	local attackTimer = 0
	local ATTACK_INTERVAL = 60 -- Launch attack wave every 60 seconds

	-- Main loop
	while state and aiStates[ownerId] do
		local currentTime = tick()

		-- Give AI resources periodically (AI cheat to keep them playing)
		AIManager.giveResources(ownerId)

		-- Build buildings periodically (based on difficulty)
		if currentTime - state.lastBuildTime >= config.buildInterval then
			AIManager.attemptBuilding(ownerId)
			state.lastBuildTime = currentTime
		end

		-- Train units periodically (based on difficulty)
		if currentTime - state.lastTrainTime >= config.trainInterval then
			AIManager.attemptTraining(ownerId)
			state.lastTrainTime = currentTime
		end

		-- Manage peasants (resource gathering)
		AIManager.managePeasants(ownerId)

		-- Check defensive status (respond to threats)
		AIManager.checkDefensiveStatus(ownerId)

		-- Command units to attack periodically
		attackTimer = attackTimer + 10
		if attackTimer >= ATTACK_INTERVAL then
			AIManager.launchAttackWave(ownerId)
			attackTimer = 0
		end

		-- Occasionally send scouts (every 45 seconds)
		if currentTime % 45 < 10 then
			AIManager.sendScout(ownerId)
		end

		task.wait(10) -- Check every 10 seconds
	end
end

-- Build the Keep for AI
function AIManager.buildKeep(ownerId: number)
	local state = aiStates[ownerId]
	if not state or state.hasKeep then
		return
	end

	-- Place Keep at spawn point (will be adjusted to ground height by placeBuilding)
	local keepPosition = state.spawnPoint
	local keep = AIManager.placeBuilding(ownerId, "Keep", keepPosition)

	if keep then
		state.hasKeep = true
		table.insert(state.buildings, keep)
		state.buildingCount += 1
		AIDebug:info(`{state.ownerName} built Keep`)
	else
		AIDebug:warn(`{state.ownerName} failed to build Keep`)
	end
end

-- Build Storehouse for AI
function AIManager.buildStorehouse(ownerId: number)
	local state = aiStates[ownerId]
	if not state or state.hasStorehouse then
		return
	end

	-- Place Storehouse near Keep (40 studs away to avoid overlap)
	local storehousePosition = state.spawnPoint * CFrame.new(40, 0, 0)
	local storehouse = AIManager.placeBuilding(ownerId, "Storehouse", storehousePosition)

	if storehouse then
		state.hasStorehouse = true
		table.insert(state.buildings, storehouse)
		state.buildingCount += 1
		AIDebug:info(`{state.ownerName} built Storehouse`)
	else
		AIDebug:warn(`{state.ownerName} failed to build Storehouse`)
	end
end

-- Build Granary for AI (food storage)
function AIManager.buildGranary(ownerId: number)
	local state = aiStates[ownerId]
	if not state or state.hasGranary then
		return
	end

	-- Place Granary 40 studs away in different direction from Storehouse
	local granaryPosition = state.spawnPoint * CFrame.new(0, 0, 40)
	local granary = AIManager.placeBuilding(ownerId, "Granary", granaryPosition)

	if granary then
		state.hasGranary = true
		table.insert(state.buildings, granary)
		state.buildingCount += 1
		AIDebug:info(`{state.ownerName} built Granary`)
	else
		AIDebug:warn(`{state.ownerName} failed to build Granary`)
	end
end

-- Attempt to build something
function AIManager.attemptBuilding(ownerId: number)
	local state = aiStates[ownerId]
	if not state then
		return
	end

	local config = DIFFICULTY_CONFIGS[state.difficulty]

	-- Check if AI has reached max building count for difficulty
	if state.buildingCount >= config.maxConcurrentBuildings + 3 then -- +3 for Keep, Storehouse, and Granary
		return
	end

	-- Count existing building types for strategic building
	local buildingCounts = {
		Barracks = 0,
		["Archery Range"] = 0,
		Lumbermill = 0,
		Farm = 0,
		["Stone Mine"] = 0,
	}

	for _, building in state.buildings do
		if building and building.Parent then
			local buildingType = building:GetAttribute("BuildingType")
			if buildingCounts[buildingType] then
				buildingCounts[buildingType] += 1
			end
		end
	end

	-- Strategic building selection based on AI personality and what's needed
	local buildingOptions = {}
	local economyBuildings = {}
	local militaryBuildings = {}

	-- Economy buildings
	if buildingCounts["Farm"] == 0 then
		table.insert(economyBuildings, "Farm")
	end
	if buildingCounts["Lumbermill"] == 0 then
		table.insert(economyBuildings, "Lumbermill")
	end
	if buildingCounts["Stone Mine"] == 0 then
		table.insert(economyBuildings, "Stone Mine")
	end

	-- Military buildings
	if buildingCounts["Barracks"] < 2 then
		table.insert(militaryBuildings, "Barracks")
	end
	if buildingCounts["Archery Range"] < 1 then
		table.insert(militaryBuildings, "Archery Range")
	end

	-- AI personality influences building priority
	if state.buildingBias == "economy" then
		-- Economy-focused AI: prioritize economy buildings
		for _, building in economyBuildings do
			table.insert(buildingOptions, building)
		end
		for _, building in militaryBuildings do
			table.insert(buildingOptions, building)
		end
	else
		-- Military-focused AI: prioritize military buildings
		for _, building in militaryBuildings do
			table.insert(buildingOptions, building)
		end
		for _, building in economyBuildings do
			table.insert(buildingOptions, building)
		end
	end

	-- If all priorities met, add any random building based on bias
	if #buildingOptions == 0 then
		if state.buildingBias == "economy" then
			buildingOptions = { "Farm", "Lumbermill", "Barracks" }
		else
			buildingOptions = { "Barracks", "Archery Range", "Farm" }
		end
	end

	local randomBuilding = buildingOptions[math.random(1, #buildingOptions)]

	-- Use improved position finding with collision avoidance
	local buildPosition = AIManager.getValidBuildingPosition(ownerId, randomBuilding)
	if not buildPosition then
		-- Fallback to random position (expanded for larger estates)
		local offsetX = math.random(-200, 200)
		local offsetZ = math.random(-200, 200)
		buildPosition = state.spawnPoint * CFrame.new(offsetX, 0, offsetZ)
	end

	local building = AIManager.placeBuilding(ownerId, randomBuilding, buildPosition)
	if building then
		table.insert(state.buildings, building)
		state.buildingCount += 1
		AIDebug:info(`{state.ownerName} built {randomBuilding} ({state.buildingCount} buildings)`)
	end
end

-- Attempt to train units
function AIManager.attemptTraining(ownerId: number)
	local state = aiStates[ownerId]
	if not state then
		return
	end

	local config = DIFFICULTY_CONFIGS[state.difficulty]

	-- Count current peasants
	local peasantCount = 0
	for _, unit in state.units do
		if unit and unit.Parent then
			local unitType = unit:GetAttribute("UnitType")
			if unitType == "Peasant" then
				peasantCount += 1
			end
		end
	end

	-- Determine unit type based on aggressiveness, peasant count, and AI personality
	local unitOptions: { string }

	-- Always maintain at least 3 peasants for resource gathering
	if peasantCount < 3 then
		unitOptions = { "Peasant" }
	elseif math.random() < (config.aggressiveness + state.aggressionBonus) then
		-- Aggressive units (combat focused) - favor preferred unit
		unitOptions = { state.preferredUnitType, "Swordsman", "Knight", "Macemen", "Archer" }
	else
		-- Mix of combat and economy units
		unitOptions = { "Peasant", "Archer", "Swordsman", state.preferredUnitType }
	end

	local randomUnit = unitOptions[math.random(1, #unitOptions)]

	-- Spawn near Keep
	local spawnOffset = Vector3.new(math.random(-15, 15), 0, math.random(-15, 15))
	local spawnPos = state.spawnPoint.Position + spawnOffset

	local unit = UnitManager.createUnit(randomUnit, ownerId, spawnPos, state.faction)
	if unit then
		table.insert(state.units, unit)
		AIDebug:info(`{state.ownerName} trained {randomUnit}`)
	end
end

-- Give AI resources (cheat to keep them playing)
function AIManager.giveResources(ownerId: number)
	local state = aiStates[ownerId]
	if not state then
		return
	end

	local config = DIFFICULTY_CONFIGS[state.difficulty]
	local resourceAmount = math.floor(AI_BASE_RESOURCE_AMOUNT * config.resourceMultiplier)

	state.resources.Wood = state.resources.Wood + resourceAmount
	state.resources.Stone = state.resources.Stone + resourceAmount
	state.resources.Food = state.resources.Food + resourceAmount
	state.resources.Gold = state.resources.Gold + math.floor(resourceAmount / 2)
end

-- Place a building for AI using BuildingManager (ensures proper collision detection)
function AIManager.placeBuilding(ownerId: number, buildingName: string, cframe: CFrame): Instance?
	local state = aiStates[ownerId]
	if not state then
		return nil
	end

	-- Get building info to get size
	local buildingInfo = GameData.Buildings[buildingName]
	if not buildingInfo then
		AIDebug:warn(`Unknown building: {buildingName}`)
		return nil
	end

	-- Perform ground raycast to get proper Y position (same as PlacementController)
	local position = cframe.Position
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	local ignoreList = {}
	local buildingsFolder = Workspace:FindFirstChild("Buildings")
	local unitsFolder = Workspace:FindFirstChild("Units")
	if buildingsFolder then
		table.insert(ignoreList, buildingsFolder)
	end
	if unitsFolder then
		table.insert(ignoreList, unitsFolder)
	end
	raycastParams.FilterDescendantsInstances = ignoreList

	-- Raycast from above to find ground
	local rayOrigin = Vector3.new(position.X, 1000, position.Z)
	local rayDirection = Vector3.new(0, -2000, 0)
	local groundResult = Workspace:Raycast(rayOrigin, rayDirection, raycastParams)

	local groundY = position.Y -- Default to provided Y if raycast fails
	if groundResult then
		groundY = groundResult.Position.Y
	end

	-- Use the same formula as PlacementController (line 590)
	local buildingSize = buildingInfo.size or Vector3.new(10, 10, 10)
	local adjustedY = groundY + buildingSize.Y / 2

	-- Create adjusted CFrame with proper ground height
	local adjustedCFrame = CFrame.new(position.X, adjustedY, position.Z) * (cframe - cframe.Position)

	AIDebug:info(`AI placing {buildingName} - Ground Y: {groundY}, Size Y: {buildingSize.Y}, Final Y: {adjustedY}`)

	-- Use BuildingManager to create the building (handles all validation and collision)
	-- Pass ownerId (number) instead of Player object - BuildingManager now supports both
	local building = BuildingManager.createBuilding(
		ownerId, -- AI uses ownerId instead of Player
		buildingName,
		adjustedCFrame,
		nil, -- wallPieceType
		nil, -- manualRotation
		true -- skipCost = true for AI
	)

	if building then
		-- Add AI-specific attributes
		building:SetAttribute("Faction", state.faction)
		building:SetAttribute("IsAIBuilding", true)
		building:SetAttribute("Difficulty", state.difficulty)
		AIDebug:info(`Placed {buildingName} for {state.ownerName}`)
	else
		AIDebug:warn(`Failed to place {buildingName} for {state.ownerName} - collision or invalid position`)
	end

	return building
end

-- Launch an attack wave - command AI units to attack enemy players
function AIManager.launchAttackWave(ownerId: number)
	local state = aiStates[ownerId]
	if not state then
		return
	end

	local config = DIFFICULTY_CONFIGS[state.difficulty]

	-- Find all combat units (not peasants)
	local combatUnits = {}
	for _, unit in state.units do
		if unit and unit.Parent then
			local unitType = unit:GetAttribute("UnitType")
			if unitType and unitType ~= "Peasant" then
				table.insert(combatUnits, unit)
			end
		end
	end

	-- Adaptive attack threshold based on AI strength
	local strength = AIManager.evaluateStrength(ownerId)
	local attackThreshold = config.attackWaveSize

	if strength == "Strong" then
		-- When strong, attack more frequently with smaller waves
		attackThreshold = math.max(2, config.attackWaveSize - 1)
	elseif strength == "Weak" then
		-- When weak, wait for larger force before attacking
		attackThreshold = config.attackWaveSize + 2
	end

	-- Check if we have enough units to attack (adaptive)
	if #combatUnits < attackThreshold then
		AIDebug:info(`{state.ownerName} ({strength}) has only {#combatUnits} combat units, needs {attackThreshold} before attacking`)
		return
	end

	-- Find nearest enemy player or keep
	local targetPosition = AIManager.findNearestEnemyTarget(ownerId, state.spawnPoint.Position)
	if not targetPosition then
		AIDebug:warn(`{state.ownerName} couldn't find attack target`)
		return
	end

	-- Command units to move to target
	for _, unit in combatUnits do
		-- Set unit destination attribute for movement system
		unit:SetAttribute("AIDestination", targetPosition)
		unit:SetAttribute("AICommand", "Attack")
	end

	AIDebug:info(`{state.ownerName} launched attack wave with {#combatUnits} units to {targetPosition}`)
end

-- Command peasants to gather resources
function AIManager.managePeasants(ownerId: number)
	local state = aiStates[ownerId]
	if not state then
		return
	end

	-- Find all peasants
	local peasants = {}
	for _, unit in state.units do
		if unit and unit.Parent then
			local unitType = unit:GetAttribute("UnitType")
			if unitType == "Peasant" then
				table.insert(peasants, unit)
			end
		end
	end

	if #peasants == 0 then
		return
	end

	-- Find resource nodes (trees, stone deposits, etc.)
	local ResourcesFolder = workspace:FindFirstChild("Resources")
	if not ResourcesFolder then
		return
	end

	-- Assign peasants to nearby resource nodes
	for _, peasant in ipairs(peasants) do
		-- Check if peasant already has a task
		local currentTask = peasant:GetAttribute("AICommand")
		if currentTask == "Gather" then
			continue -- Already gathering
		end

		-- Find nearest resource node
		local peasantPos = peasant:GetPivot().Position
		local nearestResource = nil
		local nearestDistance = math.huge

		for _, resource in ResourcesFolder:GetChildren() do
			local resourcePos = resource:GetPivot().Position
			local distance = (resourcePos - peasantPos).Magnitude

			if distance < nearestDistance then
				nearestDistance = distance
				nearestResource = resource
			end
		end

		-- Send peasant to gather if resource found
		if nearestResource then
			peasant:SetAttribute("AIDestination", nearestResource:GetPivot().Position)
			peasant:SetAttribute("AICommand", "Gather")
			peasant:SetAttribute("TargetResource", nearestResource)
		end
	end
end

-- Evaluate AI's current strength (used for adaptive behavior)
function AIManager.evaluateStrength(ownerId: number): string
	local state = aiStates[ownerId]
	if not state then
		return "Weak"
	end

	-- Count combat units
	local combatUnitCount = 0
	for _, unit in state.units do
		if unit and unit.Parent then
			local unitType = unit:GetAttribute("UnitType")
			if unitType and unitType ~= "Peasant" then
				combatUnitCount += 1
			end
		end
	end

	-- Count buildings
	local militaryBuildings = 0
	for _, building in state.buildings do
		if building and building.Parent then
			local buildingType = building:GetAttribute("BuildingType")
			if buildingType == "Barracks" or buildingType == "Archery Range" then
				militaryBuildings += 1
			end
		end
	end

	-- Evaluate strength based on units and buildings
	if combatUnitCount >= 10 and militaryBuildings >= 2 then
		return "Strong"
	elseif combatUnitCount >= 5 and militaryBuildings >= 1 then
		return "Medium"
	else
		return "Weak"
	end
end

-- Send a scout to explore enemy territory
function AIManager.sendScout(ownerId: number)
	local state = aiStates[ownerId]
	if not state then
		return
	end

	-- Find a fast unit to scout (Archer or any available combat unit)
	local scoutUnit = nil
	for _, unit in state.units do
		if unit and unit.Parent then
			local unitType = unit:GetAttribute("UnitType")
			local currentCommand = unit:GetAttribute("AICommand")

			-- Use Archer as scout (they're fast), or any non-peasant that's idle
			if unitType == "Archer" and currentCommand ~= "Scout" then
				scoutUnit = unit
				break
			elseif unitType and unitType ~= "Peasant" and not currentCommand then
				scoutUnit = unit
			end
		end
	end

	if not scoutUnit then
		return -- No available scouts
	end

	-- Find a random enemy Keep to scout
	local BuildingsFolder = workspace:FindFirstChild("Buildings")
	if not BuildingsFolder then
		return
	end

	local enemyKeeps = {}
	for _, building in BuildingsFolder:GetChildren() do
		local buildingOwner = building:GetAttribute("Owner")
		local buildingType = building:GetAttribute("BuildingType")

		if buildingType == "Keep" and buildingOwner and buildingOwner ~= ownerId then
			table.insert(enemyKeeps, building)
		end
	end

	if #enemyKeeps > 0 then
		local targetKeep = enemyKeeps[math.random(1, #enemyKeeps)]
		local targetPos = targetKeep:GetPivot().Position

		-- Send scout to enemy base
		scoutUnit:SetAttribute("AIDestination", targetPos)
		scoutUnit:SetAttribute("AICommand", "Scout")

		AIDebug:info(`{state.ownerName} sent scout to enemy territory`)
	end
end

-- Check if AI is under attack and respond defensively
function AIManager.checkDefensiveStatus(ownerId: number)
	local state = aiStates[ownerId]
	if not state then
		return
	end

	local config = DIFFICULTY_CONFIGS[state.difficulty]

	-- Check if any buildings are under threat (enemy units nearby)
	local BuildingsFolder = workspace:FindFirstChild("Buildings")
	local UnitsFolder = workspace:FindFirstChild("Units")
	if not BuildingsFolder or not UnitsFolder then
		return
	end

	-- Find AI's Keep position
	local keepPosition = nil
	for _, building in state.buildings do
		if building and building.Parent then
			local buildingType = building:GetAttribute("BuildingType")
			if buildingType == "Keep" then
				keepPosition = building:GetPivot().Position
				break
			end
		end
	end

	if not keepPosition then
		return
	end

	-- Check for enemy units near Keep (within 100 studs)
	local threatsNearby = 0
	for _, unit in UnitsFolder:GetChildren() do
		local unitOwner = unit:GetAttribute("Owner")
		if unitOwner and unitOwner ~= ownerId then
			local unitPos = unit:GetPivot().Position
			local distance = (unitPos - keepPosition).Magnitude
			if distance < 100 then
				threatsNearby += 1
			end
		end
	end

	-- If under attack and exceeds retreat threshold, recall combat units to defend
	if threatsNearby >= config.retreatThreshold then
		AIDebug:info(`{state.ownerName} is under attack! {threatsNearby} enemy units nearby (threshold: {config.retreatThreshold}), recalling defenders`)

		-- Find all combat units
		for _, unit in state.units do
			if unit and unit.Parent then
				local unitType = unit:GetAttribute("UnitType")
				if unitType and unitType ~= "Peasant" then
					-- Send units back to defend Keep
					unit:SetAttribute("AIDestination", keepPosition)
					unit:SetAttribute("AICommand", "Defend")
				end
			end
		end
	end
end

-- Find best enemy target (prioritizes weakest enemies or nearest)
function AIManager.findNearestEnemyTarget(ownerId: number, aiPosition: Vector3): Vector3?
	-- Look for enemy Keeps in workspace
	local BuildingsFolder = workspace:FindFirstChild("Buildings")
	local UnitsFolder = workspace:FindFirstChild("Units")
	if not BuildingsFolder then
		return nil
	end

	-- Collect all enemy keeps with their strength assessment
	local enemyTargets = {}

	for _, building in BuildingsFolder:GetChildren() do
		local buildingOwner = building:GetAttribute("Owner")
		local buildingType = building:GetAttribute("BuildingType")

		-- Find enemy Keeps (not AI's own)
		if buildingType == "Keep" and buildingOwner and buildingOwner ~= ownerId then
			local buildingPos = building:GetPivot().Position
			local distance = (buildingPos - aiPosition).Magnitude

			-- Count enemy's nearby units (within 150 studs of their Keep)
			local enemyUnitCount = 0
			if UnitsFolder then
				for _, unit in UnitsFolder:GetChildren() do
					local unitOwner = unit:GetAttribute("Owner")
					if unitOwner == buildingOwner then
						local unitPos = unit:GetPivot().Position
						if (unitPos - buildingPos).Magnitude < 150 then
							enemyUnitCount += 1
						end
					end
				end
			end

			table.insert(enemyTargets, {
				position = buildingPos,
				distance = distance,
				unitCount = enemyUnitCount,
				score = (1000 / distance) - (enemyUnitCount * 10), -- Higher score = better target
			})
		end
	end

	if #enemyTargets == 0 then
		return nil
	end

	-- Sort by score (attack weakest/nearest first)
	table.sort(enemyTargets, function(a, b)
		return a.score > b.score
	end)

	-- Return best target position
	return enemyTargets[1].position
end

-- Improved building placement with collision avoidance
function AIManager.getValidBuildingPosition(ownerId: number, buildingName: string): CFrame?
	local state = aiStates[ownerId]
	if not state then
		return nil
	end

	local buildingInfo = GameData.Buildings[buildingName]
	if not buildingInfo then
		return nil
	end

	-- Try multiple positions
	for _ = 1, 10 do
		-- Generate random position near spawn (expanded range for larger estates)
		local angle = math.random() * math.pi * 2
		local distance = math.random(30, 200) -- Expanded from 25-70 to 30-200 for larger estates
		local offsetX = math.cos(angle) * distance
		local offsetZ = math.sin(angle) * distance
		local testPosition = state.spawnPoint * CFrame.new(offsetX, 0, offsetZ)

		-- Check if position is clear (simple check - just distance from other buildings)
		local isClear = true
		for _, existingBuilding in state.buildings do
			if existingBuilding and existingBuilding.Parent then
				local dist = (existingBuilding:GetPivot().Position - testPosition.Position).Magnitude
				if dist < 30 then -- Minimum 30 studs between buildings
					isClear = false
					break
				end
			end
		end

		if isClear then
			return testPosition
		end
	end

	-- If all attempts failed, just use a random position (fallback - expanded for larger estates)
	local offsetX = math.random(-200, 200)
	local offsetZ = math.random(-200, 200)
	return state.spawnPoint * CFrame.new(offsetX, 0, offsetZ)
end

-- Remove AI when they're defeated
function AIManager.removeAI(ownerId: number)
	local state = aiStates[ownerId]
	if not state then
		return
	end

	AIDebug:info(`Removing AI: {state.ownerName}`)

	-- Clean up buildings
	for _, building in state.buildings do
		if building and building.Parent then
			building:Destroy()
		end
	end

	-- Clean up units
	for _, unit in state.units do
		if unit and unit.Parent then
			unit:Destroy()
		end
	end

	aiStates[ownerId] = nil
end

return AIManager
