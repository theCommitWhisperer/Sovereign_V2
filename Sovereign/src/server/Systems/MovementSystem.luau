--!strict
-- MovementSystem: Handles server-side unit movement with pathfinding

local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)
local MovementDebug = DebugManager.createChannel("Movement", true)

local MovementSystem = {}

MovementDebug:info("MovementSystem loading...")

-- Store active paths for each unit
local activePaths = {}

-- Create a path for a unit
local function createPath(unit: Model, targetPos: Vector3)
	local humanoid = unit:FindFirstChildOfClass("Humanoid")
	if not humanoid or not unit.PrimaryPart then
		return nil
	end

	-- Create path with agent parameters
	local path = PathfindingService:CreatePath({
		AgentRadius = 2,
		AgentHeight = 5,
		AgentCanJump = true,
		WaypointSpacing = 4,
		Costs = {
			Water = math.huge, -- Avoid water
		}
	})

	-- Compute path
	local success, errorMsg = pcall(function()
		path:ComputeAsync(unit.PrimaryPart.Position, targetPos)
	end)

	if not success then
		MovementDebug:warn(`Path computation failed for {unit.Name}: {errorMsg}`)
		return nil
	end

	if path.Status == Enum.PathStatus.NoPath then
		MovementDebug:warn(`No path found for {unit.Name}`)
		return nil
	end

	if path.Status == Enum.PathStatus.Success then
		return path
	end

	return nil
end

-- Handle path blocked events
local function setupPathBlockedListener(unit: Model, path: Path)
	local connection
	connection = path.Blocked:Connect(function(blockedWaypointIndex)
		MovementDebug:warn(`Path blocked for {unit.Name} at waypoint {blockedWaypointIndex}`)

		-- Mark as blocked and clear path to force recalculation
		if activePaths[unit] then
			activePaths[unit].blocked = true
			activePaths[unit] = nil
		end

		connection:Disconnect()
	end)
end

-- Follow path waypoints
local function followPath(unit: Model, path: Path)
	local humanoid = unit:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	local waypoints = path:GetWaypoints()

	-- Store path data
	activePaths[unit] = {
		path = path,
		waypoints = waypoints,
		currentWaypointIndex = 2, -- Start at 2 (skip current position)
		blocked = false,
	}

	-- Setup blocked listener
	setupPathBlockedListener(unit, path)

	MovementDebug:info(`Unit {unit.Name} starting path with {#waypoints} waypoints`)
end

-- Update all moving units
function MovementSystem.update()
	local unitsFolder = workspace:FindFirstChild("Units")
	if not unitsFolder then
		return
	end

	for _, unit in unitsFolder:GetChildren() do
		if unit:IsA("Model") and unit:GetAttribute("IsMoving") then
			local targetPos = unit:GetAttribute("TargetPosition")

			if targetPos and typeof(targetPos) == "Vector3" and unit.PrimaryPart then
				local humanoid = unit:FindFirstChildOfClass("Humanoid")

				if humanoid then
					-- Check if we already have an active path
					local pathData = activePaths[unit]

					if not pathData then
						-- No path exists - create one
						local path = createPath(unit, targetPos)
						if path then
							followPath(unit, path)
							pathData = activePaths[unit]
						else
							-- Fallback to direct movement if pathfinding fails
							humanoid:MoveTo(targetPos)
							MovementDebug:warn(`Using direct movement for {unit.Name} (pathfinding failed)`)
						end
					end

					-- If we have path data, follow waypoints
					if pathData and pathData.waypoints then
						local waypoints = pathData.waypoints
						local currentIndex = pathData.currentWaypointIndex

						if currentIndex <= #waypoints then
							local waypoint = waypoints[currentIndex]

							-- Move to current waypoint
							humanoid:MoveTo(waypoint.Position)

							-- Check if we reached this waypoint
							local distance = (unit.PrimaryPart.Position - waypoint.Position).Magnitude
							if distance < 4 then
								-- Move to next waypoint
								pathData.currentWaypointIndex = currentIndex + 1
								MovementDebug:info(`Unit {unit.Name} reached waypoint {currentIndex}/{#waypoints}`)
							end
						else
							-- Reached end of path - check if we're at target
							local finalDistance = (unit.PrimaryPart.Position - targetPos).Magnitude
							if finalDistance < 5 then
								unit:SetAttribute("IsMoving", false)
								unit:SetAttribute("TargetPosition", nil)
								activePaths[unit] = nil
								MovementDebug:info(`Unit {unit.Name} arrived at destination`)
							else
								-- Recalculate path if we're not at target
								MovementDebug:warn(`Unit {unit.Name} finished path but not at target, recalculating...`)
								activePaths[unit] = nil
							end
						end
					end
				end
			else
				-- No valid target - stop moving
				unit:SetAttribute("IsMoving", false)
				activePaths[unit] = nil
			end
		else
			-- Unit stopped moving - clear path data
			if activePaths[unit] then
				activePaths[unit] = nil
			end
		end
	end
end

-- Start update loop
RunService.Heartbeat:Connect(function()
	MovementSystem.update()
end)

MovementDebug:info("MovementSystem initialized successfully with pathfinding!")

return MovementSystem
