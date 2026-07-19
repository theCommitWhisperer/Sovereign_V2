--!strict
-- MovementSystem: Production-ready server-side unit movement with A* grid-based pathfinding

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)
local MovementDebug = DebugManager.createChannel("Movement", false)

-- Import new A* pathfinding system
local PathfindingIntegration = require(script.Parent.PathfindingIntegration)
local FlowFieldManager = require(script.Parent.FlowFieldManager)

local MovementSystem = {}

-- PRODUCTION CONFIGURATION
local CONFIG = {
	TARGET_CHANGE_THRESHOLD = 5, -- Studs - how far target must move to recalculate
	ARRIVAL_DISTANCE = 5, -- Studs - distance to consider "arrived"
	DEFAULT_SPEED = 16, -- Studs per second
	MAX_UNITS_PER_FRAME = 100, -- Throttle to prevent lag spikes (round-robin resumes across frames)
	ENABLE_PERFORMANCE_MONITORING = true,
	STUCK_DETECTION_TIME = 10, -- Seconds before considering a unit stuck (was 5 — too aggressive for RTS)
	STUCK_DISTANCE_THRESHOLD = 2, -- Studs - if unit moves less than this in STUCK_DETECTION_TIME
	MAX_PATHFIND_RETRIES = 5, -- Maximum pathfinding retries before falling back to direct walk
	PATHFIND_RETRY_DELAY = 2, -- Seconds to wait before retrying failed pathfinding
	PATHFIND_COOLDOWN = 5, -- Seconds to wait after exhausting retries before trying again (was 30)
	STUCK_ARRIVAL_DISTANCE = 9, -- Stuck within this range of the goal = treat as arrived
	-- Local separation steering (units flow around each other rather than
	-- overlapping — collisions between units are disabled, so this is purely
	-- a movement nudge)
	SEPARATION_RADIUS = 5, -- Studs - neighbours inside this push apart
	SEPARATION_STRENGTH = 3.5, -- Studs of lateral offset applied to move target
	FLOW_LOOKAHEAD = 10, -- Studs ahead the unit steers along its flow field
}

-- Track last target position for each unit to detect changes
local lastTargetPositions = {}

-- Track unit positions for stuck detection
local unitPositionHistory = {}

-- Track pathfinding failures for retry limiting
local pathfindingFailures = {} -- {[unit] = {count = number, lastAttempt = tick()}}

-- Track active paths for units
local unitPaths = {} -- {[unit] = {path = {Vector3}, index = number}}

-- Performance monitoring
local unitsProcessedThisSecond = 0
local lastPerformanceLog = tick()

MovementDebug:info("MovementSystem loading with production A* pathfinding...")

-- Check if target position has changed significantly
local function hasTargetChanged(unit, newTarget)
	local lastTarget = lastTargetPositions[unit]
	if not lastTarget then
		return true
	end

	-- Consider target changed if moved more than threshold
	return (lastTarget - newTarget).Magnitude > CONFIG.TARGET_CHANGE_THRESHOLD
end

-- Detect if a unit is stuck
local function isUnitStuck(unit)
	if not unit.PrimaryPart then
		return false
	end

	local history = unitPositionHistory[unit]
	if not history then
		unitPositionHistory[unit] = {
			position = unit.PrimaryPart.Position,
			timestamp = tick(),
		}
		return false
	end

	local timeSinceLastCheck = tick() - history.timestamp
	if timeSinceLastCheck >= CONFIG.STUCK_DETECTION_TIME then
		local distanceMoved = (unit.PrimaryPart.Position - history.position).Magnitude

		if distanceMoved < CONFIG.STUCK_DISTANCE_THRESHOLD then
			-- Unit is stuck - reset history and return true
			unitPositionHistory[unit] = {
				position = unit.PrimaryPart.Position,
				timestamp = tick(),
			}
			return true
		else
			-- Unit is moving - update history
			unitPositionHistory[unit] = {
				position = unit.PrimaryPart.Position,
				timestamp = tick(),
			}
		end
	end

	return false
end

-- Clean up unit tracking data
-- Humanoid:MoveTo silently times out after 8 seconds; long marches need the
-- order refreshed or units stop partway to their destination.
local lastMoveToTimes = {}

-- Active sidestep detours (stuck units peel off geometry before re-pathing)
local sidestepUntil = {}

local function cleanupUnit(unit)
	lastTargetPositions[unit] = nil
	unitPositionHistory[unit] = nil
	pathfindingFailures[unit] = nil
	unitPaths[unit] = nil
	lastMoveToTimes[unit] = nil
	sidestepUntil[unit] = nil
	PathfindingIntegration.unregisterMover(unit)
end

-- ── Local separation steering ──────────────────────────────────────────────
-- A lightweight spatial hash rebuilt each update from unit positions. Each
-- moving unit queries its 9 surrounding cells and gets pushed away from close
-- neighbours, so groups flow around one another instead of piling up.
local SEP_CELL = 5 -- studs; ~= SEPARATION_RADIUS
local sepBuckets: { [number]: { { pos: Vector3, model: Instance } } } = {}

local function sepKey(x: number, z: number): number
	local cx = math.floor(x / SEP_CELL)
	local cz = math.floor(z / SEP_CELL)
	return (cx + 32768) * 65536 + (cz + 32768)
end

local function buildSeparationBuckets(unitsFolder: Instance)
	table.clear(sepBuckets)
	for _, unit in unitsFolder:GetChildren() do
		if unit:IsA("Model") and unit.PrimaryPart then
			local pos = unit.PrimaryPart.Position
			local key = sepKey(pos.X, pos.Z)
			local bucket = sepBuckets[key]
			if not bucket then
				bucket = {}
				sepBuckets[key] = bucket
			end
			table.insert(bucket, { pos = pos, model = unit })
		end
	end
end

-- Sum of repulsion from nearby units, as a horizontal Vector3 (may be zero)
local function computeSeparation(unit: Instance, pos: Vector3): Vector3
	local push = Vector3.zero
	local radiusSq = CONFIG.SEPARATION_RADIUS * CONFIG.SEPARATION_RADIUS
	local baseCx = math.floor(pos.X / SEP_CELL)
	local baseCz = math.floor(pos.Z / SEP_CELL)
	for dx = -1, 1 do
		for dz = -1, 1 do
			local bucket = sepBuckets[((baseCx + dx) + 32768) * 65536 + ((baseCz + dz) + 32768)]
			if bucket then
				for _, entry in bucket do
					if entry.model ~= unit then
						local delta = pos - entry.pos
						local flat = Vector3.new(delta.X, 0, delta.Z)
						local distSq = flat.X * flat.X + flat.Z * flat.Z
						if distSq < radiusSq and distSq > 0.0001 then
							-- Closer neighbours push harder (inverse falloff)
							local dist = math.sqrt(distSq)
							push += flat / dist * (1 - dist / CONFIG.SEPARATION_RADIUS)
						end
					end
				end
			end
		end
	end
	if push.Magnitude > 0.001 then
		return push.Unit * CONFIG.SEPARATION_STRENGTH
	end
	return Vector3.zero
end

-- Round-robin resume point: the old throttle iterated GetChildren() in a
-- FIXED order and broke after MAX_UNITS_PER_FRAME — with more movers than
-- the budget, the same units were processed every frame and the rest NEVER
-- received a move command (permanently stuck).
local roundRobinIndex = 1

-- Update all moving units using A* pathfinding
function MovementSystem.update()
	local unitsFolder = workspace:FindFirstChild("Units")
	if not unitsFolder then
		return
	end

	local children = unitsFolder:GetChildren()
	local totalChildren = #children
	if totalChildren == 0 then
		return
	end
	if roundRobinIndex > totalChildren then
		roundRobinIndex = 1
	end

	-- Rebuild the separation spatial hash once for this update
	buildSeparationBuckets(unitsFolder)

	local unitsProcessedThisFrame = 0
	local visited = 0
	local childIndex = roundRobinIndex

	-- Process each unit that wants to move, resuming where last frame stopped
	while visited < totalChildren do
		local unit = children[childIndex]
		childIndex = childIndex % totalChildren + 1
		visited += 1

		if not unit:IsA("Model") then
			continue
		end

		-- Throttle processing to prevent lag; resume from here next frame
		if unitsProcessedThisFrame >= CONFIG.MAX_UNITS_PER_FRAME then
			roundRobinIndex = childIndex
			MovementDebug:warn("Unit processing throttled - too many units this frame")
			break
		end

		-- Validate unit has essential components
		if not unit.PrimaryPart then
			continue
		end

		if unit:GetAttribute("IsMoving") then
			-- Skip units that recently failed pathfinding (short cooldown then retry)
			local failedTime = unit:GetAttribute("PathfindingFailed")
			if failedTime and (tick() - failedTime) < CONFIG.PATHFIND_COOLDOWN then
				continue
			elseif failedTime then
				-- Cooldown expired — clear the flag so the unit can try again
				unit:SetAttribute("PathfindingFailed", nil)
				pathfindingFailures[unit] = nil
			end

			unitsProcessedThisFrame = unitsProcessedThisFrame + 1
			unitsProcessedThisSecond = unitsProcessedThisSecond + 1

			local targetPos = unit:GetAttribute("TargetPosition")

			if targetPos and typeof(targetPos) == "Vector3" then
				-- Wrap in pcall for safety
				local success, result = pcall(function()
					-- Check if unit is close enough to target. Formation moves set
					-- a tighter per-unit ArrivalDistance (slots are only 2-6 studs
					-- apart — the default 5-stud tolerance turned formations into
					-- clumps because units "arrived" while still in a blob).
					local arrivalDistance = (unit:GetAttribute("ArrivalDistance") :: number?)
						or CONFIG.ARRIVAL_DISTANCE
					-- HORIZONTAL distance only: the root part sits ~4.5 studs above
					-- ground-level targets, so a 3D check can exceed tight arrival
					-- tolerances forever (formation snap never fired, IsMoving never
					-- cleared, stragglers never corrected)
					local arrivalDelta = unit.PrimaryPart.Position - targetPos
					local distance = Vector3.new(arrivalDelta.X, 0, arrivalDelta.Z).Magnitude
					if distance < arrivalDistance then
						-- Arrived at destination
						unit:SetAttribute("IsMoving", false)
						unit:SetAttribute("TargetPosition", nil)
						unit:SetAttribute("FlowFieldId", nil)

						-- Formation slot: snap exactly onto it and face the way the
						-- formation faces — this is what makes ranks read as clean
						-- lines instead of a loose crowd pointing everywhere
						local formationFacing = unit:GetAttribute("FormationFacing")
						if typeof(formationFacing) == "Vector3" then
							local currentPos = unit.PrimaryPart.Position
							local snapPos = Vector3.new(targetPos.X, currentPos.Y, targetPos.Z)
							local flatFacing = Vector3.new(formationFacing.X, 0, formationFacing.Z)
							if flatFacing.Magnitude > 0.01 then
								unit:PivotTo(CFrame.lookAt(snapPos, snapPos + flatFacing))
							else
								unit:PivotTo(CFrame.new(snapPos))
							end
							unit:SetAttribute("FormationFacing", nil)
						end

						cleanupUnit(unit)
						MovementDebug:info("Unit " .. unit.Name .. " arrived at destination")
						return
					end

					-- Check for stuck units
					if isUnitStuck(unit) then
						-- Stuck but already near the goal (workers pressing against a
						-- building wall trying to reach an interior point): call it
						-- arrived — interaction radii are more generous than this.
						if distance < CONFIG.STUCK_ARRIVAL_DISTANCE then
							unit:SetAttribute("IsMoving", false)
							unit:SetAttribute("TargetPosition", nil)
							cleanupUnit(unit)
							MovementDebug:info("Unit " .. unit.Name .. " stuck near goal — treating as arrived")
							return
						end

						MovementDebug:warn("Unit " .. unit.Name .. " appears stuck, recalculating path")
						-- Force recalculation by clearing last target
						lastTargetPositions[unit] = nil

						-- Sidestep to peel off whatever geometry we're pressed against
						-- before re-pathing — recalculating from a wall-hug position
						-- tends to produce the same blocked path again.
						local stuckHumanoid = unit:FindFirstChildOfClass("Humanoid")
						if stuckHumanoid then
							local awayDir = (targetPos - unit.PrimaryPart.Position)
							local flatDir = Vector3.new(awayDir.X, 0, awayDir.Z)
							if flatDir.Magnitude > 0.1 then
								flatDir = flatDir.Unit
								local sign = if math.random() < 0.5 then 1 else -1
								local perpendicular = Vector3.new(-flatDir.Z, 0, flatDir.X) * sign * 8
								stuckHumanoid:MoveTo(unit.PrimaryPart.Position + perpendicular)
								lastMoveToTimes[unit] = tick()
								sidestepUntil[unit] = tick() + 0.7
							end
						end
					end

					-- While sidestepping, let the detour play out before re-pathing
					if sidestepUntil[unit] then
						if tick() < sidestepUntil[unit] then
							return
						end
						sidestepUntil[unit] = nil
					end

					-- Check if target has changed (unit was redirected)
					local targetChanged = hasTargetChanged(unit, targetPos)

					-- Get unit speed from Humanoid WalkSpeed or use default
					local speed = CONFIG.DEFAULT_SPEED
					local humanoid = unit:FindFirstChildOfClass("Humanoid")
					if humanoid and humanoid.WalkSpeed > 0 then
						speed = math.clamp(humanoid.WalkSpeed, 1, 100)
					end

					local unitPos = unit.PrimaryPart.Position
					local separation = computeSeparation(unit, unitPos)

					-- Fade separation to zero as a unit nears its target. Formation
					-- slots sit ~4 studs apart — inside the separation radius — so
					-- without this, neighbours shove a settling unit left↔right and
					-- it never locks onto its slot. Full push while travelling
					-- (>=12 studs), none while settling (<=5).
					local sepScale = math.clamp((distance - 5) / 7, 0, 1)
					separation = separation * sepScale

					-- ── Flow-field following (shared group movement) ──────────
					-- When a group was ordered via MovementSystem.moveGroup, every
					-- member follows one precomputed field instead of running its
					-- own A*. Honored only while the field's goal still matches
					-- this unit's target (combat retarget auto-invalidates it).
					local flowId = unit:GetAttribute("FlowFieldId")
					if flowId and typeof(flowId) == "number" and PathfindingIntegration.isInitialized() then
						local fieldGoal = FlowFieldManager.getGoal(flowId)
						if fieldGoal and (Vector3.new(fieldGoal.X, 0, fieldGoal.Z) - Vector3.new(targetPos.X, 0, targetPos.Z)).Magnitude <= 10 then
							local flowDir = FlowFieldManager.sample(flowId, unitPos)
							if humanoid then
								local dest: Vector3
								if flowDir.Magnitude < 0.01 then
									-- Field exhausted near the goal: head straight in
									dest = targetPos + separation
								else
									dest = unitPos + flowDir * CONFIG.FLOW_LOOKAHEAD + separation
								end
								if tick() - (lastMoveToTimes[unit] or 0) > 0.35 or targetChanged then
									humanoid:MoveTo(dest)
									lastMoveToTimes[unit] = tick()
								end
							end
							lastTargetPositions[unit] = targetPos
							return -- flow field handles this unit; skip A*
						else
							-- Field no longer relevant to this order
							unit:SetAttribute("FlowFieldId", nil)
						end
					end

					-- No pathfinding grid (e.g. Battle Arena — flat ground, no map):
					-- walk straight at the target instead of standing still forever.
					-- Separation keeps arena armies from overlapping into one mass.
					if not PathfindingIntegration.isInitialized() then
						if humanoid then
							local dest = targetPos + separation
							if targetChanged or tick() - (lastMoveToTimes[unit] or 0) > 0.35 then
								humanoid:MoveTo(dest)
								lastMoveToTimes[unit] = tick()
							end
						end
						unitPaths[unit] = {
							path = { targetPos },
							index = 1,
						}
						lastTargetPositions[unit] = targetPos
						return
					end

					-- Start or restart pathfinding if target changed
					if PathfindingIntegration.isInitialized() and targetChanged then
						-- Check if we should retry pathfinding (retry limiting)
						local failureData = pathfindingFailures[unit]
						local canRetry = true

						if failureData then
							-- Check if max retries exceeded
							if failureData.count >= CONFIG.MAX_PATHFIND_RETRIES then
								-- Check if enough time has passed to reset retry counter
								if tick() - failureData.lastAttempt >= CONFIG.PATHFIND_RETRY_DELAY then
									-- Reset retry counter after delay
									pathfindingFailures[unit] = nil
									failureData = nil
								else
									-- Too many retries, don't spam pathfinding
									canRetry = false
								end
							elseif tick() - failureData.lastAttempt < 0.5 then
								-- Don't retry more than twice per second
								canRetry = false
							end
						end

						if canRetry then
							-- Get path from PathfindingIntegration
							local path, pathFailReason = PathfindingIntegration.getPath(unit, targetPos)

							-- Frame budget exhaustion is NOT a failure — counting it
							-- as one pushed units into the direct-walk fallback,
							-- which beelines straight into buildings. Just wait.
							if path == nil and pathFailReason == "throttled" then
								return
							end

							local pathSuccess = path ~= nil and #path > 0
							if pathSuccess and path then
								-- Store path in local table
								unitPaths[unit] = {
									path = path,
									index = 1,
								}

								-- Move humanoid to first waypoint
								local humanoid = unit:FindFirstChildOfClass("Humanoid")
								if humanoid and #path > 0 then
									humanoid:MoveTo(path[1])
									MovementDebug:info(`Unit {unit.Name} starting path with {#path} waypoints to {path[1]}`)
								end

								-- Remember this target position
								lastTargetPositions[unit] = targetPos
								-- Clear failure tracking on success
								pathfindingFailures[unit] = nil
								if targetChanged then
									MovementDebug:info("Unit " .. unit.Name .. " redirected to new target")
								end
							else
								-- Track failure
								if not pathfindingFailures[unit] then
									pathfindingFailures[unit] = {count = 1, lastAttempt = tick()}
								else
									pathfindingFailures[unit].count = pathfindingFailures[unit].count + 1
									pathfindingFailures[unit].lastAttempt = tick()
								end

								-- After max retries, fall back to direct walk toward target
								if pathfindingFailures[unit].count >= CONFIG.MAX_PATHFIND_RETRIES then
									MovementDebug:warn(`A* failed for {unit.Name} after {CONFIG.MAX_PATHFIND_RETRIES} attempts, using direct walk`)
									-- Use Humanoid:MoveTo as a direct-walk fallback
									local humanoid = unit:FindFirstChildOfClass("Humanoid")
									if humanoid then
										humanoid:MoveTo(targetPos)
									end
									-- Store a single-waypoint "path" so the follow logic still works
									unitPaths[unit] = {
										path = { targetPos },
										index = 1,
									}
									lastTargetPositions[unit] = targetPos
									-- Set cooldown so we don't spam A* on the next frame
									unit:SetAttribute("PathfindingFailed", tick())
								end
							end
						end
					end

					-- Handle path following for units with active paths
					local pathData = unitPaths[unit]
					if pathData and pathData.path and #pathData.path > 0 then
						local currentWaypoint = pathData.path[pathData.index]
						if currentWaypoint and unit.PrimaryPart then
							local distanceToWaypoint = (unit.PrimaryPart.Position - currentWaypoint).Magnitude

							-- Refresh MoveTo before its 8-second internal timeout so
							-- long marches don't stall partway
							if distanceToWaypoint >= 3 and tick() - (lastMoveToTimes[unit] or 0) > 0.4 then
								local marchHumanoid = unit:FindFirstChildOfClass("Humanoid")
								if marchHumanoid then
									marchHumanoid:MoveTo(currentWaypoint + separation)
									lastMoveToTimes[unit] = tick()
								end
							end

							-- If we're close to current waypoint, move to next one
							if distanceToWaypoint < 3 then
								pathData.index = pathData.index + 1

								if pathData.index <= #pathData.path then
									-- Move to next waypoint
									local humanoid = unit:FindFirstChildOfClass("Humanoid")
									if humanoid then
										humanoid:MoveTo(pathData.path[pathData.index] + separation)
										lastMoveToTimes[unit] = tick()
										MovementDebug:info(`Unit {unit.Name} reached waypoint {pathData.index - 1}/{#pathData.path}, moving to next`)
									end
								else
									-- Reached end of path
									MovementDebug:info(`Unit {unit.Name} reached final destination`)
									unitPaths[unit] = nil
								end
							end
						end
					end
				end)

				if not success then
					warn("Error processing unit " .. unit.Name .. ": " .. tostring(result))
					unit:SetAttribute("IsMoving", false)
					cleanupUnit(unit)
				end
			else
				-- No valid target - stop moving
				unit:SetAttribute("IsMoving", false)
				cleanupUnit(unit)
			end
		else
			-- Unit stopped moving - clean up
			if lastTargetPositions[unit] or unitPositionHistory[unit] then
				cleanupUnit(unit)
			end
		end
	end
end

-- Move a group of units to a shared destination using ONE flow field (falls
-- back to plain per-unit targets if pathfinding is inactive or the goal is
-- unreachable). Use this for AI army marches, worker rallies, and any order
-- that sends many units to the same place — far cheaper than N separate A*
-- solves and it produces coherent flow.
function MovementSystem.moveGroup(units: { Model }, destination: Vector3)
	local flowId: number? = nil
	if PathfindingIntegration.isInitialized() then
		flowId = FlowFieldManager.acquire(destination)
	end

	for _, unit in units do
		if unit and unit.Parent and unit:IsA("Model") then
			unit:SetAttribute("CombatTarget", nil)
			unit:SetAttribute("TargetPosition", destination)
			unit:SetAttribute("IsMoving", true)
			unit:SetAttribute("PathfindingFailed", nil)
			unit:SetAttribute("ArrivalDistance", nil)
			unit:SetAttribute("FormationFacing", nil)
			if flowId then
				unit:SetAttribute("FlowFieldId", flowId)
			else
				unit:SetAttribute("FlowFieldId", nil)
			end
		end
	end
	return flowId ~= nil
end

-- Get movement statistics
function MovementSystem.getStats()
	local activeUnits = 0
	for _ in pairs(lastTargetPositions) do
		activeUnits = activeUnits + 1
	end

	return {
		activeMovingUnits = activeUnits,
		unitsProcessedLastSecond = unitsProcessedThisSecond,
		config = CONFIG,
	}
end

-- Update configuration at runtime
function MovementSystem.setConfig(key, value)
	if CONFIG[key] ~= nil then
		CONFIG[key] = value
		MovementDebug:info("Config updated: " .. key .. " = " .. tostring(value))
		return true
	else
		warn("Invalid config key: " .. key)
		return false
	end
end

local movementLoopStarted = false

function MovementSystem.startLoop()
	-- Idempotent: ArenaMode and GameManager may both call this
	if movementLoopStarted then
		return
	end
	movementLoopStarted = true
	RunService.Heartbeat:Connect(function()
		MovementSystem.update()
	end)
end

-- Performance monitoring loop
if CONFIG.ENABLE_PERFORMANCE_MONITORING then
	task.spawn(function()
		while true do
			task.wait(1)

			local now = tick()
			if now - lastPerformanceLog >= 1 then
				if unitsProcessedThisSecond > 500 then
					MovementDebug:warn("High unit processing load: " .. unitsProcessedThisSecond .. " units/second")
				end

				-- Reset counter
				unitsProcessedThisSecond = 0
				lastPerformanceLog = now
			end
		end
	end)
end

MovementDebug:info("MovementSystem initialized successfully with production A* pathfinding!")

return MovementSystem
                                                                                                                                                                                                                                                                                                                                                        