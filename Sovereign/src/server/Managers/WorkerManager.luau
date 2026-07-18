--!strict
-- WorkerManager: Simplified approach - workers walk to BuildingEntrance (placed OUTSIDE building)
-- No teleporting, no edge calculations - just direct pathfinding to points

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local GameData = require(ReplicatedStorage.Shared.GameData)
local BuildingManager = require(script.Parent.BuildingManager)
local ProductionChainManager = require(script.Parent.ProductionChainManager)
local WeatherManager = require(script.Parent.WeatherManager)
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)
local WorkerPointSystem = require(script.Parent.Parent.Systems.WorkerPointSystem)
local IdlePeasantManager = require(script.Parent.IdlePeasantManager)
local ResourceNodeManager = require(script.Parent.ResourceNodeManager)

local WorkerManager = {}

-- Debug channels
local WorkerDebug = DebugManager.createChannel("Worker", false)
local HaulerDebug = DebugManager.createChannel("Hauler", false)

-- Active tasks
local WorkerTasks: { WorkerTask } = {}
local HaulerTasks: { HaulerTask } = {}
local BuildingProduction: { [Instance]: BuildingProductionState } = {}

-- Hauler assignment timer
local lastHaulerAssignmentTime = 0
local HAULER_ASSIGNMENT_INTERVAL = 5 -- Check every 5 seconds

-- Per-owner production modifier (set by HappinessManager / RevoltManager)
-- 1.0 = full production, 0.5 = half, 0 = halted
local productionModifiers: { [number]: number } = {}

-- Worker states - simple and clean
export type WorkerTask = {
	worker: Model,
	workplace: Instance,
	workplaceType: string,
	resourceType: string,
	jobType: string,
	state: "WalkingToEntrance" | "Working" | "GatheringResources" | "ReturningToDropoff",
	resourcesCarrying: number,
	targetNode: any?,
	ownerId: number,
	hasTransformed: boolean,
}

export type HaulerTask = {
	hauler: Model,
	state: "Idle" | "WalkingToPickup" | "WalkingToStorage" | "UnloadingInside",
	resourcesCarrying: number,
	resourceType: string?,
	sourceBuilding: Instance?,
	targetStorage: Instance?,
	ownerId: number,
	unloadStartTime: number?, -- Timestamp when unloading started
	storageEntrancePos: Vector3?, -- Position to respawn at after unloading
}

export type BuildingProductionState = {
	building: Instance,
	buildingType: string,
	lastProductionTime: number,
}

-- ============================================
-- PATHFINDING HELPERS
-- ============================================

-- Find an appropriate storage building for a resource type
local function findStorageBuildingForResource(resourceType: string, ownerId: number): Instance?
	local BuildingsFolder = Workspace:FindFirstChild("Buildings")
	if not BuildingsFolder then
		return nil
	end

	-- Determine which storage building type to look for based on resource
	local targetBuildingType: string?
	if resourceType == "Food" or resourceType == "Flour" or resourceType == "Bread" or resourceType == "Ale" then
		targetBuildingType = "Granary"
	elseif resourceType == "Wood" or resourceType == "Stone" or resourceType == "Iron_Bars"
		or resourceType == "Weapons" or resourceType == "Siege_Equipment" or resourceType == "Iron_Ore"
		or resourceType == "Leather" or resourceType == "Furniture" or resourceType == "Coal"
		or resourceType == "Manuscripts" then
		targetBuildingType = "Storehouse"
	else
		-- Unknown resource type, try Storehouse as default
		targetBuildingType = "Storehouse"
	end

	-- Find the first available storage building of the correct type owned by the player
	local bestStorage: Instance? = nil
	local bestSpaceAvailable = 0

	for _, building in ipairs(BuildingsFolder:GetChildren()) do
		if building:IsA("Model") then
			local buildingType = building:GetAttribute("BuildingType")
			local buildingOwnerId = building:GetAttribute("OwnerId")

			-- Check if it's the right type and owned by the same player
			if buildingType == targetBuildingType and buildingOwnerId == ownerId then
				-- Check if it can store this resource and has space
				local buildingInfo = GameData.Buildings[buildingType]
				if buildingInfo and buildingInfo.storage_capacity and buildingInfo.storage_capacity[resourceType] then
					local currentAmount = BuildingManager.getStorageAmount(building, resourceType)
					local maxCapacity = buildingInfo.storage_capacity[resourceType]
					local spaceAvailable = maxCapacity - currentAmount

					-- Choose the storage with most available space
					if spaceAvailable > bestSpaceAvailable then
						bestStorage = building
						bestSpaceAvailable = spaceAvailable
					end
				end
			end
		end
	end

	return bestStorage
end

-- Pathfind to a specific position (for resource nodes)
local function pathfindToPosition(unit: Model, targetPos: Vector3, arrivalThreshold: number): boolean
	if not unit.PrimaryPart then
		return true
	end

	local currentPos = unit.PrimaryPart.Position
	local distance2D = (Vector3.new(targetPos.X, 0, targetPos.Z) - Vector3.new(currentPos.X, 0, currentPos.Z)).Magnitude

	-- Check if arrived
	if distance2D <= arrivalThreshold then
		unit:SetAttribute("IsMoving", false)
		unit:SetAttribute("TargetPosition", nil)
		return true
	end

	-- Set pathfinding target
	local currentTarget = unit:GetAttribute("TargetPosition")
	if not currentTarget or (currentTarget - targetPos).Magnitude > 1 then
		unit:SetAttribute("TargetPosition", targetPos)
		unit:SetAttribute("IsMoving", true)
	end

	return false
end

-- Pathfind to a worker point (BuildingEntrance, ProductionStation, ResourceDropoff)
local function pathfindToPoint(unit: Model, building: Instance, pointType: string, arrivalThreshold: number): boolean
	if not unit.PrimaryPart then
		return true
	end

	-- Get the point position from WorkerPointSystem
	local targetPos = WorkerPointSystem.getPointPosition(building, pointType)
	if not targetPos then
		WorkerDebug:warn(`Point {pointType} not found in {building.Name}`)
		return false
	end

	-- Use standard pathfinding
	return pathfindToPosition(unit, targetPos, arrivalThreshold)
end

-- ============================================
-- WORKER TRANSFORMATION
-- ============================================

local function transformWorker(peasant: Model, jobType: string): Model
	local unitData = GameData.Units[jobType]
	if not unitData then
		return peasant
	end

	peasant:SetAttribute("UnitType", jobType)

	local modelName = unitData.model_name or jobType
	local newModel = ReplicatedStorage.Assets.Units:FindFirstChild(modelName)

	if newModel then
		local position = peasant:GetPivot()
		local attributes = {}
		for key, value in pairs(peasant:GetAttributes()) do
			attributes[key] = value
		end

		local clone = newModel:Clone()
		clone.Name = peasant.Name
		clone:PivotTo(position)

		for key, value in pairs(attributes) do
			clone:SetAttribute(key, value)
		end

		clone.Parent = peasant.Parent
		peasant:Destroy()

		WorkerDebug:info(`Transformed peasant to {jobType}`)
		return clone
	end

	return peasant
end

-- ============================================
-- WORKER ASSIGNMENT
-- ============================================

function WorkerManager.assignWorkerToBuilding(peasant: Model, building: Instance, ownerId: number)
	if not peasant or not building then
		return
	end

	local buildingType = building:GetAttribute("BuildingType")
	local buildingInfo = GameData.Buildings[buildingType]

	if not buildingInfo or not buildingInfo.requires_worker then
		return
	end

	local jobType = buildingInfo.worker_type or "Worker"

	WorkerDebug:info(`Assigning peasant to {buildingType} as {jobType}`)

	local task: WorkerTask = {
		worker = peasant,
		workplace = building,
		workplaceType = buildingType,
		resourceType = buildingInfo.produces_resource,
		jobType = jobType,
		state = "WalkingToEntrance",
		resourcesCarrying = 0,
		targetNode = nil,
		ownerId = ownerId,
		hasTransformed = false,
	}

	table.insert(WorkerTasks, task)
	peasant:SetAttribute("IsWorking", true)
	peasant:SetAttribute("AssignedTo", buildingType)
end

-- ============================================
-- WORKER UPDATE LOOP
-- ============================================

local function updateWorkerTasks(dt: number)
	for i = #WorkerTasks, 1, -1 do
		local task = WorkerTasks[i]

		-- Validate
		if not task.worker or not task.worker.Parent or not task.workplace or not task.workplace.Parent then
			table.remove(WorkerTasks, i)
			if task.worker then
				task.worker:SetAttribute("IsWorking", false)
			end
			continue
		end

		local buildingInfo = GameData.Buildings[task.workplaceType]
		if not buildingInfo then
			continue
		end

		local unitInfo = GameData.Units[task.jobType]
		local carryCapacity = unitInfo and unitInfo.carry_capacity or 10

		-- ============================================
		-- STATE: WALKING TO ENTRANCE
		-- ============================================
		if task.state == "WalkingToEntrance" then
			-- Walk directly to BuildingEntrance point (should be OUTSIDE building, in walkable space)
			local arrivedAtEntrance = pathfindToPoint(task.worker, task.workplace, "BuildingEntrance", 3)

			if arrivedAtEntrance then
				WorkerDebug:info(`Worker arrived at BuildingEntrance`)

				-- Transform peasant to worker type
				if not task.hasTransformed then
					local oldWorker = task.worker
					task.worker = transformWorker(task.worker, task.jobType)
					task.hasTransformed = true

					-- Validate worker model still exists after transformation
					if not task.worker or not task.worker.Parent then
						WorkerDebug:warn(`Worker model invalid after transformation for {task.jobType}`)
						table.remove(WorkerTasks, i)
						continue
					end

					WorkerDebug:info(`Worker transformation successful: {task.jobType}`)
				end

				-- Double-check worker is still valid
				if not task.worker or not task.worker.Parent then
					WorkerDebug:warn("Worker disappeared during entrance processing")
					table.remove(WorkerTasks, i)
					continue
				end

				-- Clear movement first
				task.worker:SetAttribute("TargetPosition", nil)
				task.worker:SetAttribute("IsMoving", false)

				-- Check if building has TeleportIntoBuilding point (use hasPoint to avoid fallback)
				local hasTeleportPoint = WorkerPointSystem.hasPoint(task.workplace, "TeleportIntoBuilding")

				if hasTeleportPoint then
					WorkerDebug:info(`Building has TeleportIntoBuilding - hiding worker`)

					local teleportPoint = WorkerPointSystem.getPointPosition(task.workplace, "TeleportIntoBuilding")

					-- Worker enters building and becomes invisible
					if teleportPoint and task.worker.PrimaryPart then
						task.worker:PivotTo(CFrame.new(teleportPoint))
					else
						WorkerDebug:warn("Worker has no PrimaryPart or no teleport position, cannot teleport")
					end

					-- Hide worker completely (inside building)
					for _, part in ipairs(task.worker:GetDescendants()) do
						if part:IsA("BasePart") then
							part.Transparency = 1
							part.CanCollide = false
						elseif part:IsA("Decal") or part:IsA("Texture") then
							part.Transparency = 1
						end
					end

					WorkerDebug:info(`Worker entered building and is now hidden`)
				else
					-- No teleport point - worker stays visible at entrance
					WorkerDebug:info(`No TeleportIntoBuilding point - worker staying visible at entrance`)
				end

				-- Move to working state
				task.state = "Working"

				-- Initialize production state for auto-production buildings
				local isAutoProduction = buildingInfo.production_time and buildingInfo.production_time > 0
				if isAutoProduction and not BuildingProduction[task.workplace] then
					BuildingProduction[task.workplace] = {
						building = task.workplace,
						buildingType = task.workplaceType,
						lastProductionTime = tick(),
					}
				end
			end

		-- ============================================
		-- STATE: WORKING (at building)
		-- ============================================
		elseif task.state == "Working" then
			-- Debug: Log once when entering Working state
			if not task.worker:GetAttribute("_LoggedWorkingState") then
				WorkerDebug:info(`Worker entered Working state at {task.workplace.Name}`)
				task.worker:SetAttribute("_LoggedWorkingState", true)
			end

			-- Check building type to determine work behavior
			local isAutoProduction = buildingInfo.production_time and buildingInfo.production_time > 0

			if isAutoProduction then
				-- AUTO-PRODUCTION (Farm, Smelter, Bakery)
				-- Worker stays at ProductionStation (or BuildingEntrance if no ProductionStation) and produces over time

				-- Pathfind to ProductionStation if not already there
				local arrivedAtStation = pathfindToPoint(task.worker, task.workplace, "ProductionStation", 3)
				if not arrivedAtStation then
					-- Still walking to station, wait
					if not task.worker:GetAttribute("_LoggedWalkingToStation") then
						WorkerDebug:info(`Worker walking to ProductionStation (will only log once)`)
						task.worker:SetAttribute("_LoggedWalkingToStation", true)
					end
					continue
				end

				-- Clear the debug flag when arrived
				if task.worker:GetAttribute("_LoggedWalkingToStation") then
					WorkerDebug:info(`Worker arrived at ProductionStation, starting production`)
					task.worker:SetAttribute("_LoggedWalkingToStation", nil)
				end

				local productionState = BuildingProduction[task.workplace]
				if not productionState then
					productionState = {
						building = task.workplace,
						buildingType = task.workplaceType,
						lastProductionTime = tick(),
					}
					BuildingProduction[task.workplace] = productionState
				end

				-- Check if enough time has passed
				local timeSinceLastProduction = tick() - productionState.lastProductionTime

				if timeSinceLastProduction >= buildingInfo.production_time then
					-- Check if worker can carry more
					if task.resourcesCarrying < carryCapacity then
						-- Apply per-owner production modifier (set by HappinessManager / RevoltManager)
						local modifier = productionModifiers[task.ownerId] or 1.0
						local produceAmount = math.floor((buildingInfo.production_output or 1) * modifier)

						productionState.lastProductionTime = tick()

						-- Skip this tick when production is fully halted (modifier = 0)
						if produceAmount <= 0 then
							continue
						end

						task.resourcesCarrying = task.resourcesCarrying + produceAmount
						task.worker:SetAttribute("ResourcesCarrying", task.resourcesCarrying)

						WorkerDebug:info(`Worker produced {produceAmount} {task.resourceType} (modifier: {modifier})`, {
							carrying = task.resourcesCarrying,
							capacity = carryCapacity,
						})

						-- If full, go to dropoff
						if task.resourcesCarrying >= carryCapacity then
							task.state = "ReturningToDropoff"
						end
					else
						-- Full, go to dropoff
						task.state = "ReturningToDropoff"
					end
				end

			else
				-- RESOURCE GATHERING (Lumberjack, Miner, Quarry)
				-- Worker goes out to find resource nodes in the world

				-- Find nearest resource node
				local nearestNode = nil
				local shortestDistance = math.huge

				if workspace:FindFirstChild("ResourceNodes") then
					for _, node in ipairs(workspace.ResourceNodes:GetChildren()) do
						if node:GetAttribute("ResourceType") == task.resourceType and node.PrimaryPart then
							local nodePos = node.PrimaryPart.Position
							local distance = (nodePos - task.worker.PrimaryPart.Position).Magnitude

							if distance < shortestDistance then
								shortestDistance = distance
								nearestNode = node
							end
						end
					end
				end

				if nearestNode then
					task.targetNode = nearestNode
					task.state = "GatheringResources"
					WorkerDebug:info(`Worker going to gather {task.resourceType} from resource node`)
				else
					WorkerDebug:warn(`No {task.resourceType} nodes found in workspace`)
				end
			end

		-- ============================================
		-- STATE: GATHERING RESOURCES (from world)
		-- ============================================
		elseif task.state == "GatheringResources" then
			if task.targetNode and task.targetNode.Parent and task.targetNode.PrimaryPart then
				local nodePos = task.targetNode.PrimaryPart.Position
				local arrivedAtNode = pathfindToPosition(task.worker, nodePos, 5)

				if arrivedAtNode then
					-- Gather from node, depleting it (nodes shrink/fade and are
					-- destroyed by ResourceNodeManager when exhausted)
					local wantAmount = math.min(carryCapacity - task.resourcesCarrying, 1)
					local gatherAmount = ResourceNodeManager.gatherFromInstance(task.targetNode, wantAmount)

					if gatherAmount <= 0 then
						-- Node just ran dry (or isn't tracked); find another one
						task.targetNode = nil
						task.state = "Working"
						continue
					end

					task.resourcesCarrying = task.resourcesCarrying + gatherAmount
					task.worker:SetAttribute("ResourcesCarrying", task.resourcesCarrying)

					WorkerDebug:info(`Gathered {gatherAmount} {task.resourceType}`, {
						carrying = task.resourcesCarrying,
						capacity = carryCapacity,
					})

					-- If full, return to building
					if task.resourcesCarrying >= carryCapacity then
						task.state = "ReturningToDropoff"
						task.targetNode = nil
					else
						-- Keep gathering (find another node next frame)
						task.targetNode = nil
						task.state = "Working"
					end
				end
			else
				-- Node disappeared
				task.targetNode = nil
				task.state = "Working"
			end

		-- ============================================
		-- STATE: RETURNING TO DROPOFF
		-- ============================================
		elseif task.state == "ReturningToDropoff" then
			-- Try ResourceDropoff first, fallback to BuildingEntrance if it doesn't exist
			local dropoffPointType = "ResourceDropoff"
			if not WorkerPointSystem.hasPoint(task.workplace, "ResourceDropoff") then
				dropoffPointType = "BuildingEntrance"
				WorkerDebug:info(`No ResourceDropoff point, using BuildingEntrance for deposit`)
			end

			local arrivedAtDropoff = pathfindToPoint(task.worker, task.workplace, dropoffPointType, 3)

			if arrivedAtDropoff then
				-- Deposit resources to building storage
				local deposited = BuildingManager.addToStorage(
					task.workplace,
					task.resourceType,
					task.resourcesCarrying
				)

				WorkerDebug:info(`Worker deposited {deposited} {task.resourceType} at {dropoffPointType} (attempted: {task.resourcesCarrying})`)

				task.resourcesCarrying = 0
				task.worker:SetAttribute("ResourcesCarrying", 0)

				-- Go back to working (will pathfind back to ProductionStation or enter building)
				task.state = "Working"
			end
		end
	end
end

-- ============================================
-- HAULER SYSTEM
-- ============================================

function WorkerManager.createHaulerTask(hauler: Model, sourceBuilding: Instance, resourceType: string, ownerId: number)
	-- Remove from idle peasants if they were there
	IdlePeasantManager.removeIdlePeasant(hauler)

	local task: HaulerTask = {
		hauler = hauler,
		state = "WalkingToPickup",
		resourcesCarrying = 0,
		resourceType = resourceType,
		sourceBuilding = sourceBuilding,
		targetStorage = nil,
		ownerId = ownerId,
		unloadStartTime = nil,
		storageEntrancePos = nil,
	}

	table.insert(HaulerTasks, task)
	hauler:SetAttribute("IsHauling", true)
	HaulerDebug:info(`Created hauler task for {hauler.Name} (ownerId: {ownerId}, task.ownerId: {task.ownerId})`)
end

local function updateHaulerTasks(dt: number)
	for i = #HaulerTasks, 1, -1 do
		local task = HaulerTasks[i]

		if not task.hauler or not task.hauler.Parent then
			table.remove(HaulerTasks, i)
			continue
		end

		if task.state == "WalkingToPickup" then
			if task.sourceBuilding and task.sourceBuilding.Parent and task.resourceType then
				-- Walk to ResourceDropoff point (where workers deposit resources)
				local pickupPos = WorkerPointSystem.getPickupPosition(task.sourceBuilding)
				if not pickupPos then
					HaulerDebug:warn(`No pickup point found for {task.sourceBuilding.Name}`)
					task.state = "Idle"
					continue
				end

				local arrivedAtPickup = pathfindToPosition(task.hauler, pickupPos, 3)

				if arrivedAtPickup then
					-- Pick up resources
					local pickupAmount = 10
					local actualPickup = BuildingManager.takeFromStorage(
						task.sourceBuilding,
						task.resourceType,
						pickupAmount
					)

					if actualPickup > 0 then
						task.resourcesCarrying = actualPickup
						task.hauler:SetAttribute("ResourcesCarrying", actualPickup)

						HaulerDebug:info(`Hauler picked up {actualPickup} {task.resourceType}`)

						-- Find appropriate storage building
						local storageBuilding = findStorageBuildingForResource(task.resourceType, task.ownerId)
						if storageBuilding then
							task.targetStorage = storageBuilding
							task.state = "WalkingToStorage"
							HaulerDebug:info(`Hauler going to {storageBuilding.Name} to deposit {task.resourceType}`)
						else
							HaulerDebug:warn(`No storage building found for {task.resourceType}`)
							-- Return resources to source building
							BuildingManager.addToStorage(
								task.sourceBuilding,
								task.resourceType,
								task.resourcesCarrying
							)
							task.resourcesCarrying = 0
							task.hauler:SetAttribute("ResourcesCarrying", 0)
							task.state = "Idle"
						end
					else
						HaulerDebug:warn(`No resources available to pick up`)
						task.state = "Idle"
					end
				end
			end

		elseif task.state == "WalkingToStorage" then
			if task.targetStorage and task.targetStorage.Parent and task.resourceType then
				-- Walk to storage BuildingEntrance
				local entrancePos = WorkerPointSystem.getPointPosition(task.targetStorage, "BuildingEntrance")
				if not entrancePos then
					HaulerDebug:warn(`No BuildingEntrance found on storage building`)
					task.state = "Idle"
					continue
				end

				local arrivedAtStorage = pathfindToPosition(task.hauler, entrancePos, 3)

				if arrivedAtStorage then
					HaulerDebug:info(`Hauler arrived at storage entrance, teleporting inside`)

					-- Store entrance position for respawning
					task.storageEntrancePos = entrancePos

					-- Make hauler invisible (teleport inside)
					if task.hauler.PrimaryPart then
						for _, part in ipairs(task.hauler:GetDescendants()) do
							if part:IsA("BasePart") then
								part.Transparency = 1
							end
						end
					end

					-- Start unloading timer
					task.unloadStartTime = tick()
					task.state = "UnloadingInside"
				end
			end

		elseif task.state == "UnloadingInside" then
			if task.targetStorage and task.resourceType and task.unloadStartTime then
				-- Wait 5 seconds before unloading completes
				local elapsedTime = tick() - task.unloadStartTime

				if elapsedTime >= 5 then
					-- Deposit resources
					local deposited = BuildingManager.addToStorage(
						task.targetStorage,
						task.resourceType,
						task.resourcesCarrying
					)

					HaulerDebug:info(`Hauler deposited {deposited} {task.resourceType} to storage`)

					task.resourcesCarrying = 0
					task.hauler:SetAttribute("ResourcesCarrying", 0)

					-- Respawn hauler at entrance
					if task.storageEntrancePos and task.hauler.PrimaryPart then
						task.hauler:PivotTo(CFrame.new(task.storageEntrancePos))

						-- Make hauler visible again
						for _, part in ipairs(task.hauler:GetDescendants()) do
							if part:IsA("BasePart") then
								part.Transparency = 0
							end
						end

						HaulerDebug:info(`Hauler respawned at storage entrance`)
					end

					-- Return hauler to idle behavior
					task.hauler:SetAttribute("IsHauling", false)

					-- Get ownerId from task or hauler attribute as fallback
					local ownerId = task.ownerId
					if not ownerId then
						ownerId = task.hauler:GetAttribute("OwnerId")
						HaulerDebug:warn(`Task ownerId was nil, using hauler OwnerId attribute: {ownerId}`)
					end

					if ownerId then
						HaulerDebug:info(`Adding hauler back to idle with ownerId: {ownerId}`)
						IdlePeasantManager.addIdlePeasant(task.hauler, ownerId)
					else
						HaulerDebug:warn(`Cannot add hauler to idle - no ownerId found`)
					end

					table.remove(HaulerTasks, i)
					HaulerDebug:info(`Hauler task completed, returning to idle behavior`)
				end
			end
		end
	end
end

-- Automatically assign haulers to buildings that need hauling
local function assignHaulersToBuildings()
	local BuildingsFolder = Workspace:FindFirstChild("Buildings")
	if not BuildingsFolder then
		HaulerDebug:warn("Buildings folder not found in Workspace!")
		return
	end


	-- Find all production buildings with resources to haul
	local buildingsNeedingHauling: { { building: Instance, resourceType: string, ownerId: number } } = {}

	for _, building in ipairs(BuildingsFolder:GetChildren()) do
		if building:IsA("Model") then
			local buildingType = building:GetAttribute("BuildingType")
			local buildingInfo = GameData.Buildings[buildingType]
			local ownerId = building:GetAttribute("OwnerId")

			if not ownerId then
				HaulerDebug:warn(`Building {building.Name} has no OwnerId attribute!`)
			end

			-- Check if building produces resources and has storage
			if buildingInfo and buildingInfo.produces_resource and buildingInfo.storage_capacity then
				local resourceType = buildingInfo.produces_resource
				local currentAmount = BuildingManager.getStorageAmount(building, resourceType)

				-- Debug: Log storage amounts for all production buildings
				HaulerDebug:info(`{building.Name} storage: {currentAmount or 0} {resourceType}`)

				-- If building has resources to haul (more than 5 units)
				if currentAmount >= 5 then
					HaulerDebug:info(`{building.Name} has {currentAmount} {resourceType} - checking for hauler`)
					-- Check if there's already a hauler assigned to this building
					local alreadyAssigned = false
					for _, haulerTask in ipairs(HaulerTasks) do
						if haulerTask.sourceBuilding == building and haulerTask.state ~= "Idle" then
							alreadyAssigned = true
							break
						end
					end

					if not alreadyAssigned then
						table.insert(buildingsNeedingHauling, {
							building = building,
							resourceType = resourceType,
							ownerId = ownerId,
						})
					end
				end
			end
		end
	end

	if #buildingsNeedingHauling == 0 then return end

	HaulerDebug:info(`Found {#buildingsNeedingHauling} buildings needing hauling, searching for idle peasants...`)

	for _, buildingNeedingHauling in ipairs(buildingsNeedingHauling) do
		local building = buildingNeedingHauling.building
		local resourceType = buildingNeedingHauling.resourceType
		local ownerId = buildingNeedingHauling.ownerId

		HaulerDebug:info(`Looking for idle peasant for {building.Name} (ownerId: {ownerId})`)

		-- Use IdlePeasantManager to find peasants by owner (avoids OwnerId attribute issues)
		local idlePeasants = IdlePeasantManager.getIdlePeasantsForOwner(ownerId)
		HaulerDebug:info(`IdlePeasantManager found {#idlePeasants} idle peasants for ownerId {ownerId}`)

		if #idlePeasants == 0 then
			HaulerDebug:warn(`No idle peasants tracked for ownerId {ownerId} for {building.Name}`)
		end

		for _, unit in ipairs(idlePeasants) do
			if not unit or not unit.Parent then continue end

			local isAssigned = false

			-- Check if assigned as worker
			for _, workerTask in ipairs(WorkerTasks) do
				if workerTask.worker == unit then
					isAssigned = true
					break
				end
			end

			-- Check if assigned as hauler
			if not isAssigned then
				for _, haulerTask in ipairs(HaulerTasks) do
					if haulerTask.hauler == unit then
						isAssigned = true
						break
					end
				end
			end

			-- If not already assigned to a task, use as hauler
			if not isAssigned then
				HaulerDebug:info(`Found idle peasant {unit.Name} for hauling`)
				WorkerManager.createHaulerTask(unit, building, resourceType, ownerId)
				HaulerDebug:info(`Assigned hauler to {building.Name} for {resourceType} (ownerId: {ownerId})`)
				break -- Move to next building needing hauling
			end
		end
	end
end

-- ============================================
-- MAIN UPDATE
-- ============================================

function WorkerManager.update(dt: number)
	updateWorkerTasks(dt)
	updateHaulerTasks(dt)
	IdlePeasantManager.update(dt)

	-- Periodically assign haulers to buildings
	local currentTime = tick()
	if currentTime - lastHaulerAssignmentTime >= HAULER_ASSIGNMENT_INTERVAL then
		assignHaulersToBuildings()
		lastHaulerAssignmentTime = currentTime
	end
end

-- Called by GameManager when a game actually starts
function WorkerManager.startLoop()
	local RunService = game:GetService("RunService")
	RunService.Heartbeat:Connect(function(dt)
		WorkerManager.update(dt)
	end)
	WorkerDebug:info("WorkerManager update loop started")
end

-- Called by HappinessManager and RevoltManager to scale worker output.
-- modifier: 1.0 = full production, 0.5 = half, 0 = fully halted.
function WorkerManager.setProductionModifier(player: Player, modifier: number)
	local ownerId = player.UserId
	productionModifiers[ownerId] = math.clamp(modifier, 0, 1)
	WorkerDebug:info(`Production modifier for owner {ownerId} set to {productionModifiers[ownerId]}`)
end

return WorkerManager
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             