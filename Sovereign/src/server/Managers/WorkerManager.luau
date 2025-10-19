local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameData = require(ReplicatedStorage.Shared.GameData)
local ResourceNodeManager = require(script.Parent.ResourceNodeManager)
local PlayerManager = require(script.Parent.PlayerManager)
local BuildingManager = require(script.Parent.BuildingManager)
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)

local WorkerManager = {}

-- Create debug channels
local WorkerDebug = DebugManager.createChannel("Worker", true) -- Workers gathering (disabled by default)
local HaulerDebug = DebugManager.createChannel("Hauler", true) -- Haulers transporting (enabled)
local MovementDebug = DebugManager.createChannel("Movement", false) -- Movement (disabled, very spammy)

-- Job type mapping
local JOB_TRANSFORMATIONS = {
	Woodcutters_Post = "Woodcutter",
	Stone_Quarry = "Stonemason",
	Farm = "Farmer",
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

-- Simple pathfinding - use 2D distance to avoid Y-axis issues
local function moveTowards(unit: Model, targetPos: Vector3, speed: number): boolean
	if not unit.PrimaryPart then
		MovementDebug:warn("Unit has no PrimaryPart!")
		return true
	end

	local currentPos = unit.PrimaryPart.Position

	-- Calculate 2D distance (ignore Y axis)
	local currentPos2D = Vector3.new(currentPos.X, 0, currentPos.Z)
	local targetPos2D = Vector3.new(targetPos.X, 0, targetPos.Z)
	local distance2D = (targetPos2D - currentPos2D).Magnitude

	-- Increased arrival threshold to 8 studs
	if distance2D > 8 then
		-- Move towards target (keep current Y position)
		local direction = (targetPos2D - currentPos2D).Unit
		local newPos = currentPos + (direction * speed)
		unit:SetPrimaryPartCFrame(CFrame.new(newPos))
		return false -- Not arrived
	else
		MovementDebug:info(`Unit arrived!`, { distance = distance2D })
		return true -- Arrived
	end
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
			local arrived = moveTowards(task.worker, task.workplace.Position, 0.5)

			if arrived then
				WorkerDebug:info(`Worker arrived at workplace`, {
					currentType = task.worker:GetAttribute("UnitType"),
					transformingTo = task.jobType,
				})
				transformWorker(task.worker, task.jobType)
				task.state = "Gathering"
			end
		elseif task.state == "Gathering" then
			-- Find and gather from resource node
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
					local gatherRate = buildingInfo.production_rate or 1
					local gathered = ResourceNodeManager.gatherFromNode(task.targetNode, gatherRate * deltaTime * 2)
					task.resourcesCarrying = task.resourcesCarrying + gathered

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
		elseif task.state == "ReturningToWorkplace" then
			-- Return resources to workplace
			local arrived = moveTowards(task.worker, task.workplace.Position, 0.5)
			if arrived then
				-- Deposit to workplace storage
				local deposited =
					BuildingManager.addToStorage(task.workplace, task.resourceType, task.resourcesCarrying)
				WorkerDebug:info(`{task.jobType} deposited resources`, {
					amount = deposited,
					resourceType = task.resourceType,
				})
				task.resourcesCarrying = 0

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
		if not task.hauler or not task.hauler.Parent then
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
				local arrived = moveTowards(task.hauler, task.sourceBuilding.Position, 0.4)

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
				local arrived = moveTowards(task.hauler, task.targetStorage.Position, 0.4)

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
