--!strict
-- LocalSteeringBehavior: Handles short-range reactive collision avoidance
-- Uses raycasting and proximity checks for smooth unit flow

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)
local SteeringDebug = DebugManager.createChannel("Steering", false)

local LocalSteeringBehavior = {}

-- Configuration
local AVOIDANCE_RADIUS = 6 -- Distance to check for obstacles (matches user preference)
local COLLISION_CHECK_DISTANCE = 8 -- How far ahead to raycast
local PUSH_FORCE = 0.3 -- How strong the avoidance force is (0-1)
local FRIENDLY_PUSH_DELAY = 2 -- Seconds to wait before pushing through friendlies
local MAX_NEARBY_UNITS = 10 -- Max units to consider for performance

-- Track when units started being blocked
local blockTimers: { [Model]: number } = {}

-- Calculate avoidance vector based on nearby units
local function calculateAvoidanceVector(unit: Model, targetVelocity: Vector3): Vector3
	if not unit.PrimaryPart then
		return Vector3.new(0, 0, 0)
	end

	local unitPos = unit.PrimaryPart.Position
	local ownerId = unit:GetAttribute("Owner")
	local avoidanceVector = Vector3.new(0, 0, 0)
	local nearbyCount = 0

	-- Find nearby units
	local unitsFolder = workspace:FindFirstChild("Units")
	if not unitsFolder then
		return avoidanceVector
	end

	for _, otherUnit in unitsFolder:GetChildren() do
		if otherUnit ~= unit and otherUnit:IsA("Model") and otherUnit.PrimaryPart then
			local otherPos = otherUnit.PrimaryPart.Position
			local distance = (unitPos - otherPos).Magnitude

			-- Only consider nearby units
			if distance < AVOIDANCE_RADIUS and distance > 0.5 then
				nearbyCount += 1

				-- Calculate repulsion vector (away from other unit)
				local repulsionDir = (unitPos - otherPos).Unit
				local repulsionStrength = 1 - (distance / AVOIDANCE_RADIUS) -- Stronger when closer

				-- Friendly units have weaker repulsion
				local otherOwnerId = otherUnit:GetAttribute("Owner")
				local isFriendly = (ownerId == otherOwnerId)

				if isFriendly then
					-- Check if we've been blocked long enough to push through
					if not blockTimers[unit] then
						blockTimers[unit] = tick()
					end

					local blockDuration = tick() - blockTimers[unit]
					if blockDuration > FRIENDLY_PUSH_DELAY then
						-- After delay, push through with reduced force
						repulsionStrength *= 0.3
					else
						-- Still waiting, stronger avoidance
						repulsionStrength *= 0.8
					end
				else
					-- Enemy units have stronger repulsion
					repulsionStrength *= 1.2
				end

				avoidanceVector += repulsionDir * repulsionStrength

				-- Performance: don't check too many units
				if nearbyCount >= MAX_NEARBY_UNITS then
					break
				end
			end
		end
	end

	-- Clear block timer if no nearby units
	if nearbyCount == 0 and blockTimers[unit] then
		blockTimers[unit] = nil
	end

	return avoidanceVector
end

-- Check for obstacles ahead using raycasting
local function checkObstaclesAhead(unit: Model, direction: Vector3): (boolean, Vector3?)
	if not unit.PrimaryPart then
		return false, nil
	end

	-- Raycast parameters
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { unit }

	local origin = unit.PrimaryPart.Position
	local rayDirection = direction.Unit * COLLISION_CHECK_DISTANCE

	-- Cast ray ahead
	local result = workspace:Raycast(origin, rayDirection, raycastParams)

	if result then
		-- Hit something - check if it's a building or unit
		local hitInstance = result.Instance
		local hitBuilding = hitInstance:FindFirstAncestorOfClass("Model")

		if hitBuilding then
			local isBuilding = hitBuilding.Parent and hitBuilding.Parent.Name == "Buildings"
			local isUnit = hitBuilding.Parent and hitBuilding.Parent.Name == "Units"

			if isBuilding or isUnit then
				SteeringDebug:info(`Unit {unit.Name} detected obstacle ahead: {hitBuilding.Name}`)
				return true, result.Position
			end
		end
	end

	return false, nil
end

-- Calculate steering force to avoid obstacles
function LocalSteeringBehavior.calculateSteeringForce(unit: Model, desiredVelocity: Vector3): Vector3
	if not unit.PrimaryPart then
		return Vector3.new(0, 0, 0)
	end

	-- Get avoidance from nearby units
	local avoidanceVector = calculateAvoidanceVector(unit, desiredVelocity)

	-- Check for obstacles ahead
	local hasObstacle, obstaclePos = checkObstaclesAhead(unit, desiredVelocity)

	if hasObstacle and obstaclePos then
		-- Calculate perpendicular direction to steer around obstacle
		local toObstacle = obstaclePos - unit.PrimaryPart.Position
		local perpendicular = Vector3.new(-toObstacle.Z, 0, toObstacle.X).Unit
		avoidanceVector += perpendicular * 0.5
	end

	-- Normalize and scale avoidance vector
	if avoidanceVector.Magnitude > 0.1 then
		avoidanceVector = avoidanceVector.Unit * PUSH_FORCE
	end

	return avoidanceVector
end

-- Apply steering force to a unit's movement
function LocalSteeringBehavior.applySteeringToWaypoint(unit: Model, waypointPosition: Vector3): Vector3
	if not unit.PrimaryPart then
		return waypointPosition
	end

	-- Calculate desired direction
	local currentPos = unit.PrimaryPart.Position
	local desiredDirection = (waypointPosition - currentPos)

	if desiredDirection.Magnitude < 0.1 then
		return waypointPosition -- Already at waypoint
	end

	desiredDirection = desiredDirection.Unit

	-- Get steering force
	local steeringForce = LocalSteeringBehavior.calculateSteeringForce(unit, desiredDirection)

	-- Combine desired direction with steering
	local adjustedDirection = (desiredDirection + steeringForce)

	if adjustedDirection.Magnitude > 0.1 then
		adjustedDirection = adjustedDirection.Unit
	else
		return waypointPosition -- No adjustment needed
	end

	-- Calculate adjusted waypoint position
	local distanceToWaypoint = (waypointPosition - currentPos).Magnitude
	local adjustedWaypoint = currentPos + (adjustedDirection * math.min(distanceToWaypoint, 10))

	-- Keep Y coordinate the same (don't fly up)
	adjustedWaypoint = Vector3.new(adjustedWaypoint.X, waypointPosition.Y, adjustedWaypoint.Z)

	return adjustedWaypoint
end

-- Clean up block timer when unit stops moving
function LocalSteeringBehavior.clearBlockTimer(unit: Model)
	if blockTimers[unit] then
		blockTimers[unit] = nil
	end
end

-- Get configuration for debugging
function LocalSteeringBehavior.getConfig()
	return {
		avoidanceRadius = AVOIDANCE_RADIUS,
		collisionCheckDistance = COLLISION_CHECK_DISTANCE,
		pushForce = PUSH_FORCE,
		friendlyPushDelay = FRIENDLY_PUSH_DELAY,
	}
end

SteeringDebug:info("LocalSteeringBehavior loaded successfully")

return LocalSteeringBehavior
