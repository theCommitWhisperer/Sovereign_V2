--!strict
-- DesktopInput: Handles mouse and keyboard input for camera control (RTS-style)
-- Right-click drag: Rotate camera (yaw and pitch)
-- Middle-click drag: Pan camera
-- Mouse wheel: Zoom
-- WASD: Pan camera
-- Q/E: Rotate around vertical axis
-- F: Focus on target

local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

export type KeybindingsConfig = {
	PanUp: Enum.KeyCode,
	PanDown: Enum.KeyCode,
	PanLeft: Enum.KeyCode,
	PanRight: Enum.KeyCode,
	RotateLeft: Enum.KeyCode,
	RotateRight: Enum.KeyCode,
	Focus: Enum.KeyCode,
}

local DEFAULT_KEYBINDINGS: KeybindingsConfig = {
	PanUp = Enum.KeyCode.W,
	PanDown = Enum.KeyCode.S,
	PanLeft = Enum.KeyCode.A,
	PanRight = Enum.KeyCode.D,
	RotateLeft = Enum.KeyCode.Q,
	RotateRight = Enum.KeyCode.E,
	Focus = Enum.KeyCode.F,
}

local DesktopInput = {}
DesktopInput.__index = DesktopInput

function DesktopInput.new(inputHandler)
	local self = setmetatable({}, DesktopInput)

	self.inputHandler = inputHandler
	self.enabled = false

	-- Keybindings (can be customized)
	self.keybindings = table.clone(DEFAULT_KEYBINDINGS)

	-- Mouse state
	self.isRightClickRotating = false
	self.isMiddleClickPanning = false
	self.lastMousePosition = Vector2.zero

	-- Edge scrolling
	self.edgeScrollEnabled = true
	self.edgeScrollSize = 50 -- pixels from edge
	self.edgeScrollSpeed = 0.6

	-- Keyboard movement speed
	self.keyboardMoveSpeed = 1.0

	-- Connections
	self.connections = {}

	return self
end

function DesktopInput:Enable()
	if self.enabled then
		return
	end
	self.enabled = true

	-- Input began (mouse buttons)
	table.insert(
		self.connections,
		UserInputService.InputBegan:Connect(function(input, gameProcessed)
			if not self.enabled then
				return
			end

			-- Right-click for rotation (yaw and pitch) - works even if UI is focused
			if input.UserInputType == Enum.UserInputType.MouseButton2 then
				self.isRightClickRotating = true
				self.lastMousePosition = UserInputService:GetMouseLocation()
				UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition

				self.inputHandler:FireEvent({
					Type = "Rotate",
					IsActive = true,
					Delta = Vector2.zero,
				})
				return
			end

			if gameProcessed then
				return
			end

			-- Middle-click for panning
			if input.UserInputType == Enum.UserInputType.MouseButton3 then
				self.isMiddleClickPanning = true
				self.lastMousePosition = UserInputService:GetMouseLocation()

				self.inputHandler:FireEvent({
					Type = "Pan",
					IsActive = true,
					Delta = Vector2.zero,
				})
			end

			-- Focus key (F)
			if input.KeyCode == self.keybindings.Focus then
				self.inputHandler:FireEvent({
					Type = "Focus",
					IsActive = true,
				})
			end
		end)
	)

	-- Input ended (mouse buttons)
	table.insert(
		self.connections,
		UserInputService.InputEnded:Connect(function(input)
			if not self.enabled then
				return
			end

			-- Release right-click rotation
			if input.UserInputType == Enum.UserInputType.MouseButton2 then
				self.isRightClickRotating = false
				UserInputService.MouseBehavior = Enum.MouseBehavior.Default

				self.inputHandler:FireEvent({
					Type = "Rotate",
					IsActive = false,
				})
			end

			-- Release middle-click panning
			if input.UserInputType == Enum.UserInputType.MouseButton3 then
				self.isMiddleClickPanning = false

				self.inputHandler:FireEvent({
					Type = "Pan",
					IsActive = false,
				})
			end
		end)
	)

	-- Mouse wheel zoom
	table.insert(
		self.connections,
		UserInputService.InputChanged:Connect(function(input, gameProcessed)
			if not self.enabled or gameProcessed then
				return
			end

			if input.UserInputType == Enum.UserInputType.MouseWheel then
				self.inputHandler:FireEvent({
					Type = "Zoom",
					ZoomDelta = -input.Position.Z, -- Inverted for natural scrolling
					IsActive = true,
				})
			end
		end)
	)

	-- RenderStepped for continuous input (mouse drag, keyboard, edge scroll)
	table.insert(
		self.connections,
		RunService.RenderStepped:Connect(function(deltaTime)
			if not self.enabled then
				return
			end

			-- Handle right-click rotation drag (yaw and pitch)
			if self.isRightClickRotating then
				local mouseDelta = UserInputService:GetMouseDelta()
				if mouseDelta.Magnitude > 0 then
					self.inputHandler:FireEvent({
						Type = "Rotate",
						Delta = mouseDelta,
						IsActive = true,
					})
				end
			end

			-- Handle middle-click pan drag
			if self.isMiddleClickPanning then
				local currentMousePosition = UserInputService:GetMouseLocation()
				local delta = currentMousePosition - self.lastMousePosition
				self.lastMousePosition = currentMousePosition

				if delta.Magnitude > 0 then
					self.inputHandler:FireEvent({
						Type = "Pan",
						Delta = delta,
						IsActive = true,
					})
				end
			end

			-- Keyboard movement (WASD)
			local moveDirection = Vector3.zero
			if UserInputService:IsKeyDown(self.keybindings.PanUp) then
				moveDirection = moveDirection + Vector3.new(0, 0, -1)
			end
			if UserInputService:IsKeyDown(self.keybindings.PanDown) then
				moveDirection = moveDirection + Vector3.new(0, 0, 1)
			end
			if UserInputService:IsKeyDown(self.keybindings.PanLeft) then
				moveDirection = moveDirection + Vector3.new(-1, 0, 0)
			end
			if UserInputService:IsKeyDown(self.keybindings.PanRight) then
				moveDirection = moveDirection + Vector3.new(1, 0, 0)
			end

			-- Keyboard rotation (Q/E)
			local rotateDirection = 0
			if UserInputService:IsKeyDown(self.keybindings.RotateLeft) then
				rotateDirection = rotateDirection + 1
			end
			if UserInputService:IsKeyDown(self.keybindings.RotateRight) then
				rotateDirection = rotateDirection - 1
			end

			if rotateDirection ~= 0 then
				self.inputHandler:FireEvent({
					Type = "Rotate",
					Delta = Vector2.new(rotateDirection * 100 * deltaTime, 0), -- Convert to mouse-like delta
					IsActive = true,
				})
			end

			-- Edge scrolling
			if self.edgeScrollEnabled then
				local mouseLocation = UserInputService:GetMouseLocation()
				local camera = workspace.CurrentCamera
				if camera then
					local screenSize = camera.ViewportSize
					local edgeMove = Vector3.zero

					if mouseLocation.X < self.edgeScrollSize then
						edgeMove = edgeMove + Vector3.new(-1, 0, 0)
					elseif mouseLocation.X > screenSize.X - self.edgeScrollSize then
						edgeMove = edgeMove + Vector3.new(1, 0, 0)
					end

					if mouseLocation.Y < self.edgeScrollSize then
						edgeMove = edgeMove + Vector3.new(0, 0, -1)
					elseif mouseLocation.Y > screenSize.Y - self.edgeScrollSize then
						edgeMove = edgeMove + Vector3.new(0, 0, 1)
					end

					if edgeMove.Magnitude > 0 then
						moveDirection = moveDirection + (edgeMove * self.edgeScrollSpeed)
					end
				end
			end

			-- Fire movement event if there's any movement
			if moveDirection.Magnitude > 0 then
				self.inputHandler:FireEvent({
					Type = "Move",
					MoveDirection = moveDirection,
					IsActive = true,
				})
			end
		end)
	)
end

function DesktopInput:Disable()
	if not self.enabled then
		return
	end
	self.enabled = false

	-- Restore mouse behavior
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default

	-- Disconnect all connections
	for _, connection in ipairs(self.connections) do
		connection:Disconnect()
	end
	self.connections = {}

	-- Reset state
	self.isRightClickRotating = false
	self.isMiddleClickPanning = false
end

function DesktopInput:SetKeybinding(action: string, keyCode: Enum.KeyCode)
	if self.keybindings[action] then
		self.keybindings[action] = keyCode
	end
end

function DesktopInput:GetKeybinding(action: string): Enum.KeyCode?
	return self.keybindings[action]
end

function DesktopInput:GetAllKeybindings(): KeybindingsConfig
	return table.clone(self.keybindings)
end

function DesktopInput:SetEdgeScrollEnabled(enabled: boolean)
	self.edgeScrollEnabled = enabled
end

function DesktopInput:Destroy()
	self:Disable()
end

return DesktopInput
