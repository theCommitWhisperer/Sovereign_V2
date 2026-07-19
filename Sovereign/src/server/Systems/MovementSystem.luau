--!strict
-- MovementSystem: Production-ready server-side unit movement with A* grid-based pathfinding

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)
local MovementDebug = DebugManager.createChannel("Movement", false)

-- Import new A* pathfinding system
local PathfindingIntegration = require(script.Parent.PathfindingIntegration)

local MovementSystem = {}

-- PRODUCTION CONFIGURATION
local CONFIG = {
	TARGET_CHANGE_THRESHOLD = 5, -- Studs - how far target must move to recalculate
	ARRIVAL_DISTANCE = 5, -- Studs - distance to consider "arrived"
	DEFAULT_SPEED = 16, -- Studs per second
	MAX_UNITS_PER_FRAME = 50, -- Throttle to prevent lag spikes
	ENABLE_PERFORMANCE_MONITORING = true,
	STUCK_DETECTION_TIME = 10, -- Seconds before considering a unit stuck (was 5 — too aggressive for RTS)
	STUCK_DISTANCE_THRESHOLD = 2, -- Studs - if unit moves less than this in STUCK_DETECTION_TIME
	MAX_PATHFIND_RETRIES = 5, -- Maximum pathfinding retries before falling back to direct walk
	PATHFIND_RETRY_DELAY = 2, -- Seconds to wait before retrying failed pathfinding
	PATHFIND_COOLDOWN = 5, -- Seconds to wait after exhausting retries before trying again (was 30)
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

local function cleanupUnit(unit)
	lastTargetPositions[unit] = nil
	unitPositionHistory[unit] = nil
	pathfindingFailures[unit] = nil
	unitPaths[unit] = nil
	lastMoveToTimes[unit] = nil
	PathfindingIntegration.unregisterMover(unit)
end

-- Update all moving units using A* pathfinding
function MovementSystem.update()
	local unitsFolder = workspace:FindFirstChild("Units")
	if not unitsFolder then
		return
	end

	local unitsProcessedThisFrame = 0

	-- Process each unit that wants to move
	for _, unit in unitsFolder:GetChildren() do
		if not unit:IsA("Model") then
			continue
		end

		-- Throttle processing to prevent lag
		if unitsProcessedThisFrame >= CONFIG.MAX_UNITS_PER_FRAME then
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
						MovementDebug:warn("Unit " .. unit.Name .. " appears stuck, recalculating path")
						-- Force recalculation by clearing last target
						lastTargetPositions[unit] = nil
					end

					-- Check if target has changed (unit was redirected)
					local targetChanged = hasTargetChanged(unit, targetPos)

					-- Get unit speed from Humanoid WalkSpeed or use default
					local speed = CONFIG.DEFAULT_SPEED
					local humanoid = unit:FindFirstChildOfClass("Humanoid")
					if humanoid and humanoid.WalkSpeed > 0 then
						speed = math.clamp(humanoid.WalkSpeed, 1, 100)
					end

					-- No pathfinding grid (e.g. Battle Arena — flat ground, no map):
					-- walk straight at the target instead of standing still forever.
					if not PathfindingIntegration.isInitialized() and targetChanged then
						if humanoid then
							humanoid:MoveTo(targetPos)
							lastMoveToTimes[unit] = tick()
						end
						unitPaths[unit] = {
							path = { targetPos },
							index = 1,
						}
						lastTargetPositions[unit] = targetPos
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
							local path = PathfindingIntegration.getPath(unit, targetPos)
							local pathSuccess = path ~= nil and path ~= nil and #path > 0
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
							if distanceToWaypoint >= 3 and tick() - (lastMoveToTimes[unit] or 0) > 4 then
								local marchHumanoid = unit:FindFirstChildOfClass("Humanoid")
								if marchHumanoid then
									marchHumanoid:MoveTo(currentWaypoint)
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
										humanoid:MoveTo(pathData.path[pathData.index])
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