--!strict
-- WorkerService: the single worker engine.
--
-- Replaces three competing state machines (WorkerTask.state, HaulerTask.state,
-- IdlePeasantManager.IdleBehavior) with one. Every unit this service manages
-- has exactly one WorkerRecord, keyed by its own Model instance in `Records` --
-- that keying is what makes "a unit in two task tables at once" structurally
-- impossible: there is only one table, and a Lua table can only hold one
-- value per key.
--
--   Idle ──claim──> Travelling ──arrive──> Working ───┐
--     ▲                   │                    │      │
--     │                   │                 (carrying)│
--     │                   │                    ▼      │
--     └──── release ──────┴──────────── Hauling ──────┘
--
-- `Idle` is a real state here, not a separate manager -- that removes the
-- historical limbo case where `releaseFromWork` cleared IsWorking but never
-- set IsIdle. Every attribute write funnels through `syncAttributes`, which
-- derives IsIdle/IsWorking/IsHauling/AssignedTo/etc. purely from the record,
-- so those four flags can never again disagree with each other.
--
-- Behaviour is data-driven off WorkerRoles.getBehaviour(role): Gatherer,
-- Producer, Hauler, Server. The engine dispatches on `record.behaviour`
-- (one of those four) and `record.state` (one of the four WorkerStates) --
-- never on a trade/job-type string. Adding a 25th trade to WorkerRoles is
-- zero lines here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local WorkerRoles = require(ReplicatedStorage.Shared.GameData.WorkerRoles)
local BuildingSpec = require(ReplicatedStorage.Shared.GameData.BuildingSpec)
local UnitAnimations = require(ReplicatedStorage.Shared.GameData.UnitAnimationsData)
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)

local Managers = script.Parent.Parent.Managers
local BuildingManager = require(Managers.BuildingManager)
local PlayerManager = require(Managers.PlayerManager)
local UnitManager = require(Managers.UnitManager)
local ResourceNodeManager = require(Managers.ResourceNodeManager)

local BuildingIndex = require(script.Parent.BuildingIndex)
local PathfindingIntegration = require(script.Parent.PathfindingIntegration)
local WorkerPointSystem = require(script.Parent.WorkerPointSystem)
local SpawnPointSystem = require(script.Parent.SpawnPointSystem)

local WorkerService = {}

local WorkerDebug = DebugManager.createChannel("Worker", false)
local HaulerDebug = DebugManager.createChannel("Hauler", false)
local IdleDebug = DebugManager.createChannel("IdlePeasant", false)

-- ============================================================
-- TYPES
-- ============================================================

export type WorkerState = "Idle" | "Travelling" | "Working" | "Hauling"

type IdlePresentation = {
	behaviorType: "Campfire" | "Roaming",
	slotIndex: number?,
	campfirePosition: Vector3?,
	campfireCenter: Vector3?,
	seated: boolean,
	arriveBy: number?,
	roamCenter: Vector3?,
	roamRadius: number,
	roamMinRadius: number?,
	nextRoamTime: number,
	targetPosition: Vector3?,
}

export type WorkerRecord = {
	unit: Model,
	ownerId: number?,
	role: string,
	behaviour: WorkerRoles.Behaviour,
	state: WorkerState,

	-- Gatherer / Producer / Server: the employer. Never set for a Hauler.
	building: Instance?,
	buildingType: string?,
	hasTransformed: boolean,
	walkStartTime: number,
	atStation: boolean,

	-- Gatherer
	targetNode: Model?,
	resourcesCarrying: number,
	resourceType: string?,
	cycleStart: number,

	-- Hauler
	haulRole: ("Output" | "Supply")?,
	haulPhase: ("ToPickup" | "ToStorage" | "Unloading")?,
	sourceBuilding: Instance?,
	targetStorage: Instance?,
	unloadStart: number?,

	-- Idle-only visual decoration. nil = no loitering (e.g. mid manual order).
	idle: IdlePresentation?,
}

export type TransitionContext = {
	ownerId: number?,
	building: Instance?,
	buildingType: string?,
	role: string?,
	haulRole: ("Output" | "Supply")?,
	sourceBuilding: Instance?,
	targetStorage: Instance?,
	resourceType: string?,
	presentation: boolean?,
}

-- ============================================================
-- TUNING
-- ============================================================

local CONFIG = {
	MIN_ARRIVAL = 6,
	GIVEUP_RADIUS = 12,
	WALK_STUCK_TIMEOUT = 8,
	GATHER_ARRIVAL = 6,
	HAULER_ASSIGNMENT_INTERVAL = 5,
	HAULER_PICKUP_AMOUNT = 15,
	HAULER_OUTPUT_THRESHOLD = 5,
	HAULER_SUPPLY_MIN = 5,
	HAULER_UNLOAD_SECONDS = 3,
	-- Workers are ticked round-robin, this many per Heartbeat, instead of every
	-- worker every frame -- see WorkerService.update for why that's safe.
	SCHEDULE_BUDGET = 40,
}

local ROAM_RADIUS = 30
local CAMPFIRE_POSITIONS_COUNT = 6
local CAMPFIRE_RADIUS = 8
local CAMPFIRE_MODEL_RADIUS = 7
local CAMPFIRE_ARRIVAL_TIMEOUT = 30

-- ============================================================
-- STATE
-- ============================================================

-- THE single source of truth. One Model can hold at most one key here, which
-- is what makes double-assignment structurally impossible rather than merely
-- avoided by convention.
local Records: { [Model]: WorkerRecord } = {}

-- The labour pool: idle records currently decorated with presentation
-- (campfire/roam), grouped per owner so assignment/staffing can find them.
-- Keyed by RECORD, not Model -- idle units never transform, so this never
-- needs rekeying the way the roster does.
local IdleByOwner: { [number]: { [WorkerRecord]: true } } = {}

-- Round-robin roster of every registered worker, for the staggered scheduler.
local Roster: { Model } = {}
local RosterIndex: { [Model]: number } = {}
local cursor = 1
local scheduleBudget = CONFIG.SCHEDULE_BUDGET

local productionModifiers: { [number]: number } = {}
local lastHaulerAssignmentTime = 0

local function getModifier(ownerId: number?): number
	if not ownerId then
		return 1.0
	end
	return productionModifiers[ownerId] or 1.0
end

local function rosterAdd(unit: Model)
	if RosterIndex[unit] then
		return
	end
	table.insert(Roster, unit)
	RosterIndex[unit] = #Roster
end

local function rosterRemove(unit: Model)
	local idx = RosterIndex[unit]
	if not idx then
		return
	end
	local lastIdx = #Roster
	local lastUnit = Roster[lastIdx]
	Roster[idx] = lastUnit
	RosterIndex[lastUnit] = idx
	Roster[lastIdx] = nil
	RosterIndex[unit] = nil
	if cursor > #Roster then
		cursor = 1
	end
end

-- A model swap (peasant rig <-> trade rig) changes the Model instance that
-- keys `Records`/`Roster`. Every place that swaps a model MUST call this so
-- the index and the roster stay in step with the new instance.
local function rekey(record: WorkerRecord, oldUnit: Model, newUnit: Model)
	Records[oldUnit] = nil
	Records[newUnit] = record
	record.unit = newUnit
	local idx = RosterIndex[oldUnit]
	if idx then
		Roster[idx] = newUnit
		RosterIndex[newUnit] = idx
		RosterIndex[oldUnit] = nil
	end
end

-- ============================================================
-- MOVEMENT (unified arrival, ported from the old WorkerManager)
-- ============================================================

local function horizontalDistance(a: Vector3, b: Vector3): number
	local d = a - b
	return Vector3.new(d.X, 0, d.Z).Magnitude
end

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

	if not unit:GetAttribute("IsMoving") and distance2D <= CONFIG.GIVEUP_RADIUS then
		unit:SetAttribute("TargetPosition", nil)
		return true
	end

	local currentTarget = unit:GetAttribute("TargetPosition")
	if typeof(currentTarget) ~= "Vector3" or (currentTarget - targetPos).Magnitude > 1 then
		unit:SetAttribute("TargetPosition", targetPos)
		unit:SetAttribute("IsMoving", true)
		unit:SetAttribute("PathfindingFailed", nil)
	end
	return false
end

local function getInteractionPos(building: Instance): Vector3?
	local cached = building:GetAttribute("ApproachPosition")
	if typeof(cached) == "Vector3" then
		return cached
	end

	if building:IsA("Model") then
		local pos = PathfindingIntegration.getApproachPosition(building)
		if pos then
			building:SetAttribute("ApproachPosition", pos)
			return pos
		end
	end

	local pointPos = WorkerPointSystem.getPointPosition(building :: any, "BuildingEntrance" :: any)
	if pointPos then
		return pointPos
	end
	return building:IsA("Model") and (building :: Model):GetPivot().Position or nil
end

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

-- Last-resort guarantee: a worker stuck walking to its building for too long
-- gets snapped there so the state machine always makes progress.
local function snapIfStuck(record: WorkerRecord): boolean
	if tick() - record.walkStartTime < CONFIG.WALK_STUCK_TIMEOUT then
		return false
	end
	local building = record.building
	if not building then
		return false
	end
	local pos = getInteractionPos(building)
	if pos and record.unit.PrimaryPart then
		record.unit:PivotTo(CFrame.new(pos))
	end
	record.unit:SetAttribute("IsMoving", false)
	record.unit:SetAttribute("TargetPosition", nil)
	WorkerDebug:info(`Worker snapped to approach position of {building.Name} after stuck timeout`)
	return true
end

-- ============================================================
-- MODEL TRANSFORM (peasant rig <-> trade rig)
-- ============================================================

-- Attributes that belong to the MODEL's skeleton/pose, not the unit, and must
-- come from the new template rather than riding along across a swap -- see
-- the historical note in project memory: copying AnimSet across a rig swap
-- drives the new skeleton with the old rig's clips and animates nothing.
local MODEL_OWNED: { [string]: boolean } = {
	AnimSet = true,
	SkinnedRig = true,
	Pose = true,
	Gait = true,
	SitJointDrop = true,
}

local function setUnitDisplayName(model: Model, displayName: string)
	local hum = model:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.DisplayName = (displayName:gsub("_", " "))
	end
end

local function makeWalkable(model: Model)
	if not model.PrimaryPart then
		local hrp = model:FindFirstChild("HumanoidRootPart")
		if hrp and hrp:IsA("BasePart") then
			model.PrimaryPart = hrp
		end
	end
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.CanCollide = false
		end
	end
end

-- Swap a unit's MODEL to the rig for `role`. Reuses UnitManager.getUnitModel
-- -- the same resolver spawning uses, so Assets/Units/<rigSet> being a FOLDER
-- of variants just works -- instead of writing a second copy of that scan.
-- Returns the NEW model; callers MUST rekey off the return value.
local function transformToRole(unit: Model, role: string): Model
	local data = WorkerRoles.getOrDefault(role)
	local template = UnitManager.getUnitModel(role, { model_name = data.rigSet })
	unit:SetAttribute("UnitType", role)

	if not template then
		setUnitDisplayName(unit, data.displayName)
		WorkerDebug:info(`No rig for "{role}"; kept current model, relabelled`)
		return unit
	end

	local pivot = unit:GetPivot()
	local attributes = unit:GetAttributes()
	local clone = template:Clone()
	clone.Name = unit.Name
	makeWalkable(clone)
	clone:PivotTo(pivot)
	for key, value in attributes do
		if not MODEL_OWNED[key] and key:sub(1, 4) ~= "RBX_" then
			clone:SetAttribute(key, value)
		end
	end
	clone.Parent = unit.Parent
	unit:Destroy()

	setUnitDisplayName(clone, data.displayName)
	WorkerDebug:info(`Transformed unit to {role}`)
	return clone
end

-- ============================================================
-- IDLE PRESENTATION (ported from IdlePeasantManager: campfire + roaming)
--
-- This decorates the Idle state for how the kingdom LOOKS -- it never
-- decides whether a unit IS idle. `record.state == "Idle"` is the only
-- authority on that; presentation just adds the sitting/wandering flavour on
-- top, and can be detached (suppressPresentation) without touching state, so
-- it can never again become a second, disagreeing authority.
-- ============================================================

local function findPlayerKeep(ownerId: number): Model?
	for _, player in Players:GetPlayers() do
		if player.UserId == ownerId then
			local playerData = PlayerManager.get(player)
			if playerData and playerData.Keep then
				return playerData.Keep :: Model
			end
			break
		end
	end
	return nil
end

local function findCampfire(keep: Model): Vector3?
	local fire = keep:FindFirstChild("Campfire", true)
	if not fire then
		return nil
	end
	if fire:IsA("BasePart") then
		return fire.Position
	end
	if fire:IsA("Model") then
		local cf = fire:GetBoundingBox()
		return cf.Position
	end
	return nil
end

local function getCampfirePositions(center: Vector3, count: number, radius: number): { Vector3 }
	local positions = {}
	for i = 1, count do
		local angle = (math.pi * 2 * (i - 1)) / count
		table.insert(positions, center + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius))
	end
	return positions
end

local function findRootJoint(unit: Model): Motor6D?
	local root = unit.PrimaryPart
	if not root then
		return nil
	end
	local joint = root:FindFirstChild("RootJoint")
	return (joint and joint:IsA("Motor6D")) and joint or nil
end

-- Sit down / stand up. See IdlePeasantManager's original header (project
-- memory: "custom rig animation") for why this drives the RootJoint C0
-- instead of Humanoid.HipHeight -- HipHeight walks the only collider these
-- skinned rigs have down toward the floor and several rigs never settle.
local function setSeated(unit: Model, seated: boolean)
	local joint = findRootJoint(unit)

	if seated then
		unit:SetAttribute(UnitAnimations.POSE_ATTRIBUTE, "sit")
		if joint and unit:GetAttribute("SitJointDrop") == nil then
			local set = UnitAnimations.getSet(unit:GetAttribute("AnimSet") :: string?)
			local drop = set and set.sitHipDrop or 0
			if drop > 0 then
				joint.C0 = joint.C0 * CFrame.new(0, -drop, 0)
				unit:SetAttribute("SitJointDrop", drop)
			end
		end
		return
	end

	unit:SetAttribute(UnitAnimations.POSE_ATTRIBUTE, nil)
	local jointDrop = unit:GetAttribute("SitJointDrop") :: number?
	if jointDrop and joint then
		joint.C0 = joint.C0 * CFrame.new(0, jointDrop, 0)
	end
	unit:SetAttribute("SitJointDrop", nil)
end

local function attachPresentation(record: WorkerRecord)
	local ownerId = record.ownerId
	if not ownerId then
		return
	end
	local keep = findPlayerKeep(ownerId)
	if not keep then
		return
	end

	local spawnPoint = SpawnPointSystem.getSpawnPosition(keep)
		or (keep.PrimaryPart and keep.PrimaryPart.Position)
		or Vector3.new(0, 0, 0)

	local _, keepSize = keep:GetBoundingBox()
	local safeIdleRadius = math.max(keepSize.X, keepSize.Z) / 2 + 10

	local fireCenter = findCampfire(keep)
	local ringCenter = fireCenter or spawnPoint
	local ringRadius = if fireCenter then CAMPFIRE_MODEL_RADIUS else safeIdleRadius
	local campfirePositions = getCampfirePositions(ringCenter, CAMPFIRE_POSITIONS_COUNT, ringRadius)

	local taken: { [number]: boolean } = {}
	local ownerIdle = IdleByOwner[ownerId]
	if ownerIdle then
		for other in ownerIdle do
			if other.idle and other.idle.slotIndex then
				taken[other.idle.slotIndex :: number] = true
			end
		end
	end

	local free: { number } = {}
	for i = 1, #campfirePositions do
		if not taken[i] then
			table.insert(free, i)
		end
	end

	local presentation: IdlePresentation
	if math.random() < 0.6 and #free > 0 then
		local slotIndex = free[math.random(1, #free)]
		presentation = {
			behaviorType = "Campfire",
			slotIndex = slotIndex,
			campfirePosition = campfirePositions[slotIndex],
			campfireCenter = fireCenter,
			seated = false,
			arriveBy = tick() + CAMPFIRE_ARRIVAL_TIMEOUT,
			roamCenter = nil,
			roamRadius = ROAM_RADIUS,
			roamMinRadius = nil,
			nextRoamTime = 0,
			targetPosition = campfirePositions[slotIndex],
		}
	else
		presentation = {
			behaviorType = "Roaming",
			slotIndex = nil,
			campfirePosition = nil,
			campfireCenter = nil,
			seated = false,
			arriveBy = nil,
			roamCenter = spawnPoint,
			roamRadius = ROAM_RADIUS,
			roamMinRadius = safeIdleRadius,
			nextRoamTime = tick() + math.random(2, 5),
			targetPosition = nil,
		}
	end

	record.idle = presentation
	local set = IdleByOwner[ownerId]
	if not set then
		set = {}
		IdleByOwner[ownerId] = set
	end
	set[record] = true
end

-- Detach presentation WITHOUT touching `state`. Safe to call on a record
-- that never had presentation attached in the first place.
local function clearPresentation(record: WorkerRecord)
	if record.idle then
		if record.idle.seated then
			setSeated(record.unit, false)
		end
		record.idle = nil
	end
	local ownerId = record.ownerId
	if ownerId and IdleByOwner[ownerId] then
		IdleByOwner[ownerId][record] = nil
	end
end

local function idlePathfindTo(unit: Model, targetPos: Vector3, threshold: number): boolean
	if not unit.PrimaryPart then
		return false
	end
	local here = unit.PrimaryPart.Position
	local distance2D = (Vector3.new(targetPos.X, 0, targetPos.Z) - Vector3.new(here.X, 0, here.Z)).Magnitude
	if distance2D <= threshold then
		unit:SetAttribute("IsMoving", false)
		unit:SetAttribute("TargetPosition", nil)
		return true
	end
	local currentTarget = unit:GetAttribute("TargetPosition")
	if typeof(currentTarget) ~= "Vector3" or (currentTarget - targetPos).Magnitude > 1 then
		unit:SetAttribute("TargetPosition", targetPos)
		unit:SetAttribute("IsMoving", true)
	end
	return false
end

local function tickPresentation(record: WorkerRecord)
	local presentation = record.idle
	if not presentation then
		return
	end
	local unit = record.unit

	if presentation.behaviorType == "Campfire" then
		if presentation.campfirePosition then
			local arrived = idlePathfindTo(unit, presentation.campfirePosition, 2)

			if not arrived and presentation.arriveBy and tick() > presentation.arriveBy then
				arrived = true
				presentation.arriveBy = nil
				unit:SetAttribute("IsMoving", false)
				unit:SetAttribute("TargetPosition", nil)
				IdleDebug:warn(`{unit.Name} could not reach its campfire slot in time -- sitting where it stands`)
			end

			if arrived and not presentation.seated then
				presentation.seated = true
				presentation.arriveBy = nil
				local root = unit.PrimaryPart
				if root and presentation.campfireCenter then
					local here = root.Position
					local look = Vector3.new(presentation.campfireCenter.X, here.Y, presentation.campfireCenter.Z)
					if (look - here).Magnitude > 0.05 then
						unit:PivotTo(CFrame.lookAt(here, look))
					end
				end
				setSeated(unit, true)
			elseif not arrived and presentation.seated then
				presentation.seated = false
				setSeated(unit, false)
			end
		end
	elseif presentation.behaviorType == "Roaming" then
		if presentation.roamCenter then
			if tick() >= presentation.nextRoamTime then
				local angle = math.random() * math.pi * 2
				local distance = math.random() * presentation.roamRadius
				presentation.targetPosition = presentation.roamCenter
					+ Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
				presentation.nextRoamTime = tick() + math.random(5, 10)
			end
			if presentation.targetPosition then
				if idlePathfindTo(unit, presentation.targetPosition, 3) then
					presentation.nextRoamTime = tick() + math.random(2, 4)
				end
			end
		end
	end
end

-- ============================================================
-- ATTRIBUTE SYNC -- the ONLY place that writes replicated worker attributes
-- ============================================================

local function syncAttributes(record: WorkerRecord)
	local unit = record.unit
	if not unit or not unit.Parent then
		return
	end
	local idle = record.state == "Idle"
	local hauling = record.behaviour == "Hauler" and not idle
	local working = not idle and not hauling

	local buildingId: string? = nil
	if not idle and record.building then
		buildingId = record.building.Name
	end

	unit:SetAttribute("IsIdle", idle)
	unit:SetAttribute("IsWorking", working)
	unit:SetAttribute("IsHauling", hauling)
	unit:SetAttribute("AssignedTo", (not idle) and record.buildingType or nil)
	unit:SetAttribute("AssignedBuildingId", buildingId)
	unit:SetAttribute("ResourceType", record.resourceType)
	unit:SetAttribute("ResourcesCarrying", record.resourcesCarrying)
	unit:SetAttribute("WorkerState", (not idle) and record.state or nil)
	unit:SetAttribute(UnitAnimations.POSE_ATTRIBUTE, (record.state == "Working" and record.atStation) and "work" or nil)
end

-- ============================================================
-- BUILDINGS: worker-count attrs + Destroying-driven cleanup (fixes the
-- worker leak: previously only the UI delete path released workers, so a
-- building destroyed by combat/siege left its worker invisible, non-
-- colliding, flagged not-working, and never returned to the pool)
-- ============================================================

local function getAssignedCount(building: Instance): number
	local count = 0
	for _, record in Records do
		if record.building == building and record.unit and record.unit.Parent then
			count += 1
		end
	end
	return count
end

local function getWorkerCapacity(building: Instance): number
	local buildingType = building:GetAttribute("BuildingType")
	return (buildingType and BuildingSpec.getWorkerSlots(buildingType :: string)) or 0
end

local function syncBuildingWorkerAttrs(building: Instance)
	if not building.Parent then
		return
	end
	local count = getAssignedCount(building)
	building:SetAttribute("WorkerCount", count)
	building:SetAttribute("WorkerSlots", getWorkerCapacity(building))
	-- ConsumptionManager gates food/etc. consumption on HasWorker; nothing
	-- ever set it before (doc: "Building food consumption is dead").
	building:SetAttribute("HasWorker", count > 0)
end

-- Forward-declared: assigned below, used by the Destroying handler.
local unassignWorkersFromBuilding: (building: Instance) -> number

local function releaseWorkersAt(building: Instance)
	unassignWorkersFromBuilding(building)
	-- Haulers mid-route lose their destination too, rather than walking
	-- forever toward a building that no longer exists.
	for _, record in Records do
		if
			record.behaviour == "Hauler"
			and record.state ~= "Idle"
			and (record.sourceBuilding == building or record.targetStorage == building)
		then
			WorkerService.setState(record.unit, "Idle", { ownerId = record.ownerId, presentation = true })
		end
	end
end

local DestroyConns: { [Instance]: RBXScriptConnection } = {}

local function registerBuilding(building: Instance)
	if not building:IsA("Model") then
		return
	end
	BuildingIndex.register(building)
	if DestroyConns[building] then
		return
	end
	local conn: RBXScriptConnection
	conn = building.Destroying:Connect(function()
		conn:Disconnect()
		DestroyConns[building] = nil
		releaseWorkersAt(building)
		BuildingIndex.unregister(building)
	end)
	DestroyConns[building] = conn
end

local function unregisterBuilding(building: Instance)
	local conn = DestroyConns[building]
	if conn then
		conn:Disconnect()
		DestroyConns[building] = nil
	end
	releaseWorkersAt(building)
	BuildingIndex.unregister(building)
end

-- Watch the Buildings folder for the lifetime of the server.
--
-- Requiring BuildingManager above creates Workspace.Buildings as a side effect,
-- so in practice the folder exists by the time we get here. Relying on that is
-- fragile though -- reordering the requires at the top of this file would
-- silently disable every Destroying handler, and the symptom (workers leaking
-- when a building is destroyed) is exactly the bug this service exists to fix.
-- So handle the folder arriving late as well.
local function watchBuildingsFolder(folder: Instance)
	for _, existing in folder:GetChildren() do
		registerBuilding(existing)
	end
	folder.ChildAdded:Connect(registerBuilding)
	folder.ChildRemoved:Connect(unregisterBuilding)
end

do
	local existing = Workspace:FindFirstChild("Buildings")
	if existing then
		watchBuildingsFolder(existing)
	else
		local conn: RBXScriptConnection
		conn = Workspace.ChildAdded:Connect(function(child)
			if child.Name == "Buildings" then
				conn:Disconnect()
				watchBuildingsFolder(child)
			end
		end)
	end
end

-- ============================================================
-- THE TRANSITION FUNCTION
--
-- The only thing allowed to mutate a worker's attributes, its place in the
-- task/idle-pool tables, and its building's headcount attrs. Every other
-- function in this file that changes what a unit is doing calls this.
-- ============================================================

function WorkerService.setState(worker: Model, nextState: WorkerState, ctx: TransitionContext?): Model
	if not worker or not worker.Parent then
		return worker
	end
	local c: TransitionContext = ctx or {}

	local record = Records[worker]
	if not record then
		record = {
			unit = worker,
			ownerId = c.ownerId,
			role = c.role or "Peasant",
			behaviour = WorkerRoles.getBehaviour(c.role or "Peasant"),
			state = "Idle",
			building = nil,
			buildingType = nil,
			hasTransformed = false,
			walkStartTime = tick(),
			atStation = false,
			targetNode = nil,
			resourcesCarrying = 0,
			resourceType = nil,
			cycleStart = tick(),
			haulRole = nil,
			haulPhase = nil,
			sourceBuilding = nil,
			targetStorage = nil,
			unloadStart = nil,
			idle = nil,
		}
		Records[worker] = record
		rosterAdd(worker)
	end

	local prevState = record.state
	local prevBuilding = record.building

	if prevState == "Idle" and nextState ~= "Idle" then
		clearPresentation(record)
	end

	-- Restore visibility whenever a worker stops working.
	--
	-- Buildings that author a "TeleportIntoBuilding" point hide their worker
	-- inside (Transparency = 1, CanCollide = false) on arrival. Only the hauler
	-- unload path ever undid that, so a Producer/Server worker that was
	-- unassigned, manually moved, or whose building was destroyed by siege was
	-- left permanently invisible and non-colliding -- alive, idle, and
	-- unclickable. The old WorkerManager un-hid on both release paths; this puts
	-- that guarantee in the one place every transition already goes through.
	if nextState == "Idle" and prevState ~= "Idle" then
		for _, part in record.unit:GetDescendants() do
			if part:IsA("BasePart") then
				part.Transparency = 0
			end
		end
	end

	if c.ownerId then
		record.ownerId = c.ownerId
	end

	if nextState == "Idle" then
		record.building = nil
		record.buildingType = nil
		record.hasTransformed = false
		record.targetNode = nil
		record.resourcesCarrying = 0
		record.resourceType = nil
		record.haulRole = nil
		record.haulPhase = nil
		record.sourceBuilding = nil
		record.targetStorage = nil
		record.unloadStart = nil
		record.atStation = false
		record.role = "Peasant"
		record.behaviour = WorkerRoles.getBehaviour("Peasant")
	else
		if c.role then
			record.role = c.role
			record.behaviour = WorkerRoles.getBehaviour(c.role)
		end
		if nextState == "Travelling" then
			-- A fresh claim seats the employer/haul context. Internal
			-- re-entries into Working/Hauling (arrival, deposit-then-loop)
			-- never pass these, so they fall through and keep what's there.
			record.building = c.building
			record.buildingType = c.buildingType
				or (c.building and (c.building :: Instance):GetAttribute("BuildingType") :: string?)
			if c.sourceBuilding then
				record.sourceBuilding = c.sourceBuilding
			end
			if c.resourceType then
				record.resourceType = c.resourceType
			end
			if c.haulRole then
				record.haulRole = c.haulRole
			end
		end
		if c.targetStorage ~= nil then
			record.targetStorage = c.targetStorage
		end
		if nextState == "Working" and prevState ~= "Working" then
			record.cycleStart = tick()
		end
	end

	record.state = nextState
	record.walkStartTime = tick()

	if nextState == "Idle" and c.presentation ~= false then
		attachPresentation(record)
	end

	syncAttributes(record)

	if prevBuilding and prevBuilding ~= record.building then
		syncBuildingWorkerAttrs(prevBuilding)
	end
	if record.building then
		syncBuildingWorkerAttrs(record.building)
	end

	return record.unit
end

-- ============================================================
-- BEHAVIOUR: PRODUCER / SERVER
-- Stands at a station and converts work.inputs -> work.outputs on a cycle.
-- Server buildings with no inputs/outputs just stand there -- "provides a
-- non-material effect" until an economy system reads WorkerCount/HasWorker
-- off the building; this engine's job is to make sure a real, visible worker
-- is present, not to invent the popularity/faith math.
-- ============================================================

local function tickProducerCycle(record: WorkerRecord)
	local building = record.building
	if not building or not building.Parent or not record.buildingType then
		return
	end
	local work = BuildingSpec.getWork(record.buildingType)
	if not work then
		return
	end
	if tick() - record.cycleStart < work.cycle then
		return
	end

	for resource, amount in work.inputs do
		if BuildingManager.getStorageAmount(building, resource) < amount then
			-- Starved: don't advance the timer, retry once inputs arrive.
			return
		end
	end
	for resource, amount in work.inputs do
		BuildingManager.takeFromStorage(building, resource, amount)
	end

	local modifier = getModifier(record.ownerId)
	for resource, amount in work.outputs do
		local produced = math.floor(amount * modifier)
		if produced > 0 then
			BuildingManager.addToStorage(building, resource, produced)
		end
	end
	record.cycleStart = tick()
end

-- ============================================================
-- BEHAVIOUR: GATHERER
-- Walks to a world ResourceNode, harvests, carries the load home. Falls back
-- to the same passive cycle as Producer if the map has no matching nodes, so
-- the economy never stalls.
-- ============================================================

local function findResourceNode(position: Vector3, resourceType: string): Model?
	local node = ResourceNodeManager.findNearestNode(position, resourceType)
	if node then
		return (node :: any).Instance
	end
	local nodesFolder = Workspace:FindFirstChild("ResourceNodes")
	if not nodesFolder then
		return nil
	end
	local nearest: Model? = nil
	local nearestDist = math.huge
	for _, candidate in nodesFolder:GetChildren() do
		if candidate:IsA("Model") and candidate.PrimaryPart and candidate:GetAttribute("ResourceType") == resourceType then
			local d = (candidate.PrimaryPart.Position - position).Magnitude
			if d < nearestDist then
				nearestDist = d
				nearest = candidate
			end
		end
	end
	return nearest
end

local function tickGathererWorking(record: WorkerRecord)
	local building = record.building
	local unit = record.unit
	if not building or not building.Parent or not record.buildingType then
		return
	end
	local work = BuildingSpec.getWork(record.buildingType)
	if not work then
		return
	end

	-- `work.gathers` is resolved by BuildingSpec and is deterministic. This used
	-- to be next(work.outputs), whose order Lua does not guarantee.
	if not record.resourceType then
		record.resourceType = work.gathers
	end
	local resourceType = record.resourceType

	if not (record.targetNode and record.targetNode.Parent) then
		record.targetNode = nil
		local primaryPart = unit.PrimaryPart
		if work.gathersFromNodes and resourceType and primaryPart then
			record.targetNode = findResourceNode(primaryPart.Position, resourceType)
		end
	end

	if not record.targetNode then
		-- No matching nodes on this map: fall back to passive output.
		record.atStation = true
		tickProducerCycle(record)
		syncAttributes(record)
		return
	end

	record.atStation = false
	local node = record.targetNode
	local nodePos = node.PrimaryPart and node.PrimaryPart.Position
	if not nodePos then
		record.targetNode = nil
		return
	end

	if pathfindToPosition(unit, nodePos, CONFIG.GATHER_ARRIVAL) then
		local capacity = WorkerRoles.getCarryCapacity(record.role)
		local want = math.max(1, capacity - record.resourcesCarrying)
		local gathered = ResourceNodeManager.gatherFromInstance(node, want)
		record.targetNode = nil
		if gathered > 0 then
			record.resourcesCarrying += gathered
		end
		if record.resourcesCarrying >= capacity then
			WorkerService.setState(unit, "Hauling", {})
		else
			syncAttributes(record)
		end
	end
end

local function tickGathererHauling(record: WorkerRecord)
	local unit = record.unit
	local building = record.building
	if not building or not building.Parent then
		WorkerService.setState(unit, "Idle", { ownerId = record.ownerId, presentation = true })
		return
	end

	local arrived = pathfindToBuilding(unit, building, 3) or snapIfStuck(record)
	if arrived then
		if record.resourceType and record.resourcesCarrying > 0 then
			local modifier = getModifier(record.ownerId)
			local amount = math.floor(record.resourcesCarrying * modifier)
			if amount > 0 then
				BuildingManager.addToStorage(building, record.resourceType, amount)
			end
		end
		record.resourcesCarrying = 0
		WorkerService.setState(unit, "Working", {})
	end
end

-- ============================================================
-- BEHAVIOUR: HAULER
-- Moves goods between buildings and storage. No employer building -- the
-- job is the source/destination pair, refreshed by assignHaulersToBuildings.
-- ============================================================

local function returnHaulerToIdle(record: WorkerRecord)
	WorkerService.setState(record.unit, "Idle", { ownerId = record.ownerId, presentation = true })
end

local function tickHauler(record: WorkerRecord)
	local unit = record.unit

	if record.haulPhase == "ToStorage" then
		local storage = record.targetStorage
		if not (storage and storage.Parent) then
			returnHaulerToIdle(record)
			return
		end
		local entrancePos = getInteractionPos(storage)
		if not entrancePos then
			returnHaulerToIdle(record)
			return
		end
		if pathfindToPosition(unit, entrancePos, 3) then
			for _, part in unit:GetDescendants() do
				if part:IsA("BasePart") then
					part.Transparency = 1
				end
			end
			record.unloadStart = tick()
			record.haulPhase = "Unloading"
		end
		return
	end

	if record.haulPhase == "Unloading" then
		if record.unloadStart and tick() - record.unloadStart >= CONFIG.HAULER_UNLOAD_SECONDS then
			local storage = record.targetStorage
			if storage and storage.Parent and record.resourceType then
				BuildingManager.addToStorage(storage, record.resourceType, record.resourcesCarrying)
			end
			record.resourcesCarrying = 0
			for _, part in unit:GetDescendants() do
				if part:IsA("BasePart") then
					part.Transparency = 0
				end
			end
			returnHaulerToIdle(record)
		end
		return
	end

	-- ToPickup (default / initial phase).
	local source = record.sourceBuilding
	if not (source and source.Parent) or not record.resourceType then
		returnHaulerToIdle(record)
		return
	end
	local pickupPos = getInteractionPos(source)
	if not pickupPos then
		returnHaulerToIdle(record)
		return
	end
	if pathfindToPosition(unit, pickupPos, 3) then
		local picked = BuildingManager.takeFromStorage(source, record.resourceType, CONFIG.HAULER_PICKUP_AMOUNT)
		if picked <= 0 then
			returnHaulerToIdle(record)
			return
		end
		record.resourcesCarrying = picked

		if record.haulRole ~= "Supply" then
			record.targetStorage = BuildingIndex.findStorageFor(record.ownerId :: number, record.resourceType, source)
		end

		if not (record.targetStorage and (record.targetStorage :: Instance).Parent) then
			BuildingManager.addToStorage(source, record.resourceType, picked)
			record.resourcesCarrying = 0
			returnHaulerToIdle(record)
			return
		end

		record.haulPhase = "ToStorage"
		WorkerService.setState(unit, "Hauling", {})
	end
end

-- ============================================================
-- COMMON: walking to an employer building (Gatherer / Producer / Server)
-- ============================================================

local function tickTravellingToBuilding(record: WorkerRecord)
	local building = record.building
	if not building or not building.Parent then
		WorkerService.setState(record.unit, "Idle", { ownerId = record.ownerId, presentation = true })
		return
	end

	local arrived = pathfindToBuilding(record.unit, building, 3) or snapIfStuck(record)
	if not arrived then
		return
	end

	if not record.hasTransformed then
		local newUnit = transformToRole(record.unit, record.role)
		if newUnit ~= record.unit then
			rekey(record, record.unit, newUnit)
		end
		record.hasTransformed = true
	end

	local unit = record.unit
	unit:SetAttribute("TargetPosition", nil)
	unit:SetAttribute("IsMoving", false)
	-- Arriving means "at the station" for Producer/Server (they never leave
	-- again); a Gatherer immediately re-evaluates this against node
	-- availability on its first Working tick.
	record.atStation = true

	-- Optional: hide the worker inside the building if the model authors one.
	if WorkerPointSystem.hasPoint(building :: any, "TeleportIntoBuilding" :: any) then
		local teleportPoint = WorkerPointSystem.getPointPosition(building :: any, "TeleportIntoBuilding" :: any)
		if teleportPoint and unit.PrimaryPart then
			unit:PivotTo(CFrame.new(teleportPoint))
			for _, part in unit:GetDescendants() do
				if part:IsA("BasePart") then
					part.Transparency = 1
					part.CanCollide = false
				end
			end
		end
	end

	WorkerService.setState(unit, "Working", {})
end

-- ============================================================
-- DISPATCH -- branches only on `behaviour` (4 values) and `state` (4 values),
-- never on a trade/job-type string.
-- ============================================================

local function tickWorker(record: WorkerRecord)
	if record.state == "Idle" then
		tickPresentation(record)
		return
	end

	if record.behaviour == "Hauler" then
		tickHauler(record)
		return
	end

	if record.state == "Travelling" then
		tickTravellingToBuilding(record)
		return
	end

	if record.state == "Working" then
		if record.behaviour == "Gatherer" then
			tickGathererWorking(record)
		else
			tickProducerCycle(record)
		end
		return
	end

	if record.state == "Hauling" then
		-- Only a Gatherer reaches this state: carrying its harvest home.
		tickGathererHauling(record)
	end
end

-- ============================================================
-- HAULER ASSIGNMENT SWEEP (every CONFIG.HAULER_ASSIGNMENT_INTERVAL seconds)
-- ============================================================

local function isUnitBusy(unit: Model): boolean
	local record = Records[unit]
	return record ~= nil and record.state ~= "Idle"
end

local function getIdlePeasantsForOwner(ownerId: number): { Model }
	local out: { Model } = {}
	local set = IdleByOwner[ownerId]
	if set then
		for record in set do
			if record.unit and record.unit.Parent then
				table.insert(out, record.unit)
			end
		end
	end
	return out
end

type HaulJob = { building: Instance, resourceType: string, ownerId: number, role: "Output" | "Supply" }

local function assignHaulersToBuildings()
	local jobs: { HaulJob } = {}

	for _, ownerId in BuildingIndex.getAllOwnerIds() do
		for _, building in BuildingIndex.getOwnerBuildings(ownerId) do
			local buildingType = building:GetAttribute("BuildingType")
			local spec = buildingType and BuildingSpec.get(buildingType :: string)
			local work = spec and spec.work
			if not (spec and work) then
				continue
			end

			for resourceType in work.outputs do
				if spec.storage[resourceType] then
					local have = BuildingManager.getStorageAmount(building, resourceType)
					if have >= CONFIG.HAULER_OUTPUT_THRESHOLD then
						local alreadyAssigned = false
						for _, record in Records do
							if
								record.behaviour == "Hauler"
								and record.sourceBuilding == building
								and record.haulRole == "Output"
								and record.state ~= "Idle"
							then
								alreadyAssigned = true
								break
							end
						end
						if not alreadyAssigned then
							table.insert(jobs, { building = building, resourceType = resourceType, ownerId = ownerId, role = "Output" })
						end
					end
				end
			end

			for resourceType, amount in work.inputs do
				local have = BuildingManager.getStorageAmount(building, resourceType)
				if have < amount * 3 then
					local alreadySupplying = false
					for _, record in Records do
						if
							record.behaviour == "Hauler"
							and record.targetStorage == building
							and record.haulRole == "Supply"
							and record.state ~= "Idle"
						then
							alreadySupplying = true
							break
						end
					end
					if
						not alreadySupplying
						and BuildingIndex.findStorageWithResource(ownerId, resourceType, CONFIG.HAULER_SUPPLY_MIN)
					then
						table.insert(jobs, { building = building, resourceType = resourceType, ownerId = ownerId, role = "Supply" })
					end
				end
			end
		end
	end

	for _, job in jobs do
		for _, unit in getIdlePeasantsForOwner(job.ownerId) do
			if unit and unit.Parent and not isUnitBusy(unit) then
				if job.role == "Supply" then
					local source = BuildingIndex.findStorageWithResource(job.ownerId, job.resourceType, CONFIG.HAULER_SUPPLY_MIN)
					if source then
						WorkerService.createHaulerTask(unit, source, job.resourceType, job.ownerId, "Supply")
						local record = Records[unit]
						if record then
							record.targetStorage = job.building
						end
					end
				else
					WorkerService.createHaulerTask(unit, job.building, job.resourceType, job.ownerId, "Output")
				end
				break
			end
		end
	end
end

-- ============================================================
-- PUBLIC API
-- ============================================================

-- Replaces IdlePeasantManager.addIdlePeasant: true idle, with presentation.
function WorkerService.addIdlePeasant(peasant: Model, ownerId: number)
	WorkerService.setState(peasant, "Idle", { ownerId = ownerId, presentation = true })
end

-- Replaces IdlePeasantManager.removeIdlePeasant. Previously this ALSO force-
-- set IsIdle=false, which -- paired with releaseFromWork on every manual move
-- order -- was exactly the undocumented 4th state (IsWorking=false AND
-- IsIdle=false). Now it only detaches the visual loitering; `state` (and the
-- attributes derived from it) are untouched, so the unit is still, honestly,
-- Idle.
function WorkerService.suppressPresentation(unit: Model): boolean
	local record = Records[unit]
	if not record then
		return false
	end
	local hadPresentation = record.idle ~= nil
	clearPresentation(record)
	syncAttributes(record)
	return hadPresentation
end

function WorkerService.isIdle(unit: Model): boolean
	local record = Records[unit]
	return record ~= nil and record.state == "Idle"
end

-- The labour pool: idle AND decorated with presentation (i.e. not currently
-- mid manual player order). Mirrors the old IdlePeasantManager list exactly.
function WorkerService.getIdlePeasantsForOwner(ownerId: number): { Model }
	return getIdlePeasantsForOwner(ownerId)
end

-- Safe to call on ANY unit -- soldiers, already-idle peasants, anything.
-- Stops a working/hauling unit being re-tasked every frame so a manual
-- move/formation order can take over, WITHOUT leaving it in limbo: it lands
-- in the real Idle state, just without the campfire/roam presentation (that
-- would otherwise fight the move order for TargetPosition/IsMoving).
function WorkerService.releaseFromWork(unit: Model?)
	if not unit then
		return
	end
	local record = Records[unit]
	if not record then
		return
	end
	if record.state == "Idle" then
		clearPresentation(record)
		syncAttributes(record)
		return
	end
	WorkerService.setState(unit, "Idle", { ownerId = record.ownerId, presentation = false })
end

-- Revert a unit's rig/label back to a plain Peasant. Returns the (possibly
-- new) model; callers MUST use the return value.
function WorkerService.revertToBaseUnit(unit: Model?): Model?
	if not unit then
		return unit
	end
	local record = Records[unit]
	local currentRole = (record and record.role) or (unit:GetAttribute("UnitType") :: string?) or "Peasant"
	if currentRole == "Peasant" then
		setUnitDisplayName(unit, "Peasant")
		return unit
	end

	local newUnit = transformToRole(unit, "Peasant")
	if record then
		if newUnit ~= unit then
			rekey(record, unit, newUnit)
		end
		record.role = "Peasant"
		record.behaviour = WorkerRoles.getBehaviour("Peasant")
	end
	return newUnit
end

function WorkerService.assignWorkerToBuilding(peasant: Model?, building: Instance?, ownerId: number)
	if not peasant or not building then
		return
	end
	local buildingType = building:GetAttribute("BuildingType")
	local work = buildingType and BuildingSpec.getWork(buildingType :: string)
	if not work or work.slots <= 0 then
		return
	end

	WorkerService.setState(peasant, "Travelling", {
		ownerId = ownerId,
		building = building,
		buildingType = buildingType :: string,
		role = work.role,
	})
end

-- Every worker is now real: no virtual headcount, no despawned-but-still-
-- counted operators. Claims the nearest idle peasant and gives it a real rig.
function WorkerService.assignNearestIdlePeasant(building: Instance, ownerId: number): boolean
	local buildingType = building:GetAttribute("BuildingType")
	local work = buildingType and BuildingSpec.getWork(buildingType :: string)
	if not work or work.slots <= 0 then
		return false
	end
	if getAssignedCount(building) >= work.slots then
		return false
	end

	local approach = getInteractionPos(building)
	if not approach then
		return false
	end

	local nearest: Model? = nil
	local nearestDist = math.huge
	for _, unit in getIdlePeasantsForOwner(ownerId) do
		if unit and unit.Parent and unit.PrimaryPart then
			local d = (unit.PrimaryPart.Position - approach).Magnitude
			if d < nearestDist then
				nearestDist = d
				nearest = unit
			end
		end
	end

	if not nearest then
		return false
	end

	WorkerService.assignWorkerToBuilding(nearest, building, ownerId)
	return true
end

function WorkerService.unassignWorker(building: Instance, count: number?): number
	local toRemove = count or 1
	local toRelease: { WorkerRecord } = {}
	for _, record in Records do
		if #toRelease >= toRemove then
			break
		end
		if record.building == building then
			table.insert(toRelease, record)
		end
	end

	for _, record in toRelease do
		WorkerService.setState(record.unit, "Idle", { ownerId = record.ownerId, presentation = true })
	end

	WorkerDebug:info(`Released {#toRelease} worker(s) from {building.Name}`)
	return #toRelease
end

unassignWorkersFromBuilding = function(building: Instance): number
	return WorkerService.unassignWorker(building, math.huge)
end
WorkerService.unassignWorkersFromBuilding = unassignWorkersFromBuilding

function WorkerService.getAssignedCount(building: Instance): number
	return getAssignedCount(building)
end

function WorkerService.getWorkerCapacity(building: Instance): number
	return getWorkerCapacity(building)
end

function WorkerService.getTotalWorkers(building: Instance): number
	return getAssignedCount(building)
end

function WorkerService.createHaulerTask(
	hauler: Model?,
	sourceBuilding: Instance?,
	resourceType: string,
	ownerId: number,
	role: ("Output" | "Supply")?
)
	if not hauler or not sourceBuilding then
		return
	end

	local unit = WorkerService.setState(hauler, "Travelling", {
		ownerId = ownerId,
		role = "Hauler",
		haulRole = role or "Output",
		sourceBuilding = sourceBuilding,
		resourceType = resourceType,
	})

	local record = Records[unit]
	if not record then
		return
	end
	record.haulPhase = "ToPickup"

	if not record.hasTransformed then
		local newUnit = transformToRole(unit, "Hauler")
		if newUnit ~= unit then
			rekey(record, unit, newUnit)
		end
		record.hasTransformed = true
	end

	HaulerDebug:info(`Created {role or "Output"} hauler task for {record.unit.Name} (owner {ownerId})`)
end

function WorkerService.setProductionModifier(player: Player, modifier: number)
	productionModifiers[player.UserId] = math.clamp(modifier, 0, 1)
end

-- ============================================================
-- SCHEDULER
-- ============================================================

function WorkerService.setScheduleBudget(n: number)
	scheduleBudget = math.max(1, n)
end

-- Staggered round-robin: at most `scheduleBudget` workers are ticked per
-- Heartbeat instead of every worker every frame. This is safe because every
-- cycle timer in this file is a `tick()` deadline check, not a per-frame dt
-- accumulator -- a worker that waits an extra frame or two for its turn still
-- fires exactly on schedule once serviced. The budget only bounds worst-case
-- latency (roughly population/budget frames, a few hundredths of a second at
-- normal population sizes), it never desyncs production math.
function WorkerService.update(_dt: number)
	local total = #Roster
	if total > 0 then
		local n = math.min(scheduleBudget, total)
		for _ = 1, n do
			local unit = Roster[cursor]
			cursor += 1
			if cursor > #Roster then
				cursor = 1
			end
			if unit and unit.Parent then
				local record = Records[unit]
				if record then
					tickWorker(record)
				end
			elseif unit then
				-- The unit is gone (killed, despawned). Drop EVERY reference to
				-- it, not just its roster slot.
				--
				-- Records is keyed by the Model, so leaving the entry behind
				-- keeps the destroyed Instance reachable forever -- a real leak,
				-- not just stale data. It also makes the game get slower the
				-- longer a match runs, because getAssignedCount() walks the whole
				-- Records table on every state transition. The old WorkerManager
				-- pruned dead tasks in its update loop; this restores that.
				local dead = Records[unit]
				if dead then
					-- clearPresentation also drops it from IdleByOwner.
					clearPresentation(dead)
					local employer = dead.building
					Records[unit] = nil
					if employer and employer.Parent then
						-- Free the slot so the building can hire a replacement.
						syncBuildingWorkerAttrs(employer)
					end
				end
				rosterRemove(unit)
			end
		end
	end

	local now = tick()
	if now - lastHaulerAssignmentTime >= CONFIG.HAULER_ASSIGNMENT_INTERVAL then
		assignHaulersToBuildings()
		lastHaulerAssignmentTime = now
	end
end

function WorkerService.startLoop()
	RunService.Heartbeat:Connect(function(dt)
		WorkerService.update(dt)
	end)
	WorkerDebug:info("WorkerService update loop started")
end

return WorkerService
