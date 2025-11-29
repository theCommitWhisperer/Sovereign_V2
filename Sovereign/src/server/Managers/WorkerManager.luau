local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameData = require(ReplicatedStorage.Shared.GameData)
local ResourceNodeManager = require(script.Parent.ResourceNodeManager)
local PlayerManager = require(script.Parent.PlayerManager)
local BuildingManager = require(script.Parent.BuildingManager)
local ProductionChainManager = require(script.Parent.ProductionChainManager)
local WeatherManager = require(script.Parent.WeatherManager)
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)

local WorkerManager = {}
-- Create debug channels
local WorkerDebug = DebugManager.createChannel("Worker", false) -- Workers gathering (disabled by default)
local HaulerDebug = DebugManager.createChannel("Hauler", false) -- Haulers transporting (enabled)
local MovementDebug = DebugManager.createChannel("Movement", false) -- Movement (disabled, very spammy)

-- Job type mapping
local JOB_TRANSFORMATIONS = {
	Woodcutters_Post = "Woodcutter",
	Stone_Quarry = "Stonemason",
	Farm = "Farmer",
	Iron_Mine = "Miner",
	Smithy = "Blacksmith",
	Weaponsmith = "Weaponsmith",
	Bakery = "Baker",
	Brewery = "Brewer",
	Market = "Merchant",
	Trading_Post = "Trader",
}

export type WorkerTask = {
	worker: Model,
	workplace: Instance,
	workplaceType: string,
	resourceType: string,
	jobType: string,
	state: "GoingToWorkplace" | "Gathering" | "ReturningToWorkplace",
	resourcesCarrying: number,
	targetNode: any?,
	ownerId: number,
}

export type HaulerTask = {
	hauler: Model,
	state: "Idle" | "GoingToPickup" | "GoingToStorage",
	resourcesCarrying: number,
	resourceType: string?,
	sourceBuilding: Instance?,
	targetStorage: Instance?,
	ownerId: number,
}

local WorkerTasks: { WorkerTask } = {}
local HaulerTasks: { HaulerTask } = {}
local productionModifiers: { [number]: number } = {}

function WorkerManager.setProductionModifier(player: Player, modifier: number)
	if not player then
		return
	end
	productionModifiers[player.UserId] = modifier
	WorkerDebug:info(`Set production modifier for {player.Name} to {modifier}`)
end

-- Transform a peasant into a specialized worker
local function transformWorker(worker: Model, jobType: string)
	-- Extract the ID suffix from the current name
	local idSuffix = worker.Name:match("_(%d+_%d+)$")
	if idSuffix then
		worker.Name = jobType .. "_" .. idSuffix
	else
		-- Fallback if pattern doesn't match
		worker.Name = jobType .. "_" .. tostring(math.random(1000, 9999))
	end

	worker:SetAttribute("UnitType", jobType)

	WorkerDebug:info(`Transformed {worker.Name} to {jobType}`, {
		unitType = jobType
	})

	-- Update humanoid properties if needed
	local humanoid = worker:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local unitInfo = GameData.Units[jobType]
		if unitInfo then
			humanoid.WalkSpeed = unitInfo.movement.speed_meters_per_second * 16
		end
	end

	-- Change color based on job
	for _, part in worker:GetDescendants() do
		if part:IsA("BasePart") and part.Name == "Head" then
			if jobType == "Woodcutter" then
				part.Color = Color3.fromRGB(139, 69, 19) -- Brown
			elseif jobType == "Stonemason" then
				part.Color = Color3.fromRGB(128, 128, 128) -- Gray
			elseif jobType == "Farmer" then
				part.Color = Color3.fromRGB(144, 238, 144) -- Light green
			end
		end
	end

	WorkerDebug:info(`Transformed {worker.Name} to {jobType}`, {
		unitType = worker:GetAttribute("UnitType"),
	})
end

-- Assign a peasant to a production building
function WorkerManager.assignWorkerToBuilding(worker: Model, building: Instance, ownerId: number)
	local buildingType = building:GetAttribute("BuildingType")
	if not buildingType then
		WorkerDebug:warn("Building has no type")
		return
	end

	local buildingInfo = GameData.Buildings[buildingType]
	if not buildingInfo or not buildingInfo.produces_resource then
		WorkerDebug:warn(`{buildingType} doesn't produce resources`)
		return
	end

	local jobType = JOB_TRANSFORMATIONS[buildingType]
	if not jobType then
		WorkerDebug:warn(`No job type for {buildingType}`)
		return
	end

	WorkerDebug:info(`Assigning peasant to {buildingType}`)

	local task: WorkerTask = {
		worker = worker,
		workplace = building,
		workplaceType = buildingType,
		resourceType = buildingInfo.produces_resource,
		jobType = jobType,
		state = "GoingToWorkplace",
		resourcesCarrying = 0,
		targetNode = nil,
		ownerId = ownerId,
	}

	table.insert(WorkerTasks, task)
	worker:SetAttribute("IsWorking", true)
	worker:SetAttribute("AssignedTo", buildingType)
end

-- Assign a peasant or ox as a hauler
function WorkerManager.assignHauler(hauler: Model, ownerId: number)
	local task: HaulerTask = {
		hauler = hauler,
		state = "Idle",
		resourcesCarrying = 0,
		resourceType = nil,
		sourceBuilding = nil,
		targetStorage = nil,
		ownerId = ownerId,
	}

	table.insert(HaulerTasks, task)
	hauler:SetAttribute("IsHauling", true)
	HaulerDebug:info(`Assigned {hauler:GetAttribute("UnitType")} as hauler`)
end

-- Find nearest storage with space
local function findStorageWithSpace(
	position: Vector3,
	resourceType: string,
	ownerId: number,
	excludeBuilding: Instance?
): Instance?
	local playerData = PlayerManager.get(game.Players:GetPlayerByUserId(ownerId))
	if not playerData then
		return nil
	end

	local nearest: Instance? = nil
	local nearestDistance = math.huge

	for _, building in playerData.Buildings do
		if building and building.Parent and building ~= excludeBuilding then
			local buildingType = building:GetAttribute("BuildingType")
			if buildingType then
				local buildingInfo = GameData.Buildings[buildingType]
				if buildingInfo and buildingInfo.storage_capacity and buildingInfo.storage_capacity[resourceType] then
					if BuildingManager.hasStorageSpace(building, resourceType, 1) then
						local distance = (building.Position - position).Magnitude
						if distance < nearestDistance then
							nearest = building
							nearestDistance = distance
							HaulerDebug:info(`Found storage {buildingType} for {resourceType}`, {
								distance = distance,
							})
						end
					end
				end
			end
		end
	end

	if not nearest then
		HaulerDebug:warn(`No storage with space found for {resourceType}!`)
	end

	return nearest
end

-- Find production building with resources ready for pickup
local function findBuildingWithResources(position: Vector3, ownerId: number): (Instance?, string?)
	local playerData = PlayerManager.get(game.Players:GetPlayerByUserId(ownerId))
	if not playerData then
		return nil, nil
	end

	local nearest: Instance? = nil
	local nearestDistance = math.huge
	local resourceType: string? = nil

	for _, building in playerData.Buildings do
		if building and building.Parent then
			local buildingType = building:GetAttribute("BuildingType")
			if buildingType then
				local buildingInfo = GameData.Buildings[buildingType]
				-- Check if it's a production building
				if buildingInfo and buildingInfo.produces_resource then
					local stored = BuildingManager.getStorageAmount(building, buildingInfo.produces_resource)

					if stored >= 10 then -- Minimum amount to transport
						local distance = (building.Position - position).Magnitude
						if distance < nearestDistance then
							nearest = building
							nearestDistance = distance
							resourceType = buildingInfo.produces_resource
							HaulerDebug:info(`Found building with resources`, {
								buildingType = buildingType,
								stored = stored,
								resourceType = resourceType,
								distance = distance,
							})
						end
					end
				end
			end
		end
	end

	if not nearest then
		-- Only log occasionally to avoid spam
		if math.random() < 0.01 then
			HaulerDebug:info("No buildings with >= 10 resources found")
		end
	end

	return nearest, resourceType
end

-- Calculate arrival threshold based on building size
local function getBuildingArrivalThreshold(building: Instance): number
	local buildingPart = nil

	-- Handle both Model and Part buildings
	if building:IsA("Model") then
		buildingPart = building.PrimaryPart or building:FindFirstChildWhichIsA("Part")
	elseif building:IsA("BasePart") then
		buildingPart = building
	end

	if not buildingPart then
		return 10
	end

	-- Get building size (use the larger of X or Z dimensions)
	local size = buildingPart.Size
	local maxDimension = math.max(size.X, size.Z)

	-- Threshold = half the building's largest dimension + small buffer
	-- Reduced buffer to prevent overlapping with nearby buildings
	return (maxDimension / 2) + 5
end

-- Pathfinding-based movement to a building
local function moveTowardsBuilding(unit: Model, building: Instance, speed: number): boolean
	if not unit.PrimaryPart then
		WorkerDebug:warn("Unit has no PrimaryPart!", { unitName = unit.Name })
		return true
	end

	-- Get building part (handle both Model and Part)
	local buildingPart = nil
	if building:IsA("Model") then
		buildingPart = building.PrimaryPart or building:FindFirstChildWhichIsA("Part")
	elseif building:IsA("BasePart") then
		buildingPart = building
	end

	if not buildingPart then
		WorkerDebug:warn("Building has no valid part!")
		return true
	end

	local currentPos = unit.PrimaryPart.Position
	local buildingPos = buildingPart.Position

	-- Calculate 2D distance (ignore Y axis)
	local currentPos2D = Vector3.new(currentPos.X, 0, currentPos.Z)
	local buildingPos2D = Vector3.new(buildingPos.X, 0, buildingPos.Z)
	local distance2D = (buildingPos2D - currentPos2D).Magnitude

	-- Calculate dynamic arrival threshold based on building size
	local arrivalThreshold = getBuildingArrivalThreshold(building)

	-- Check if we've arrived
	if distance2D <= arrivalThreshold then
		-- Stop movement
		unit:SetAttribute("IsMoving", false)
		unit:SetAttribute("TargetPosition", nil)
		WorkerDebug:info(`Worker arrived at building`, {
			unitName = unit.Name,
			distance = distance2D,
			threshold = arrivalThreshold
		})
		return true -- Arrived
	end

	-- Not arrived yet - pathfind to building center
	local currentTarget = unit:GetAttribute("TargetPosition")
	local isMoving = unit:GetAttribute("IsMoving")

	-- Only update if target changed or unit isn't moving
	if not isMoving or not currentTarget or (currentTarget - buildingPos).Magnitude > 1 then
		unit:SetAttribute("TargetPosition", buildingPos)
		unit:SetAttribute("IsMoving", true)
		WorkerDebug:info(`Worker pathfinding to building`, {
			unitName = unit.Name,
			distance = distance2D,
			threshold = arrivalThreshold
		})
	end

	return false -- Not arrived yet
end

-- Simple movement to a position (for resource nodes)
local function moveTowards(unit: Model, targetPos: Vector3, speed: number): boolean
	if not unit.PrimaryPart then
		WorkerDebug:warn("Unit has no PrimaryPart!", { unitName = unit.Name })
		return true
	end

	local currentPos = unit.PrimaryPart.Position

	-- Calculate 2D distance (ignore Y axis)
	local currentPos2D = Vector3.new(currentPos.X, 0, currentPos.Z)
	local targetPos2D = Vector3.new(targetPos.X, 0, targetPos.Z)
	local distance2D = (targetPos2D - currentPos2D).Magnitude

	-- Check if we've arrived (5 stud threshold for resource nodes)
	if distance2D <= 5 then
		-- Stop movement
		unit:SetAttribute("IsMoving", false)
		unit:SetAttribute("TargetPosition", nil)
		return true -- Arrived
	end

	-- Not arrived yet - ensure MovementSystem is handling this unit
	local currentTarget = unit:GetAttribute("TargetPosition")
	local isMoving = unit:GetAttribute("IsMoving")

	-- Only update if target changed or unit isn't moving
	if not isMoving or not currentTarget or (currentTarget - targetPos).Magnitude > 1 then
		unit:SetAttribute("TargetPosition", targetPos)
		unit:SetAttribute("IsMoving", true)
		WorkerDebug:info(`Worker starting pathfinding movement`, {
			unitName = unit.Name,
			distance = distance2D,
			targetPos = targetPos
		})
	end

	return false -- Not arrived yet
end
-- Update worker tasks
local function updateWorkerTasks(deltaTime: number)
	for _, task in WorkerTasks do
		if not task.worker or not task.worker.Parent or not task.workplace or not task.workplace.Parent then
			continue
		end

		local buildingInfo = GameData.Buildings[task.workplaceType]
		if not buildingInfo then
			continue
		end

		local unitInfo = GameData.Units[task.jobType]
		local carryCapacity = unitInfo and unitInfo.carry_capacity or 10

		if task.state == "GoingToWorkplace" then
			-- Walk to workplace and transform
			local arrived = moveTowardsBuilding(task.worker, task.workplace, 0.5)

			if arrived then
				WorkerDebug:info(`Worker arrived at workplace - transforming`, {
					workerName = task.worker.Name,
					currentType = task.worker:GetAttribute("UnitType"),
					transformingTo = task.jobType,
					workplaceType = task.workplaceType,
				})
				transformWorker(task.worker, task.jobType)
				task.state = "Gathering"
				WorkerDebug:info(`Worker state changed to Gathering`, {
					workerName = task.worker.Name,
					jobType = task.jobType,
				})
			end
		elseif task.state == "Gathering" then
			-- Check if this is a resource production building (all types handled uniformly)
			local isProducer = ProductionChainManager.isProductionChainBuilding(task.workplaceType)

			if isProducer then
				-- Production building: produce resources at workplace
				-- Worker stays at workplace and produces the resource
				-- (Handles both passive producers like Farms and production chains like Smithy)

				-- Verify worker is still at the workplace
				local atWorkplace = false
				if task.worker.PrimaryPart and task.workplace then
					local buildingPart = nil
					if task.workplace:IsA("Model") then
						buildingPart = task.workplace.PrimaryPart or task.workplace:FindFirstChildWhichIsA("Part")
					elseif task.workplace:IsA("BasePart") then
						buildingPart = task.workplace
					end

					if buildingPart then
						local workerPos = task.worker.PrimaryPart.Position
						local buildingPos = buildingPart.Position
						local distance = (Vector3.new(workerPos.X, 0, workerPos.Z) - Vector3.new(buildingPos.X, 0, buildingPos.Z)).Magnitude
						local threshold = getBuildingArrivalThreshold(task.workplace)
						atWorkplace = distance <= threshold

						if not atWorkplace then
							-- Worker wandered away, send them back
							WorkerDebug:warn(`{task.jobType} wandered from workplace, distance: {distance}`)
							task.state = "GoingToWorkplace"
						end
					end
				end

				if not atWorkplace then
					-- Worker not at workplace, skip production this frame
					continue
				end

				-- Check if building can produce (handles input requirements automatically)
				local canProduce = ProductionChainManager.canProduce(task.workplace)

				if canProduce then
					-- Produce resources at the workplace
					local modifier = productionModifiers[task.ownerId] or 1
					local productionRate = (buildingInfo.production_rate or 1) * modifier
					local produced = productionRate * deltaTime * 2

					-- Consume input resources (returns true for passive producers automatically)
					local consumed = ProductionChainManager.consumeInputs(task.workplace)

					if consumed then
						task.resourcesCarrying = task.resourcesCarrying + produced
						task.worker:SetAttribute("ResourcesCarrying", task.resourcesCarrying)
						task.worker:SetAttribute("ResourceType", task.resourceType)

						WorkerDebug:info(`{task.jobType} producing {task.resourceType}`, {
							carrying = task.resourcesCarrying,
							capacity = carryCapacity,
							produced = produced,
						})

						-- If full, deposit
						if task.resourcesCarrying >= carryCapacity then
							task.state = "ReturningToWorkplace"
							WorkerDebug:info(`{task.jobType} produced {task.resourcesCarrying} {task.resourceType}`)
						end
					else
						-- Cannot produce, wait for input resources
						WorkerDebug:warn(`{task.jobType} waiting for input resources`)
					end
				else
					-- Not enough input resources, wait
					WorkerDebug:warn(`{task.workplaceType} lacks input resources for production`)
				end
			else
				-- Traditional resource gathering from nodes
				if not task.targetNode then
					task.targetNode = ResourceNodeManager.findNearestNode(task.workplace.Position, task.resourceType)
					if task.targetNode then
						WorkerDebug:info(`{task.jobType} found {task.resourceType} node`, {
							position = task.targetNode.Position,
						})
					else
						WorkerDebug:warn(`No {task.resourceType} nodes found!`)
					end
				end

				if task.targetNode then
					local arrived = moveTowards(task.worker, task.targetNode.Position, 0.5)
					if arrived then
						-- Gather resources
						local modifier = productionModifiers[task.ownerId] or 1
						local baseRate = buildingInfo.production_rate or 1

						-- Apply weather/seasonal effects
						local weatherModifier = 1.0
						local player = game.Players:GetPlayerByUserId(task.ownerId)
						if player then
							if task.workplaceType == "Farm" then
								weatherModifier = WeatherManager.getFarmProductionMultiplier(player)
							elseif task.workplaceType == "Iron_Mine" then
								weatherModifier = WeatherManager.getMiningProductionMultiplier(player)
							end
						end

						local gatherRate = baseRate * modifier * weatherModifier
						local gathered = ResourceNodeManager.gatherFromNode(task.targetNode, gatherRate * deltaTime * 2)
						task.resourcesCarrying = task.resourcesCarrying + gathered
						task.worker:SetAttribute("ResourcesCarrying", task.resourcesCarrying)
						task.worker:SetAttribute("ResourceType", task.resourceType)

						WorkerDebug:info(`{task.jobType} gathering`, {
							gathered = gathered,
							carrying = task.resourcesCarrying,
							capacity = carryCapacity,
							gatherRate = gatherRate,
							deltaTime = deltaTime,
						})

						-- If full or node depleted, return
						if task.resourcesCarrying >= carryCapacity then
							task.state = "ReturningToWorkplace"
							task.targetNode = nil
							WorkerDebug:info(`{task.jobType} full, returning`, {
								carrying = task.resourcesCarrying,
								resourceType = task.resourceType,
							})
						elseif gathered == 0 then
							-- Node depleted, find another
							task.targetNode = nil
							WorkerDebug:info("Node depleted, looking for another")
						end
					end
				else
					-- No nodes available, return to workplace
					WorkerDebug:warn(`No nodes available for {task.resourceType}`)
					task.state = "ReturningToWorkplace"
				end
			end
		elseif task.state == "ReturningToWorkplace" then
			-- Return resources to workplace
			local arrived = moveTowardsBuilding(task.worker, task.workplace, 0.5)
			if arrived then
				-- Deposit to workplace storage
				local deposited =
					BuildingManager.addToStorage(task.workplace, task.resourceType, task.resourcesCarrying)
				WorkerDebug:info(`{task.jobType} deposited resources`, {
					amount = deposited,
					resourceType = task.resourceType,
				})
				task.resourcesCarrying = 0
				task.worker:SetAttribute("ResourcesCarrying", 0)
				task.worker:SetAttribute("ResourceType", nil)

				-- Go back to gathering
				task.state = "Gathering"
				task.targetNode = nil
			end
		end
	end
end

-- Update hauler tasks
local function updateHaulerTasks(deltaTime: number)
	for i, task in HaulerTasks do
		if not task.hauler or not task.hauler.Parent then --[[ ROBLOX CHECK: CHECK_NOT_NIL, task.hauler might be nil, so this check is necessary to prevent potential errors. ]]
			HaulerDebug:warn(`Removing invalid hauler task {i}`)
			continue
		end

		local unitInfo = GameData.Units[task.hauler:GetAttribute("UnitType")]
		local carryCapacity = unitInfo and unitInfo.carry_capacity or 10

		if task.state == "Idle" then
			-- Look for production buildings with resources to haul
			local sourceBuilding, resourceType =
				findBuildingWithResources(task.hauler.PrimaryPart.Position, task.ownerId)
			if sourceBuilding and resourceType then
				task.sourceBuilding = sourceBuilding
				task.resourceType = resourceType
				task.state = "GoingToPickup"
				HaulerDebug:info(`Hauler going to pickup`, {
					haulerName = task.hauler.Name,
					resourceType = resourceType,
					buildingName = sourceBuilding.Name,
				})
			end
		elseif task.state == "GoingToPickup" then
			if task.sourceBuilding and task.sourceBuilding.Parent and task.resourceType then
				local arrived = moveTowardsBuilding(task.hauler, task.sourceBuilding, 0.4)

				if arrived then
					-- Pick up resources
					local storedAmount = BuildingManager.getStorageAmount(task.sourceBuilding, task.resourceType)
					HaulerDebug:info(`Hauler arrived at pickup`, {
						building = task.sourceBuilding.Name,
						storedAmount = storedAmount,
					})

					local amount =
						BuildingManager.takeFromStorage(task.sourceBuilding, task.resourceType, carryCapacity)
					task.resourcesCarrying = amount
					task.hauler:SetAttribute("ResourcesCarrying", amount)
					task.hauler:SetAttribute("ResourceType", task.resourceType)

					if amount > 0 then
						HaulerDebug:info(`Hauler picked up resources`, {
							amount = amount,
							resourceType = task.resourceType,
						})

						-- Find storage
						local storage = findStorageWithSpace(
							task.hauler.PrimaryPart.Position,
							task.resourceType,
							task.ownerId,
							task.sourceBuilding
						)
						if storage then
							task.targetStorage = storage
							task.state = "GoingToStorage"
							HaulerDebug:info(`Hauler going to storage`, {
								storageName = storage.Name,
							})
						else
							HaulerDebug:warn(`No storage found for {task.resourceType}!`)
							-- Put resources back
							BuildingManager.addToStorage(task.sourceBuilding, task.resourceType, amount)
							task.resourcesCarrying = 0
							task.hauler:SetAttribute("ResourcesCarrying", 0)
							task.hauler:SetAttribute("ResourceType", nil)
							task.state = "Idle"
						end
					else
						HaulerDebug:warn(`No resources to pick up from {task.sourceBuilding.Name}`)
						task.state = "Idle"
						task.sourceBuilding = nil
						task.resourceType = nil
					end
				end
			else
				HaulerDebug:warn("Hauler lost source building or resource type")
				task.state = "Idle"
				task.sourceBuilding = nil
				task.resourceType = nil
			end
		elseif task.state == "GoingToStorage" then
			if task.targetStorage and task.targetStorage.Parent and task.resourceType then
				local arrived = moveTowardsBuilding(task.hauler, task.targetStorage, 0.4)

				if arrived then
					HaulerDebug:info(`Hauler arrived at storage`, {
						carrying = task.resourcesCarrying,
						resourceType = task.resourceType,
					})

					-- Deposit to storage
					local deposited =
						BuildingManager.addToStorage(task.targetStorage, task.resourceType, task.resourcesCarrying)

					-- Add to player resources
					local player = game.Players:GetPlayerByUserId(task.ownerId)
					if player and deposited > 0 then
						PlayerManager.addResources(player, { [task.resourceType] = deposited })
						HaulerDebug:info(`Added resources to player`, {
							amount = deposited,
							resourceType = task.resourceType,
						})

						-- Notify client
						local RemoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")
						if RemoteEvents then
							local gameEvent = RemoteEvents:FindFirstChild("GameEvent")
							if gameEvent then
								local playerData = PlayerManager.get(player)
								if playerData then
									gameEvent:FireClient(player, "UpdateResources", {
										resources = playerData.Resources,
									})
								end
							end
						end
					end

					-- Reset
					task.resourcesCarrying = 0
					task.resourceType = nil
					task.hauler:SetAttribute("ResourcesCarrying", 0)
					task.hauler:SetAttribute("ResourceType", nil)
					task.sourceBuilding = nil
					task.targetStorage = nil
					task.state = "Idle"
					HaulerDebug:info("Hauler delivered resources, now idle")
				end
			else
				HaulerDebug:warn("Hauler lost target storage or resource type")
				task.state = "Idle"
				task.resourceType = nil
				task.sourceBuilding = nil
				task.targetStorage = nil
			end
		end
	end
end

-- Unassign all workers from a building (called when building is deleted)
function WorkerManager.unassignWorkersFromBuilding(building: Instance)
	-- Remove all worker tasks associated with this building
	for i = #WorkerTasks, 1, -1 do
		local task = WorkerTasks[i]
		if task.workplace == building then
			WorkerDebug:info(`Unassigning worker from deleted building`, {
				workerName = task.worker.Name,
				buildingType = task.workplaceType,
			})

			-- Clear worker attributes
			task.worker:SetAttribute("IsWorking", false)
			task.worker:SetAttribute("AssignedTo", nil)
			task.worker:SetAttribute("TargetPosition", nil)
			task.worker:SetAttribute("IsMoving", false)

			-- Remove task
			table.remove(WorkerTasks, i)
		end
	end

	-- Remove all hauler tasks associated with this building
	local buildingOwnerId = building:GetAttribute("Owner")
	WorkerDebug:info(`Checking ${#HaulerTasks} hauler tasks for deletion cleanup`)

	for i = #HaulerTasks, 1, -1 do
		local task = HaulerTasks[i]

		-- Check if hauler is working with this building (either as source or target)
		-- OR if hauler belongs to the same owner and is idle (hasn't found buildings yet)
		local isRelatedToBuilding = task.sourceBuilding == building
			or task.targetStorage == building
			or (task.ownerId == buildingOwnerId and task.state == "Idle")

		if isRelatedToBuilding then
			WorkerDebug:info(`Unassigning hauler from deleted building`, {
				haulerName = task.hauler.Name,
				haulerState = task.state,
				wasSource = task.sourceBuilding == building,
				wasTarget = task.targetStorage == building,
				wasIdle = task.state == "Idle",
			})

			-- Clear hauler attributes
			task.hauler:SetAttribute("IsHauling", false)
			task.hauler:SetAttribute("TargetPosition", nil)
			task.hauler:SetAttribute("IsMoving", false)

			-- Remove task
			table.remove(HaulerTasks, i)
		end
	end
end

-- Main update loop
function WorkerManager.update(deltaTime: number)
	updateWorkerTasks(deltaTime)
	updateHaulerTasks(deltaTime)
end

RunService.Heartbeat:Connect(function(deltaTime)
	WorkerManager.update(deltaTime)
end)

HaulerDebug:info("WorkerManager initialized with job transformations and hauling")
return WorkerManager
