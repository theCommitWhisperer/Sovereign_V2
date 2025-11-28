--!strict
-- MobileInput: Handles touch gestures for mobile camera control
-- One finger drag: Pan camera
-- Two finger pinch: Zoom in/out
-- Two finger rotate: Rotate camera around focal point
-- Two finger vertical drag: Adjust pitch angle
-- Double tap: Focus/reset camera

local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local MobileInput = {}
MobileInput.__index = MobileInput

function MobileInput.new(inputHandler)
	local self = setmetatable({}, MobileInput)

	self.inputHandler = inputHandler
	self.enabled = false

	-- Touch tracking
	self.activeTouches = {} -- [inputObject] = {Position: Vector3, StartPosition: Vector3, StartTime: number}
	self.lastTouchCount = 0

	-- Gesture state
	self.initialPinchDistance = 0
	self.lastPinchDistance = 0
	self.initialRotationAngle = 0
	self.lastRotationAngle = 0
	self.lastTwoFingerCenter = Vector2.zero

	-- Double tap detection
	self.lastTapTime = 0
	self.lastTapPosition = Vector2.zero
	self.doubleTapThreshold = 0.3 -- seconds
	self.doubleTapDistanceThreshold = 50 -- pixels

	-- UI buttons (optional fallback controls)
	self.showUIButtons = true
	self.uiButtons = nil

	-- Sensitivity
	self.panSensitivity = 1.0
	self.zoomSensitivity = 0.05
	self.rotateSensitivity = 0.003
	self.pitchSensitivity = 0.002

	-- Connections
	self.connections = {}

	return self
end

function MobileInput:Enable()
	if self.enabled then
		return
	end
	self.enabled = true

	-- Touch began
	table.insert(
		self.connections,
		UserInputService.TouchStarted:Connect(function(inputObject, gameProcessed)
			if not self.enabled or gameProcessed then
				return
			end

			-- Track this touch
			self.activeTouches[inputObject] = {
				Position = inputObject.Position,
				StartPosition = inputObject.Position,
				StartTime = tick(),
			}

			local touchCount = self:GetTouchCount()

			-- Handle single tap for double-tap detection
			if touchCount == 1 then
				local currentTime = tick()
				local tapPosition = Vector2.new(inputObject.Position.X, inputObject.Position.Y)

				-- Check for double tap
				if
					currentTime - self.lastTapTime < self.doubleTapThreshold
					and (tapPosition - self.lastTapPosition).Magnitude < self.doubleTapDistanceThreshold
				then
					-- Double tap detected
					self.inputHandler:FireEvent({
						Type = "Focus",
						Position = tapPosition,
						IsActive = true,
					})
					self.lastTapTime = 0 -- Reset to prevent triple tap
				else
					self.lastTapTime = currentTime
					self.lastTapPosition = tapPosition
				end
			end

			-- Initialize two-finger gestures
			if touchCount == 2 then
				local touches = self:GetTouchArray()
				if #touches == 2 then
					local pos1 = Vector2.new(touches[1].Position.X, touches[1].Position.Y)
					local pos2 = Vector2.new(touches[2].Position.X, touches[2].Position.Y)

					-- Initialize pinch
					self.initialPinchDistance = (pos1 - pos2).Magnitude
					self.lastPinchDistance = self.initialPinchDistance

					-- Initialize rotation
					local delta = pos2 - pos1
					self.initialRotationAngle = math.atan2(delta.Y, delta.X)
					self.lastRotationAngle = self.initialRotationAngle

					-- Initialize two-finger center
					self.lastTwoFingerCenter = (pos1 + pos2) / 2
				end
			end
		end)
	)

	-- Touch ended
	table.insert(
		self.connections,
		UserInputService.TouchEnded:Connect(function(inputObject, gameProcessed)
			if not self.enabled then
				return
			end

			-- Remove this touch
			self.activeTouches[inputObject] = nil

			local touchCount = self:GetTouchCount()

			-- Reset gesture state when fingers are lifted
			if touchCount < 2 then
				self.initialPinchDistance = 0
				self.lastPinchDistance = 0
				self.initialRotationAngle = 0
				self.lastRotationAngle = 0
			end
		end)
	)

	-- RenderStepped for continuous gesture processing
	table.insert(
		self.connections,
		RunService.RenderStepped:Connect(function(deltaTime)
			if not self.enabled then
				return
			end

			local touchCount = self:GetTouchCount()

			-- One-finger pan
			if touchCount == 1 then
				local touches = self:GetTouchArray()
				if #touches == 1 then
					local touch = touches[1]
					local currentPos = Vector2.new(touch.Position.X, touch.Position.Y)
					local lastPos = Vector2.new(
						self.activeTouches[touches[1]].Position.X,
						self.activeTouches[touches[1]].Position.Y
					)
					local delta = currentPos - lastPos

					if delta.Magnitude > 0 then
						self.inputHandler:FireEvent({
							Type = "Pan",
							Delta = delta * self.panSensitivity,
							IsActive = true,
						})
					end

					-- Update stored position
					self.activeTouches[touches[1]].Position = touch.Position
				end
			end

			-- Two-finger gestures
			if touchCount == 2 then
				local touches = self:GetTouchArray()
				if #touches == 2 then
					local pos1 = Vector2.new(touches[1].Position.X, touches[1].Position.Y)
					local pos2 = Vector2.new(touches[2].Position.X, touches[2].Position.Y)

					-- Pinch zoom
					local currentDistance = (pos1 - pos2).Magnitude
					if self.lastPinchDistance > 0 then
						local pinchDelta = currentDistance - self.lastPinchDistance
						if math.abs(pinchDelta) > 1 then
							-- Positive = zoom out, Negative = zoom in
							self.inputHandler:FireEvent({
								Type = "Zoom",
								ZoomDelta = -pinchDelta * self.zoomSensitivity, -- Inverted for natural feel
								IsActive = true,
							})
						end
					end
					self.lastPinchDistance = currentDistance

					-- Two-finger rotation (horizontal rotation around focal point)
					local delta = pos2 - pos1
					local currentAngle = math.atan2(delta.Y, delta.X)
					if self.lastRotationAngle then
						local angleDelta = currentAngle - self.lastRotationAngle
						-- Normalize angle delta to [-pi, pi]
						if angleDelta > math.pi then
							angleDelta = angleDelta - 2 * math.pi
						elseif angleDelta < -math.pi then
							angleDelta = angleDelta + 2 * math.pi
						end

						if math.abs(angleDelta) > 0.01 then
							-- Convert angle delta to mouse-like horizontal delta
							self.inputHandler:FireEvent({
								Type = "Rotate",
								Delta = Vector2.new(-angleDelta * 100, 0), -- Horizontal rotation only
								IsActive = true,
							})
						end
					end
					self.lastRotationAngle = currentAngle

					-- Two-finger vertical drag for pitch adjustment
					local currentCenter = (pos1 + pos2) / 2
					if self.lastTwoFingerCenter then
						local verticalDelta = currentCenter.Y - self.lastTwoFingerCenter.Y
						if math.abs(verticalDelta) > 2 then
							-- Vertical movement adjusts pitch
							self.inputHandler:FireEvent({
								Type = "Rotate",
								Delta = Vector2.new(0, verticalDelta * self.pitchSensitivity * 100),
								IsActive = true,
							})
						end
					end
					self.lastTwoFingerCenter = currentCenter

					-- Update stored positions
					self.activeTouches[touches[1]].Position = touches[1].Position
					self.activeTouches[touches[2]].Position = touches[2].Position
				end
			end

			self.lastTouchCount = touchCount
		end)
	)
end

function MobileInput:Disable()
	if not self.enabled then
		return
	end
	self.enabled = false

	-- Disconnect all connections
	for _, connection in ipairs(self.connections) do
		connection:Disconnect()
	end
	self.connections = {}

	-- Reset state
	self.activeTouches = {}
	self.lastTouchCount = 0
end

function MobileInput:GetTouchCount(): number
	local count = 0
	for _ in pairs(self.activeTouches) do
		count = count + 1
	end
	return count
end

function MobileInput:GetTouchArray(): { any }
	local touches = {}
	for inputObject, _ in pairs(self.activeTouches) do
		table.insert(touches, inputObject)
	end
	return touches
end

function MobileInput:SetPanSensitivity(sensitivity: number)
	self.panSensitivity = sensitivity
end

function MobileInput:SetZoomSensitivity(sensitivity: number)
	self.zoomSensitivity = sensitivity
end

function MobileInput:SetRotateSensitivity(sensitivity: number)
	self.rotateSensitivity = sensitivity
end

function MobileInput:SetPitchSensitivity(sensitivity: number)
	self.pitchSensitivity = sensitivity
end

function MobileInput:Destroy()
	self:Disable()
end

return MobileInput
