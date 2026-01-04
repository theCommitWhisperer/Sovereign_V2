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

-- Get AI state by ownerId (used by other managers like PopulationManager)
function AIManager.getState(ownerId)
	return aiStates[ownerId]
end

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
		hasKeep = true, -- Keep spawned at game start by GameManager
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
		buildings = {}, -- Keep will be added by GameManager
		units = {}, -- Starting peasants will be added by GameManager
		buildingCount = 0,
		unitCount = 0,
		-- Personality traits
		preferredUnitType = preferredUnit,
		buildingBias = buildingBias,
		aggressionBonus = aggressionBonus,
	}

	-- Register with PopulationManager for automatic population growth
	local PopulationManager = require(script.Parent.PopulationManager)
	PopulationManager.createAI(ownerId, ownerName)

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

	-- Keep and starting peasants already spawned by GameManager (same as players)
	-- No need to build Keep or train initial peasants here

	-- Build economy buildings
	AIManager.buildStorehouse(ownerId)
	task.wait(2)

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

-- Train initial peasants after Keep is built (similar to player starting units)
function AIManager.trainInitialPeasants(ownerId, count)
	local state = aiStates[ownerId]
	if not state or not state.hasKeep then
		AIDebug:warn("Cannot train initial peasants - no Keep built yet")
		return
	end

	count = count or 5 -- Default to 5 peasants
	local UnitManager = require(script.Parent.UnitManager)

	AIDebug:info(state.ownerName .. " training " .. count .. " initial peasants")

	for i = 1, count do
		-- Spawn peasants 30-50 studs away from Keep in random directions
		local angle = math.random() * math.pi * 2
		local distance = math.random(30, 50)
		local spawnOffset = Vector3.new(
			math.cos(angle) * distance,
			0,
			math.sin(angle) * distance
		)
		local basePos = state.spawnPoint.Position + spawnOffset
		local spawnPos = Vector3.new(basePos.X, 10, basePos.Z)

		-- Create peasant unit
		AIDebug:info("[PEASANT SPAWN] AIManager.trainInitialPeasants - " .. state.ownerName .. " spawning peasant #" .. i .. " at " .. tostring(spawnPos))
		local peasant = UnitManager.createUnit("Peasant", ownerId, spawnPos, state.faction)
		if peasant then
			table.insert(state.units, peasant)
			state.unitCount = state.unitCount + 1
			AIDebug:info("[PEASANT SPAWN] AIManager - Successfully spawned peasant for " .. state.ownerName)
		end

		-- Stagger spawning to avoid pathfinding congestion
		if i < count then
			task.wait(0.5)
		end
	end

	AIDebug:info(state.ownerName .. " finished training initial peasants")
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

	-- Count existing building types dynamically
	local buildingCounts = {}

	for _, building in state.buildings do
		if building and building.Parent then
			local buildingType = building:GetAttribute("BuildingType")
			if buildingType then
				buildingCounts[buildingType] = (buildingCounts[buildingType] or 0) + 1
			end
		end
	end

	-- Categorize buildings from GameData dynamically
	local economyBuildings = {}
	local militaryBuildings = {}
	local storageBuildings = {}

	for buildingName, buildingData in pairs(GameData.Buildings) do
		-- Skip the Keep (main building)
		if buildingName == "Keep" then
			continue
		end

		-- Skip buildings without model assets (can't be placed by AI)
		if not buildingData.model_asset_name then
			continue
		end

		-- Categorize based on building properties
		if buildingData.can_train_units then
			-- Military building (can train units)
			table.insert(militaryBuildings, buildingName)
		elseif buildingData.produces_resource then
			-- Economy building (produces resources)
			table.insert(economyBuildings, buildingName)
		elseif buildingData.storage_capacity then
			-- Storage building
			table.insert(storageBuildings, buildingName)
		end
	end

	-- Build priority list based on what's missing
	local buildingOptions = {}

	-- Always prioritize storage if we have none
	for _, buildingName in storageBuildings do
		if not buildingCounts[buildingName] or buildingCounts[buildingName] == 0 then
			table.insert(buildingOptions, buildingName)
		end
	end

	-- Add economy buildings we don't have yet
	for _, buildingName in economyBuildings do
		if not buildingCounts[buildingName] or buildingCounts[buildingName] == 0 then
			table.insert(buildingOptions, buildingName)
		end
	end

	-- Add military buildings (limited quantities)
	for _, buildingName in militaryBuildings do
		local maxCount = 2 -- Max 2 of each military building
		if not buildingCounts[buildingName] or buildingCounts[buildingName] < maxCount then
			table.insert(buildingOptions, buildingName)
		end
	end

	-- AI personality influences building priority
	if state.buildingBias == "military" then
		-- Military-focused: reverse order to prioritize military
		local temp = {}
		for i = #buildingOptions, 1, -1 do
			table.insert(temp, buildingOptions[i])
		end
		buildingOptions = temp
	end

	-- Fallback: if no options, pick from available buildings
	if #buildingOptions == 0 then
		for _, buildingName in economyBuildings do
			table.insert(buildingOptions, buildingName)
		end
		for _, buildingName in militaryBuildings do
			table.insert(buildingOptions, buildingName)
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

	-- Only spawn units if Keep has been built
	if not state.hasKeep then
		AIDebug:warn(`{state.ownerName} cannot train {randomUnit} - no Keep built yet`)
		return
	end

	-- Spawn away from Keep to avoid pathfinding issues (30-50 studs away in random direction)
	local angle = math.random() * math.pi * 2 -- Random angle in radians
	local distance = math.random(30, 50) -- 30-50 studs away
	local spawnOffset = Vector3.new(
		math.cos(angle) * distance,
		0,
		math.sin(angle) * distance
	)
	local basePos = state.spawnPoint.Position + spawnOffset
	-- Use Y=10 as starting point (typical ground height) - physics will adjust
	local spawnPos = Vector3.new(basePos.X, 10, basePos.Z)

	AIDebug:info(state.ownerName .. " spawning " .. randomUnit .. " at " .. tostring(spawnPos) .. " (distance: " .. distance .. " studs)")

	local unit = UnitManager.createUnit(randomUnit, ownerId, spawnPos, state.faction)
	if unit then
		table.insert(state.units, unit)
		AIDebug:info(state.ownerName .. " trained " .. randomUnit .. " successfully")

		-- TESTING: Immediately send ALL units to move (for debugging)
		task.wait(0.5) -- Small delay to ensure unit is fully created
		local spawnPos = state.spawnPoint.Position
		-- Fix Y coordinate to ground level for pathfinding
		local targetPos = Vector3.new(spawnPos.X + 100, 0, spawnPos.Z)
		unit:SetAttribute("TargetPosition", targetPos)
		unit:SetAttribute("IsMoving", true)
		local hasHumanoid = unit:FindFirstChildOfClass("Humanoid") ~= nil
		local hasPrimaryPart = unit.PrimaryPart ~= nil
		AIDebug:info(`[TEST] Sent {randomUnit} to move to {targetPos}`)
		AIDebug:info(`[TEST] Unit components - IsMoving: {unit:GetAttribute("IsMoving")}, Humanoid: {hasHumanoid}, PrimaryPart: {hasPrimaryPart}`)
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

	-- Get the building model template to measure its bounding box
	local Assets = ReplicatedStorage:FindFirstChild("Assets")
	local buildingAssets = Assets and Assets:FindFirstChild("Buildings")
	local assetName = buildingInfo.model_asset_name or buildingName

	if not buildingAssets then
		AIDebug:warn(`No building assets found`)
		return nil
	end

	local template = buildingAssets:FindFirstChild(assetName)
	if not template or not template:IsA("Model") then
		AIDebug:warn(`No template found for {assetName}`)
		return nil
	end

	-- Create a temporary clone to measure bounding box (don't parent it yet)
	local tempModel = template:Clone()
	tempModel.Parent = nil -- Keep unparented for measurement

	-- Get bounding box of the template
	local boundingCFrame, boundingSize = tempModel:GetBoundingBox()
	local tempPivot = tempModel:GetPivot()

	-- Calculate bottom offset (distance from pivot to bottom of model)
	local bottomOffset = (boundingCFrame.Position.Y - boundingSize.Y / 2) - tempPivot.Position.Y

	-- Calculate final Y position so bottom sits on ground
	local finalY = groundY - bottomOffset
	local finalCFrame = CFrame.new(position.X, finalY, position.Z) * (cframe - cframe.Position)

	-- Clean up temp model
	tempModel:Destroy()

	AIDebug:info(`AI placing {buildingName} - Ground Y: {groundY}, Pivot Y: {finalY}, Bottom Offset: {bottomOffset}`)

	-- Now create the building at the correct final position
	-- BuildingManager will check collisions at this position
	local building = BuildingManager.createBuilding(
		ownerId, -- AI uses ownerId instead of Player
		buildingName,
		finalCFrame,
		nil, -- wallPieceType
		nil, -- manualRotation
		true -- skipCost = true for AI
	)

	if not building then
		AIDebug:warn(`Failed to create {buildingName} for {state.ownerName} - likely collision`)
		return nil
	end

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
		-- Verify unit has required components
		local hasHumanoid = unit:FindFirstChildOfClass("Humanoid") ~= nil
		local hasPrimaryPart = unit.PrimaryPart ~= nil

		if not hasHumanoid or not hasPrimaryPart then
			AIDebug:warn(`Unit {unit.Name} missing components - Humanoid: {hasHumanoid}, PrimaryPart: {hasPrimaryPart}`)
		end

		-- Check if pathfinding recently failed (respect MovementSystem cooldown)
		local pathfindingFailed = unit:GetAttribute("PathfindingFailed")
		if pathfindingFailed and (tick() - pathfindingFailed) < 30 then
			AIDebug:warn(`{unit.Name} pathfinding failed recently, skipping attack command`)
			return -- Don't spam pathfinding
		end

		-- Set unit destination attribute for movement system
		unit:SetAttribute("TargetPosition", targetPosition)
		unit:SetAttribute("IsMoving", true)
		unit:SetAttribute("AICommand", "Attack")

		AIDebug:info(`Set {unit.Name} to move to {targetPosition} - IsMoving: {unit:GetAttribute("IsMoving")}`)
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
			-- Check if pathfinding recently failed (respect MovementSystem cooldown)
			local pathfindingFailed = peasant:GetAttribute("PathfindingFailed")
			if pathfindingFailed and (tick() - pathfindingFailed) < 30 then
				-- Don't spam pathfinding - skip this peasant
				return
			end

			local resourcePos = nearestResource:GetPivot().Position
			-- Fix Y coordinate to ground level for pathfinding
			local groundPos = Vector3.new(resourcePos.X, 0, resourcePos.Z)
			peasant:SetAttribute("TargetPosition", groundPos)
			peasant:SetAttribute("IsMoving", true)
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
		-- Check if pathfinding recently failed (respect MovementSystem cooldown)
		local pathfindingFailed = scoutUnit:GetAttribute("PathfindingFailed")
		if pathfindingFailed and (tick() - pathfindingFailed) < 30 then
			AIDebug:warn(`{state.ownerName} scout pathfinding failed recently, waiting for cooldown`)
			return -- Don't spam pathfinding
		end

		-- Fix Y coordinate to ground level for pathfinding
		local groundPos = Vector3.new(targetPos.X, 0, targetPos.Z)

		-- Send scout to enemy base
		scoutUnit:SetAttribute("TargetPosition", groundPos)
		scoutUnit:SetAttribute("IsMoving", true)
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
				local pivotPos = building:GetPivot().Position
				-- Fix Y coordinate to ground level for pathfinding
				keepPosition = Vector3.new(pivotPos.X, 0, pivotPos.Z)
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
					-- Check if pathfinding recently failed (respect MovementSystem cooldown)
					local pathfindingFailed = unit:GetAttribute("PathfindingFailed")
					if not (pathfindingFailed and (tick() - pathfindingFailed) < 30) then
						-- Send units back to defend Keep
						unit:SetAttribute("TargetPosition", keepPosition)
						unit:SetAttribute("IsMoving", true)
						unit:SetAttribute("AICommand", "Defend")
					end
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
			-- Fix Y coordinate to ground level for pathfinding
			local groundPos = Vector3.new(buildingPos.X, 0, buildingPos.Z)
			local distance = (groundPos - aiPosition).Magnitude

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
				position = groundPos, -- Use ground position for movement target
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

	-- Get all buildings in workspace for collision checking
	local BuildingsFolder = Workspace:FindFirstChild("Buildings")
	local UnitsFolder = Workspace:FindFirstChild("Units")
	local ResourceNodesFolder = Workspace:FindFirstChild("ResourceNodes")

	local allBuildings = {}
	if BuildingsFolder then
		for _, building in BuildingsFolder:GetChildren() do
			if building:IsA("Model") then
				table.insert(allBuildings, building)
			end
		end
	end

	local allUnits = {}
	if UnitsFolder then
		for _, unit in UnitsFolder:GetChildren() do
			if unit:IsA("Model") then
				table.insert(allUnits, unit)
			end
		end
	end

	local allResourceNodes = {}
	if ResourceNodesFolder then
		for _, node in ResourceNodesFolder:GetChildren() do
			if node:IsA("Model") then
				table.insert(allResourceNodes, node)
			end
		end
	end

	-- Try multiple positions
	for _ = 1, 15 do -- Increased attempts from 10 to 15
		-- Generate random position near spawn (expanded range for larger estates)
		local angle = math.random() * math.pi * 2
		local distance = math.random(30, 200) -- Expanded from 25-70 to 30-200 for larger estates
		local offsetX = math.cos(angle) * distance
		local offsetZ = math.sin(angle) * distance
		local testPosition = state.spawnPoint * CFrame.new(offsetX, 0, offsetZ)

		-- Check if position is clear (check against ALL buildings, units, and resources)
		local isClear = true
		local minimumBuildingDistance = 20 -- Distance from other buildings
		local minimumUnitDistance = 15 -- Distance from units (peasants, soldiers)
		local minimumResourceDistance = 12 -- Distance from resource nodes (trees, stone)

		-- Check against buildings
		for _, existingBuilding in allBuildings do
			if existingBuilding and existingBuilding.Parent then
				local dist = (existingBuilding:GetPivot().Position - testPosition.Position).Magnitude
				if dist < minimumBuildingDistance then
					isClear = false
					break
				end
			end
		end

		-- Check against units (don't place on peasants!)
		if isClear then
			for _, unit in allUnits do
				if unit and unit.Parent then
					local dist = (unit:GetPivot().Position - testPosition.Position).Magnitude
					if dist < minimumUnitDistance then
						isClear = false
						break
					end
				end
			end
		end

		-- Check against resource nodes (don't place on trees!)
		if isClear then
			for _, node in allResourceNodes do
				if node and node.Parent then
					local dist = (node:GetPivot().Position - testPosition.Position).Magnitude
					if dist < minimumResourceDistance then
						isClear = false
						break
					end
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
