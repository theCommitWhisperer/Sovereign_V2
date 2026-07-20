--!strict
-- WorkerManager: assignment, transformation and the hybrid production loop.
--
-- Design (economy-rework-v2):
--   • A peasant is ASSIGNED to a building (auto on placement or manually via the
--     WorkerAssignmentPanel). It walks to the building's approach position and,
--     ON ARRIVAL, transforms into its job unit (Farmer, Woodcutter, ...).
--   • Buildings produce in one of two modes:
--       - PASSIVE (processors / farms): once staffed, the BUILDING produces its
--         output on a timer straight into its own storage, consuming inputs for
--         production-chain buildings. Output scales with staffed workers (capped
--         at worker_slots).
--       - GATHER (lumberjack / quarry / mine): the worker walks out to the nearest
--         matching ResourceNode, harvests, walks back and deposits — the stored
--         count rises on return. If a map has no matching nodes the gatherer falls
--         back to passive output so the economy never stalls.
--   • HAULERS relay resources: producer output → central storage, and input
--     supply from central storage → hungry processors.
--
-- Navigation (why we no longer depend on worker-point PARTS):
--   Workers/haulers target a building's ApproachPosition — a guaranteed-walkable,
--   graph-connected cell next to the building, computed from geometry + the live
--   pathfinding grid at placement (see PathfindingIntegration.getApproachPosition
--   and BuildingManager). Authored BuildingEntrance / ProductionStation parts are
--   now an OPTIONAL refinement, not a requirement — they can no longer strand a
--   worker by being missing, buried, or inside the obstacle.
--
-- Arrival unification:
--   MovementSystem owns locomotion and clears IsMoving/TargetPosition once a unit
--   is within its own ~5-stud tolerance (or gives up near the goal). pathfindTo-
--   Position clamps its arrival radius OUTSIDE MovementSystem's and treats a
--   stopped-near-goal unit as arrived, so workers never park short. A per-state
--   stuck-timeout snap is a last-resort guarantee.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameData = require(ReplicatedStorage.Shared.GameData)
local BuildingManager = require(script.Parent.BuildingManager)
local ProductionChainManager = require(script.Parent.ProductionChainManager)
local BuildingTypeHelper = require(ReplicatedStorage.Shared.BuildingTypeHelper)
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)
local WorkerPointSystem = require(script.Parent.Parent.Systems.WorkerPointSystem)
local IdlePeasantManager = require(script.Parent.IdlePeasantManager)
local ResourceNodeManager = require(script.Parent.ResourceNodeManager)
local PathfindingIntegration = require(script.Parent.Parent.Systems.PathfindingIntegration)

local WorkerManager = {}

-- Debug channels
local WorkerDebug = DebugManager.createChannel("Worker", false)
local HaulerDebug = DebugManager.createChannel("Hauler", false)

-- ============================================
-- TUNING
-- ============================================

local CONFIG = {
	-- Arrival: MUST exceed MovementSystem.CONFIG.ARRIVAL_DISTANCE (5) so a unit
	-- that MovementSystem parks is recognised here as arrived.
	MIN_ARRIVAL = 6,
	-- If MovementSystem stopped a unit (IsMoving cleared) within this radius of
	-- the goal, accept it — MovementSystem won't get any closer.
	GIVEUP_RADIUS = 12,
	-- Seconds a worker may spend trying to reach its building before we snap it
	-- there. A last-resort guarantee; with reliable pathfinding it rarely fires.
	WALK_STUCK_TIMEOUT = 8,
	-- Gather loop
	GATHER_ARRIVAL = 6,
	-- Hauler cadence
	HAULER_ASSIGNMENT_INTERVAL = 5,
	HAULER_PICKUP_AMOUNT = 15,
	HAULER_OUTPUT_THRESHOLD = 5, -- building output before an output-hauler is called
	HAULER_SUPPLY_MIN = 5, -- deliver this much input to a starving processor
	HAULER_UNLOAD_SECONDS = 3,
}

-- Active tasks
local WorkerTasks: { WorkerTask } = {}
local HaulerTasks: { HaulerTask } = {}
local BuildingProduction: { [Instance]: BuildingProductionState } = {}

-- Hauler assignment timer
local lastHaulerAssignmentTime = 0

-- Per-owner production modifier (set by HappinessManager / RevoltManager)
-- 1.0 = full production, 0.5 = half, 0 = halted
local productionModifiers: { [number]: number } = {}

-- ============================================
-- TYPES
-- ============================================

export type WorkerTask = {
	worker: Model,
	workplace: Instance,
	workplaceType: string,
	resourceType: string?,
	jobType: string,
	isGatherer: boolean,
	state: "WalkingToEntrance" | "Working" | "GatheringResources" | "ReturningToDropoff",
	resourcesCarrying: number,
	targetNode: any?,
	ownerId: number,
	hasTransformed: boolean,
	atStation: boolean,
	walkStartTime: number,
	fallbackProductionTime: number, -- gatherer passive-fallback timer
}

export type HaulerTask = {
	hauler: Model,
	role: "Output" | "Supply",
	state: "Idle" | "WalkingToPickup" | "WalkingToStorage" | "UnloadingInside",
	resourcesCarrying: number,
	resourceType: string?,
	sourceBuilding: Instance?,
	targetStorage: Instance?,
	ownerId: number,
	unloadStartTime: number?,
	storageEntrancePos: Vector3?,
}

export type BuildingProductionState = {
	building: Instance,
	buildingType: string,
	lastProductionTime: number,
}

-- ============================================
-- SMALL HELPERS
-- ============================================

local function horizontalDistance(a: Vector3, b: Vector3): number
	local d = a - b
	return Vector3.new(d.X, 0, d.Z).Magnitude
end

local function getModifier(ownerId: number?): number
	if not ownerId then
		return 1.0
	end
	return productionModifiers[ownerId] or 1.0
end

-- Seconds between production ticks. Prefer an explicit production_time; else
-- derive from production_rate (units/second).
local function getProductionInterval(buildingInfo: any): number
	if buildingInfo.production_time and buildingInfo.production_time > 0 then
		return buildingInfo.production_time
	end
	local rate = buildingInfo.production_rate or 1
	if rate <= 0 then
		rate = 1
	end
	return 1 / rate
end

local function getProductionOutput(buildingInfo: any): number
	return buildingInfo.production_output or 1
end

local function getWorkerCapacity(buildingInfo: any): number
	return buildingInfo.worker_slots or 1
end

local function isGathererBuilding(buildingInfo: any): boolean
	return buildingInfo.worker_gathers_from_nodes == true
end

-- Can this unit be put to work? Peasants, and any civilian/worker job unit that
-- has been released back to idle (so unassigned workers can be re-staffed rather
-- than draining the labour pool). Never soldiers.
local function isAssignableCivilian(unit: Model): boolean
	local unitType = unit:GetAttribute("UnitType")
	if unitType == "Peasant" then
		return true
	end
	local unitData = unitType and GameData.Units[unitType]
	return unitData ~= nil and unitData.subtype == "Worker"
end

-- ============================================
-- MOVEMENT (unified arrival with MovementSystem)
-- ============================================

-- Issue / refresh a move order toward targetPos. Returns true once arrived.
local function pathfindToPosition(unit: Model, targetPos: Vector3, arrivalThreshold: number): boolean
	local pp = unit.PrimaryPart
	if not pp then
		return true
	end

	local distance2D = horizontalDistance(pp.Position, targetPos)
	local threshold = math.max(arrivalThreshold, CONFIG.MIN_ARRIVAL)

	if distance2D <= threshold then
		unit:SetAttribute("IsMoving", false)
		unit:SetAttribute("TargetPosition", nil)
		return true
	end

	-- MovementSystem cleared IsMoving (reached its own tolerance, or gave up
	-- against geometry near the goal). If we're close, treat as arrived so the
	-- worker loop never stalls waiting for a tolerance MovementSystem won't hit.
	if not unit:GetAttribute("IsMoving") and distance2D <= CONFIG.GIVEUP_RADIUS then
		unit:SetAttribute("TargetPosition", nil)
		return true
	end

	-- (Re)issue the move order toward this point.
	local currentTarget = unit:GetAttribute("TargetPosition")
	if typeof(currentTarget) ~= "Vector3" or (currentTarget - targetPos).Magnitude > 1 then
		unit:SetAttribute("TargetPosition", targetPos)
		unit:SetAttribute("IsMoving", true)
		unit:SetAttribute("PathfindingFailed", nil)
	end
	return false
end

-- The position a worker/hauler should navigate to in order to interact with a
-- building. Primary source is the cached, guaranteed-walkable ApproachPosition
-- (computed from geometry + the walkable grid at placement); we fall back to an
-- optional authored worker point, then the building centre.
local function getInteractionPos(building: Instance): Vector3?
	local cached = building:GetAttribute("ApproachPosition")
	if typeof(cached) == "Vector3" then
		return cached
	end

	-- Not cached yet (older buildings / battle sandbox) — compute and store it.
	if building:IsA("Model") then
		local pos = PathfindingIntegration.getApproachPosition(building)
		if pos then
			building:SetAttribute("ApproachPosition", pos)
			return pos
		end
	end

	-- Optional authored point, then centre, as a last resort.
	local pointPos = WorkerPointSystem.getPointPosition(building :: any, "BuildingEntrance" :: any)
	if pointPos then
		return pointPos
	end
	return building:IsA("Model") and (building :: Model):GetPivot().Position or nil
end

-- Walk a unit to a building's approach position. Returns true on arrival.
local function pathfindToBuilding(unit: Model, building: Instance, arrivalThreshold: number): boolean
	if not unit.PrimaryPart then
		return true
	end
	local targetPos = getInteractionPos(building)
	if not targetPos then
		return false
	end
	return pathfindToPosition(unit, targetPos, arrivalThreshold)
end

-- If a worker has been trying to reach its building for too long, snap it to the
-- approach position so the state machine can always make progress. A last-resort
-- guarantee — with reliable pathfinding it should almost never fire.
local function snapIfStuck(task: WorkerTask): boolean
	if tick() - task.walkStartTime < CONFIG.WALK_STUCK_TIMEOUT then
		return false
	end
	local pos = getInteractionPos(task.workplace)
	if pos and task.worker.PrimaryPart then
		task.worker:PivotTo(CFrame.new(pos))
	end
	task.worker:SetAttribute("IsMoving", false)
	task.worker:SetAttribute("TargetPosition", nil)
	WorkerDebug:info(`Worker snapped to approach position of {task.workplace.Name} after stuck timeout`)
	return true
end

-- ============================================
-- WORKER TRANSFORMATION
-- ============================================

local function transformWorker(peasant: Model, jobType: string): Model
	local unitData = GameData.Units[jobType]
	if not unitData then
		WorkerDebug:warn(`No unit data for job type "{jobType}", leaving peasant as-is`)
		return peasant
	end

	peasant:SetAttribute("UnitType", jobType)

	local modelName = unitData.model_name or jobType
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local unitsFolder = assets and assets:FindFirstChild("Units")
	local newModel = unitsFolder and unitsFolder:FindFirstChild(modelName)

	if newModel and newModel:IsA("Model") then
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

		WorkerDebug:info(`Transformed peasant into {jobType}`)
		return clone
	end

	-- No dedicated model — keep the peasant model but tag it with the job type so
	-- production still works (visual only differs).
	WorkerDebug:info(`No model "{modelName}" for {jobType}; keeping peasant model, tagged as {jobType}`)
	return peasant
end

-- ============================================
-- ASSIGNMENT API
-- ============================================

-- How many workers are currently assigned to a building.
function WorkerManager.getAssignedCount(building: Instance): number
	local count = 0
	for _, task in ipairs(WorkerTasks) do
		if task.workplace == building and task.worker and task.worker.Parent then
			count += 1
		end
	end
	return count
end

-- Worker slots for a building (data-driven).
function WorkerManager.getWorkerCapacity(building: Instance): number
	local buildingType = building:GetAttribute("BuildingType")
	local buildingInfo = buildingType and GameData.Buildings[buildingType]
	if not buildingInfo then
		return 0
	end
	return getWorkerCapacity(buildingInfo)
end

function WorkerManager.assignWorkerToBuilding(peasant: Model?, building: Instance?, ownerId: number)
	if not peasant or not building then
		return
	end

	local buildingType = building:GetAttribute("BuildingType")
	local buildingInfo = buildingType and GameData.Buildings[buildingType]

	if not buildingInfo or not buildingInfo.requires_worker then
		return
	end

	-- FIELD FIX: data uses worker_job_type; the old code read worker_type and so
	-- every worker silently defaulted to "Worker".
	local jobType = buildingInfo.worker_job_type or buildingInfo.worker_type or "Peasant"
	local gatherer = isGathererBuilding(buildingInfo)

	WorkerDebug:info(`Assigning peasant to {buildingType} as {jobType} (gatherer={gatherer})`)

	IdlePeasantManager.removeIdlePeasant(peasant)

	local task: WorkerTask = {
		worker = peasant,
		workplace = building,
		workplaceType = buildingType,
		resourceType = buildingInfo.produces_resource,
		jobType = jobType,
		isGatherer = gatherer,
		state = "WalkingToEntrance",
		resourcesCarrying = 0,
		targetNode = nil,
		ownerId = ownerId,
		hasTransformed = false,
		atStation = false,
		walkStartTime = tick(),
		fallbackProductionTime = tick(),
	}

	table.insert(WorkerTasks, task)
	peasant:SetAttribute("IsWorking", true)
	peasant:SetAttribute("AssignedTo", buildingType)
	-- Unique per-building-instance id so the UI can count workers for THIS
	-- building, not every building of the same type.
	peasant:SetAttribute("AssignedBuildingId", building.Name)
	peasant:SetAttribute("WorkerState", "Walking")
	peasant:SetAttribute("ResourceType", buildingInfo.produces_resource)
end

-- Claim the nearest idle peasant for a building (used by auto-assign on
-- placement and by manual "add worker"). Respects worker_slots. Returns true if
-- a worker was assigned.
function WorkerManager.assignNearestIdlePeasant(building: Instance, ownerId: number): boolean
	local buildingType = building:GetAttribute("BuildingType")
	local buildingInfo = buildingType and GameData.Buildings[buildingType]
	if not buildingInfo or not buildingInfo.requires_worker then
		return false
	end

	if WorkerManager.getAssignedCount(building) >= getWorkerCapacity(buildingInfo) then
		WorkerDebug:info(`{buildingType} is already fully staffed`)
		return false
	end

	local approach = getInteractionPos(building)
	if not approach then
		return false
	end

	local idlePeasants = IdlePeasantManager.getIdlePeasantsForOwner(ownerId)
	local nearest: Model? = nil
	local nearestDist = math.huge
	for _, unit in ipairs(idlePeasants) do
		if unit and unit.Parent and unit.PrimaryPart and isAssignableCivilian(unit) then
			local d = (unit.PrimaryPart.Position - approach).Magnitude
			if d < nearestDist then
				nearestDist = d
				nearest = unit
			end
		end
	end

	if not nearest then
		WorkerDebug:info(`No idle peasant available to staff {buildingType}`)
		return false
	end

	WorkerManager.assignWorkerToBuilding(nearest, building, ownerId)
	return true
end

-- Pull up to `count` workers off a building and return them to idle behaviour.
-- Returns the number actually released.
function WorkerManager.unassignWorker(building: Instance, count: number?): number
	local toRemove = count or 1
	local released = 0

	for i = #WorkerTasks, 1, -1 do
		if released >= toRemove then
			break
		end
		local task = WorkerTasks[i]
		if task.workplace == building then
			local worker = task.worker
			table.remove(WorkerTasks, i)
			released += 1

			if worker and worker.Parent then
				worker:SetAttribute("IsWorking", false)
				worker:SetAttribute("AssignedTo", nil)
				worker:SetAttribute("AssignedBuildingId", nil)
				worker:SetAttribute("WorkerState", nil)
				worker:SetAttribute("ResourcesCarrying", 0)
				worker:SetAttribute("IsMoving", false)
				worker:SetAttribute("TargetPosition", nil)
				-- Un-hide in case it was teleported inside a building.
				for _, part in ipairs(worker:GetDescendants()) do
					if part:IsA("BasePart") then
						part.Transparency = 0
						part.CanCollide = false
					end
				end
				IdlePeasantManager.addIdlePeasant(worker, task.ownerId)
			end
		end
	end

	WorkerDebug:info(`Released {released} worker(s) from {building.Name}`)
	return released
end

-- ============================================
-- WORKER UPDATE LOOP (movement + gather states)
-- ============================================

local function findNearestNode(worker: Model, resourceType: string): Model?
	if not worker.PrimaryPart then
		return nil
	end
	-- Prefer the manager's index; fall back to a workspace scan.
	local node = ResourceNodeManager.findNearestNode(worker.PrimaryPart.Position, resourceType)
	if node then
		return (node :: any).model or (node :: any)
	end

	local nodesFolder = Workspace:FindFirstChild("ResourceNodes")
	if not nodesFolder then
		return nil
	end
	local nearest: Model? = nil
	local nearestDist = math.huge
	for _, candidate in ipairs(nodesFolder:GetChildren()) do
		if candidate:IsA("Model") and candidate.PrimaryPart and candidate:GetAttribute("ResourceType") == resourceType then
			local d = (candidate.PrimaryPart.Position - worker.PrimaryPart.Position).Magnitude
			if d < nearestDist then
				nearestDist = d
				nearest = candidate
			end
		end
	end
	return nearest
end

local function updateWorkerTasks(_dt: number)
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
		local carryCapacity = (unitInfo and unitInfo.carry_capacity) or 10

		-- ── WALKING TO ENTRANCE ────────────────────────────────────────────
		if task.state == "WalkingToEntrance" then
			local arrived = pathfindToBuilding(task.worker, task.workplace, 3) or snapIfStuck(task)

			if arrived then
				if not task.hasTransformed then
					task.worker = transformWorker(task.worker, task.jobType)
					task.hasTransformed = true
					if not task.worker or not task.worker.Parent then
						table.remove(WorkerTasks, i)
						continue
					end
				end

				task.worker:SetAttribute("TargetPosition", nil)
				task.worker:SetAttribute("IsMoving", false)

				-- Optional: hide the worker inside the building if authored.
				if WorkerPointSystem.hasPoint(task.workplace :: any, "TeleportIntoBuilding" :: any) then
					local teleportPoint =
						WorkerPointSystem.getPointPosition(task.workplace :: any, "TeleportIntoBuilding" :: any)
					if teleportPoint and task.worker.PrimaryPart then
						task.worker:PivotTo(CFrame.new(teleportPoint))
						for _, part in ipairs(task.worker:GetDescendants()) do
							if part:IsA("BasePart") then
								part.Transparency = 1
								part.CanCollide = false
							end
						end
					end
				end

				task.state = "Working"
				task.walkStartTime = tick()
			end

		-- ── WORKING ────────────────────────────────────────────────────────
		elseif task.state == "Working" then
			if task.isGatherer then
				-- Active gatherer: walk out to a resource node.
				local node = findNearestNode(task.worker, task.resourceType or "Wood")
				if node then
					task.targetNode = node
					task.state = "GatheringResources"
					task.walkStartTime = tick()
					task.atStation = false
					task.worker:SetAttribute("WorkerState", "Gathering")
				else
					-- No nodes on this map — fall back to passive output so the
					-- building still functions. Stay at the building.
					pathfindToBuilding(task.worker, task.workplace, 3)
					task.worker:SetAttribute("WorkerState", "Working")
					local interval = getProductionInterval(buildingInfo)
					if tick() - task.fallbackProductionTime >= interval then
						task.fallbackProductionTime = tick()
						local amount = math.floor(getProductionOutput(buildingInfo) * getModifier(task.ownerId))
						if amount > 0 and task.resourceType then
							BuildingManager.addToStorage(task.workplace, task.resourceType, amount)
						end
					end
				end
			else
				-- Passive operator: reach the building, then flag presence so the
				-- per-building production pass counts this worker.
				local atStation = pathfindToBuilding(task.worker, task.workplace, 3) or snapIfStuck(task)
				task.atStation = atStation
				task.worker:SetAttribute("WorkerState", atStation and "Working" or "Walking")
			end

		-- ── GATHERING RESOURCES (from the world) ───────────────────────────
		elseif task.state == "GatheringResources" then
			local node = task.targetNode
			if node and node.Parent and node.PrimaryPart then
				local arrived = pathfindToPosition(task.worker, node.PrimaryPart.Position, CONFIG.GATHER_ARRIVAL)
				if arrived then
					local want = math.min(carryCapacity - task.resourcesCarrying, math.max(1, getProductionOutput(buildingInfo)))
					local gathered = ResourceNodeManager.gatherFromInstance(node, want)
					if gathered <= 0 then
						task.targetNode = nil
						task.state = "Working"
						continue
					end
					task.resourcesCarrying += gathered
					task.worker:SetAttribute("ResourcesCarrying", task.resourcesCarrying)

					if task.resourcesCarrying >= carryCapacity then
						task.state = "ReturningToDropoff"
						task.targetNode = nil
						task.walkStartTime = tick()
						task.worker:SetAttribute("WorkerState", "Returning")
					else
						task.targetNode = nil
						task.state = "Working"
					end
				end
			else
				task.targetNode = nil
				task.state = "Working"
			end

		-- ── RETURNING TO DROPOFF ───────────────────────────────────────────
		elseif task.state == "ReturningToDropoff" then
			local arrived = pathfindToBuilding(task.worker, task.workplace, 3) or snapIfStuck(task)

			if arrived and task.resourceType then
				-- Deposit into the building — the stored count rises on return.
				local modifier = getModifier(task.ownerId)
				local depositAmount = math.floor(task.resourcesCarrying * modifier)
				if depositAmount > 0 then
					BuildingManager.addToStorage(task.workplace, task.resourceType, depositAmount)
				end
				task.resourcesCarrying = 0
				task.worker:SetAttribute("ResourcesCarrying", 0)
				task.state = "Working"
				task.walkStartTime = tick()
			end
		end
	end
end

-- ============================================
-- PASSIVE PRODUCTION (per building)
-- ============================================

-- Count staffed passive workers per building this tick.
local function countPassiveStaff(): { [Instance]: number }
	local staff: { [Instance]: number } = {}
	for _, task in ipairs(WorkerTasks) do
		if not task.isGatherer and task.atStation and task.hasTransformed and task.worker and task.worker.Parent then
			staff[task.workplace] = (staff[task.workplace] or 0) + 1
		end
	end
	return staff
end

local function updateProductionBuildings(_dt: number)
	local staff = countPassiveStaff()

	for building, workerCount in pairs(staff) do
		if not building.Parent then
			continue
		end
		local buildingType = building:GetAttribute("BuildingType")
		local buildingInfo = buildingType and GameData.Buildings[buildingType]
		if not buildingInfo or not buildingInfo.produces_resource then
			continue
		end

		local state = BuildingProduction[building]
		if not state then
			state = {
				building = building,
				buildingType = buildingType,
				lastProductionTime = tick(),
			}
			BuildingProduction[building] = state
		end

		local interval = getProductionInterval(buildingInfo)
		if tick() - state.lastProductionTime < interval then
			continue
		end

		-- Production-chain buildings must have inputs available.
		if BuildingTypeHelper.isProductionChain(buildingType) then
			if not ProductionChainManager.canProduce(building) then
				continue
			end
			ProductionChainManager.consumeInputs(building)
		end

		state.lastProductionTime = tick()

		local ownerId = building:GetAttribute("OwnerId")
		local modifier = getModifier(ownerId)
		local slots = getWorkerCapacity(buildingInfo)
		local effectiveWorkers = math.min(workerCount, slots)
		local amount = math.floor(getProductionOutput(buildingInfo) * effectiveWorkers * modifier)

		if amount > 0 then
			BuildingManager.addToStorage(building, buildingInfo.produces_resource, amount)
			WorkerDebug:info(
				`{buildingType} produced {amount} {buildingInfo.produces_resource} ({effectiveWorkers} worker(s), x{modifier})`
			)
		end
	end

	-- Clean up production state for buildings that are gone.
	for building in pairs(BuildingProduction) do
		if not building.Parent then
			BuildingProduction[building] = nil
		end
	end
end

-- ============================================
-- HAULER SYSTEM
-- ============================================

-- Find a storage building that can RECEIVE a resource (for output hauling).
local function findStorageBuildingForResource(resourceType: string, ownerId: number): Instance?
	local BuildingsFolder = Workspace:FindFirstChild("Buildings")
	if not BuildingsFolder then
		return nil
	end

	local bestStorage: Instance? = nil
	local bestSpaceAvailable = 0

	for _, building in ipairs(BuildingsFolder:GetChildren()) do
		if building:IsA("Model") then
			local buildingType = building:GetAttribute("BuildingType")
			local buildingOwnerId = building:GetAttribute("OwnerId")
			local buildingInfo = buildingType and GameData.Buildings[buildingType]

			if
				buildingInfo
				and buildingOwnerId == ownerId
				and buildingInfo.storage_capacity
				and buildingInfo.storage_capacity[resourceType]
				-- Don't haul a producer's output back into itself.
				and buildingInfo.produces_resource ~= resourceType
			then
				local currentAmount = BuildingManager.getStorageAmount(building, resourceType)
				local spaceAvailable = buildingInfo.storage_capacity[resourceType] - currentAmount
				if spaceAvailable > bestSpaceAvailable then
					bestStorage = building
					bestSpaceAvailable = spaceAvailable
				end
			end
		end
	end

	return bestStorage
end

-- Find a storage building that HAS a resource in stock (for input supply).
local function findStorageWithResource(resourceType: string, ownerId: number, minAmount: number): Instance?
	local BuildingsFolder = Workspace:FindFirstChild("Buildings")
	if not BuildingsFolder then
		return nil
	end

	for _, building in ipairs(BuildingsFolder:GetChildren()) do
		if building:IsA("Model") then
			local buildingType = building:GetAttribute("BuildingType")
			local buildingOwnerId = building:GetAttribute("OwnerId")
			local buildingInfo = buildingType and GameData.Buildings[buildingType]
			-- Only pull from dedicated storage / the Keep, never from another
			-- producer that needs its own stock.
			if
				buildingInfo
				and buildingOwnerId == ownerId
				and buildingInfo.storage_capacity
				and buildingInfo.storage_capacity[resourceType]
				and not buildingInfo.requires_worker
				and BuildingManager.getStorageAmount(building, resourceType) >= minAmount
			then
				return building
			end
		end
	end

	return nil
end

function WorkerManager.createHaulerTask(
	hauler: Model,
	sourceBuilding: Instance,
	resourceType: string,
	ownerId: number,
	role: ("Output" | "Supply")?
)
	IdlePeasantManager.removeIdlePeasant(hauler)

	local task: HaulerTask = {
		hauler = hauler,
		role = role or "Output",
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
	HaulerDebug:info(`Created {task.role} hauler task for {hauler.Name} (owner {ownerId})`)
end

local function returnHaulerToIdle(task: HaulerTask, index: number)
	task.hauler:SetAttribute("IsHauling", false)
	local ownerId = task.ownerId or task.hauler:GetAttribute("OwnerId")
	if ownerId then
		IdlePeasantManager.addIdlePeasant(task.hauler, ownerId)
	end
	table.remove(HaulerTasks, index)
end

local function updateHaulerTasks(_dt: number)
	for i = #HaulerTasks, 1, -1 do
		local task = HaulerTasks[i]

		if not task.hauler or not task.hauler.Parent then
			table.remove(HaulerTasks, i)
			continue
		end

		if task.state == "WalkingToPickup" then
			if task.sourceBuilding and task.sourceBuilding.Parent and task.resourceType then
				local pickupPos = getInteractionPos(task.sourceBuilding)
				if not pickupPos then
					returnHaulerToIdle(task, i)
					continue
				end

				if pathfindToPosition(task.hauler, pickupPos, 3) then
					local actualPickup = BuildingManager.takeFromStorage(
						task.sourceBuilding,
						task.resourceType,
						CONFIG.HAULER_PICKUP_AMOUNT
					)

					if actualPickup > 0 then
						task.resourcesCarrying = actualPickup
						task.hauler:SetAttribute("ResourcesCarrying", actualPickup)

						-- Supply runs already know their destination (the processor).
						-- Output runs look up a storage building now.
						if task.role ~= "Supply" then
							task.targetStorage = findStorageBuildingForResource(task.resourceType, task.ownerId)
						end

						if task.targetStorage and task.targetStorage.Parent then
							task.state = "WalkingToStorage"
						else
							-- Nowhere to put it — give it back and stand down.
							BuildingManager.addToStorage(task.sourceBuilding, task.resourceType, task.resourcesCarrying)
							task.resourcesCarrying = 0
							task.hauler:SetAttribute("ResourcesCarrying", 0)
							returnHaulerToIdle(task, i)
						end
					else
						returnHaulerToIdle(task, i)
					end
				end
			else
				returnHaulerToIdle(task, i)
			end

		elseif task.state == "WalkingToStorage" then
			if task.targetStorage and task.targetStorage.Parent and task.resourceType then
				local entrancePos = getInteractionPos(task.targetStorage)
				if not entrancePos then
					returnHaulerToIdle(task, i)
					continue
				end

				if pathfindToPosition(task.hauler, entrancePos, 3) then
					task.storageEntrancePos = entrancePos
					for _, part in ipairs(task.hauler:GetDescendants()) do
						if part:IsA("BasePart") then
							part.Transparency = 1
						end
					end
					task.unloadStartTime = tick()
					task.state = "UnloadingInside"
				end
			else
				returnHaulerToIdle(task, i)
			end

		elseif task.state == "UnloadingInside" then
			if task.targetStorage and task.resourceType and task.unloadStartTime then
				if tick() - task.unloadStartTime >= CONFIG.HAULER_UNLOAD_SECONDS then
					BuildingManager.addToStorage(task.targetStorage, task.resourceType, task.resourcesCarrying)
					task.resourcesCarrying = 0
					task.hauler:SetAttribute("ResourcesCarrying", 0)

					if task.storageEntrancePos and task.hauler.PrimaryPart then
						task.hauler:PivotTo(CFrame.new(task.storageEntrancePos))
					end
					for _, part in ipairs(task.hauler:GetDescendants()) do
						if part:IsA("BasePart") then
							part.Transparency = 0
						end
					end

					returnHaulerToIdle(task, i)
				end
			else
				returnHaulerToIdle(task, i)
			end
		end
	end
end

-- Is this unit already committed to a worker or hauler task?
local function isUnitBusy(unit: Model): boolean
	for _, t in ipairs(WorkerTasks) do
		if t.worker == unit then
			return true
		end
	end
	for _, t in ipairs(HaulerTasks) do
		if t.hauler == unit then
			return true
		end
	end
	return false
end

-- Assign idle peasants to relay resources: producers' output → storage, and
-- (new) storage → starving processors' inputs.
local function assignHaulersToBuildings()
	local BuildingsFolder = Workspace:FindFirstChild("Buildings")
	if not BuildingsFolder then
		return
	end

	type Job = { building: Instance, resourceType: string, ownerId: number, role: "Output" | "Supply" }
	local jobs: { Job } = {}

	for _, building in ipairs(BuildingsFolder:GetChildren()) do
		if not building:IsA("Model") then
			continue
		end
		local buildingType = building:GetAttribute("BuildingType")
		local buildingInfo = buildingType and GameData.Buildings[buildingType]
		local ownerId = building:GetAttribute("OwnerId")
		if not buildingInfo or not ownerId then
			continue
		end

		-- OUTPUT: producer has stock to move to storage.
		if buildingInfo.produces_resource and buildingInfo.storage_capacity then
			local resourceType = buildingInfo.produces_resource
			local currentAmount = BuildingManager.getStorageAmount(building, resourceType)
			if currentAmount >= CONFIG.HAULER_OUTPUT_THRESHOLD then
				local alreadyAssigned = false
				for _, t in ipairs(HaulerTasks) do
					if t.sourceBuilding == building and t.role == "Output" and t.state ~= "Idle" then
						alreadyAssigned = true
						break
					end
				end
				if not alreadyAssigned then
					table.insert(
						jobs,
						{ building = building, resourceType = resourceType, ownerId = ownerId, role = "Output" }
					)
				end
			end
		end

		-- SUPPLY: production-chain building is short of its input.
		if buildingType and BuildingTypeHelper.isProductionChain(buildingType) and buildingInfo.consumes_resource then
			local input = buildingInfo.consumes_resource
			local have = BuildingManager.getStorageAmount(building, input)
			local need = (buildingInfo.consumption_rate or 1) * 3
			if have < need then
				local alreadySupplying = false
				for _, t in ipairs(HaulerTasks) do
					if t.sourceBuilding ~= building and t.targetStorage == building and t.role == "Supply" then
						alreadySupplying = true
						break
					end
				end
				-- Only queue a supply run if a storage building actually has the input.
				if not alreadySupplying and findStorageWithResource(input, ownerId, CONFIG.HAULER_SUPPLY_MIN) then
					table.insert(jobs, { building = building, resourceType = input, ownerId = ownerId, role = "Supply" })
				end
			end
		end
	end

	for _, job in ipairs(jobs) do
		local idlePeasants = IdlePeasantManager.getIdlePeasantsForOwner(job.ownerId)
		for _, unit in ipairs(idlePeasants) do
			if unit and unit.Parent and not isUnitBusy(unit) then
				if job.role == "Supply" then
					-- Supply run: pick up from a storage building, deliver to the processor.
					local source = findStorageWithResource(job.resourceType, job.ownerId, CONFIG.HAULER_SUPPLY_MIN)
					if source then
						WorkerManager.createHaulerTask(unit, source, job.resourceType, job.ownerId, "Supply")
						-- Redirect the delivery target to the processor.
						HaulerTasks[#HaulerTasks].targetStorage = job.building
					end
				else
					WorkerManager.createHaulerTask(unit, job.building, job.resourceType, job.ownerId, "Output")
				end
				break
			end
		end
	end
end

-- ============================================
-- MAIN UPDATE
-- ============================================

function WorkerManager.update(dt: number)
	updateWorkerTasks(dt)
	updateProductionBuildings(dt)
	updateHaulerTasks(dt)
	IdlePeasantManager.update(dt)

	local currentTime = tick()
	if currentTime - lastHaulerAssignmentTime >= CONFIG.HAULER_ASSIGNMENT_INTERVAL then
		assignHaulersToBuildings()
		lastHaulerAssignmentTime = currentTime
	end
end

function WorkerManager.startLoop()
	local RunService = game:GetService("RunService")
	RunService.Heartbeat:Connect(function(dt)
		WorkerManager.update(dt)
	end)
	WorkerDebug:info("WorkerManager update loop started")
end

-- Called by HappinessManager and RevoltManager to scale worker output.
function WorkerManager.setProductionModifier(player: Player, modifier: number)
	productionModifiers[player.UserId] = math.clamp(modifier, 0, 1)
	WorkerDebug:info(`Production modifier for owner {player.UserId} set to {productionModifiers[player.UserId]}`)
end

return WorkerManager
