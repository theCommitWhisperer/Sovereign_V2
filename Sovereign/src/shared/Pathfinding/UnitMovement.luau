--!strict
-- UnitMovement: Controls unit movement along paths with smooth transitions
-- Handles path following, rotation, and speed adjustments

local RunService = game:GetService("RunService")

local UnitMovement = {}
UnitMovement.__index = UnitMovement

export type PathPoint = {
	x: number,
	z: number,
}

export type MovementConfig = {
	speed: number, -- Studs per second
	rotationSpeed: number?, -- Degrees per second (default: 360)
	arrivalThreshold: number?, -- Distance to consider "arrived" (default: 0.5)
	waypointThreshold: number?, -- Distance to move to next waypoint (default: 2)
	smoothRotation: boolean?, -- Whether to smoothly rotate (default: true)
}

export type UnitMover = {
	unit: Model,
	config: MovementConfig,
	currentPath: { PathPoint }?,
	currentWaypointIndex: number,
	isMoving: boolean,
	connection: RBXScriptConnection?,
	onPathComplete: (() -> ())?,
	onWaypointReached: ((number) -> ())?,
	targetPosition: Vector3?,
}

-- Create a new unit mover
function UnitMovement.new(unit: Model, config: MovementConfig): UnitMover
	local self = setmetatable({}, UnitMovement) :: any

	self.unit = unit
	self.config = {
		speed = config.speed,
		rotationSpeed = config.rotationSpeed or 360,
		arrivalThreshold = config.arrivalThreshold or 0.5,
		waypointThreshold = config.waypointThreshold or 2,
		smoothRotation = if config.smoothRotation == nil then true else config.smoothRotation,
	}
	self.currentPath = nil
	self.currentWaypointIndex = 1
	self.isMoving = false
	self.connection = nil
	self.onPathComplete = nil
	self.onWaypointReached = nil
	self.targetPosition = nil

	return self :: UnitMover
end

-- Start following a path
function UnitMovement.followPath(self: UnitMover, path: { PathPoint })
	self:stop()

	if #path == 0 then
		if self.onPathComplete then
			self.onPathComplete()
		end
		return
	end

	self.currentPath = path
	self.currentWaypointIndex = 1
	self.isMoving = true

	-- Start movement loop
	self.connection = RunService.Heartbeat:Connect(function(deltaTime)
		if not self.isMoving or not self.currentPath then
			return
		end

		self:updateMovement(deltaTime)
	end)
end

-- Update unit movement each frame
function UnitMovement.updateMovement(self: UnitMover, deltaTime: number)
	if not self.currentPath or self.currentWaypointIndex > #self.currentPath then
		self:stop()
		if self.onPathComplete then
			self.onPathComplete()
		end
		return
	end

	local primaryPart = self.unit.PrimaryPart or self.unit:FindFirstChild("HumanoidRootPart")
	if not primaryPart or not primaryPart:IsA("BasePart") then
		warn("Unit missing PrimaryPart or HumanoidRootPart")
		self:stop()
		return
	end

	local currentPos = primaryPart.Position
	local waypoint = self.currentPath[self.currentWaypointIndex]
	local targetPos = Vector3.new(waypoint.x, currentPos.Y, waypoint.z)

	-- Check if we've reached the current waypoint
	local distanceToWaypoint = (Vector3.new(targetPos.X, currentPos.Y, targetPos.Z) - currentPos).Magnitude

	if distanceToWaypoint < self.config.waypointThreshold then
		-- Move to next waypoint
		if self.onWaypointReached then
			self.onWaypointReached(self.currentWaypointIndex)
		end

		self.currentWaypointIndex += 1

		if self.currentWaypointIndex > #self.currentPath then
			self:stop()
			if self.onPathComplete then
				self.onPathComplete()
			end
			return
		end

		waypoint = self.currentPath[self.currentWaypointIndex]
		targetPos = Vector3.new(waypoint.x, currentPos.Y, waypoint.z)
	end

	-- Calculate movement direction
	local direction = (targetPos - currentPos).Unit
	local moveDistance = math.min(
		self.config.speed * deltaTime,
		(targetPos - currentPos).Magnitude
	)

	-- Move the unit
	local newPosition = currentPos + direction * moveDistance

	-- Use PivotTo for smooth movement
	local currentCFrame = primaryPart.CFrame
	local targetCFrame = CFrame.new(newPosition)

	-- Handle rotation
	if self.config.smoothRotation then
		-- Smoothly rotate towards movement direction
		local lookDirection = Vector3.new(direction.X, 0, direction.Z)
		if lookDirection.Magnitude > 0.01 then
			local targetLook = CFrame.lookAt(newPosition, newPosition + lookDirection)
			local maxRotation = math.rad(self.config.rotationSpeed * deltaTime)

			-- Interpolate rotation
			local currentLook = CFrame.new(newPosition) * (currentCFrame - currentCFrame.Position)
			local angle = math.acos(math.clamp(currentLook.LookVector:Dot(targetLook.LookVector), -1, 1))

			if angle > 0.01 then
				local t = math.min(1, maxRotation / angle)
				targetCFrame = currentLook:Lerp(targetLook, t)
			else
				targetCFrame = targetLook
			end
		else
			targetCFrame = currentCFrame - currentCFrame.Position + newPosition
		end
	else
		-- Instant rotation
		local lookDirection = Vector3.new(direction.X, 0, direction.Z)
		if lookDirection.Magnitude > 0.01 then
			targetCFrame = CFrame.lookAt(newPosition, newPosition + lookDirection)
		else
			targetCFrame = CFrame.new(newPosition)
		end
	end

	-- Apply the new CFrame
	self.unit:PivotTo(targetCFrame)
end

-- Stop movement
function UnitMovement.stop(self: UnitMover)
	self.isMoving = false
	if self.connection then
		self.connection:Disconnect()
		self.connection = nil
	end
	self.currentPath = nil
	self.currentWaypointIndex = 1
end

-- Pause movement
function UnitMovement.pause(self: UnitMover)
	self.isMoving = false
end

-- Resume movement
function UnitMovement.resume(self: UnitMover)
	if self.currentPath and self.currentWaypointIndex <= #self.currentPath then
		self.isMoving = true
	end
end

-- Check if unit is currently moving
function UnitMovement.getIsMoving(self: UnitMover): boolean
	return self.isMoving
end

-- Get current progress (0-1)
function UnitMovement.getProgress(self: UnitMover): number
	if not self.currentPath or #self.currentPath == 0 then
		return 0
	end

	return (self.currentWaypointIndex - 1) / #self.currentPath
end

-- Destroy the mover and clean up
function UnitMovement.destroy(self: UnitMover)
	self:stop()
	self.onPathComplete = nil
	self.onWaypointReached = nil
end

return UnitMovement
