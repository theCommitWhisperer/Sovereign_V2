--!strict
-- StudioCameraController: Main camera controller integrating all camera modules
-- Provides Studio-style camera controls for both desktop and mobile

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InputHandler = require(script.Parent.InputHandler)
local DesktopInput = require(script.Parent.DesktopInput)
local MobileInput = require(script.Parent.MobileInput)
local CameraRig = require(script.Parent.CameraRig)
local CameraAnimator = require(script.Parent.CameraAnimator)
local BoundsManager = require(script.Parent.BoundsManager)
local KeybindingsManager = require(script.Parent.KeybindingsManager)

local DebugManager = require(ReplicatedStorage.Shared.DebugManager)
local CameraDebug = DebugManager.createChannel("StudioCamera", true)

-- Camera mode
local CameraMode = {
	RTS = "RTS",
	King = "King",
}

local StudioCameraController = {}
StudioCameraController.__index = StudioCameraController

function StudioCameraController.new()
	local self = setmetatable({}, StudioCameraController)

	-- Core modules
	self.inputHandler = InputHandler.new()
	self.desktopInput = DesktopInput.new(self.inputHandler)
	self.mobileInput = MobileInput.new(self.inputHandler)
	self.cameraRig = CameraRig.new()
	self.animator = CameraAnimator.new(self.cameraRig)
	self.boundsManager = BoundsManager.new()

	-- State
	self.enabled = false
	self.currentMode = CameraMode.RTS
	self.kingModel = nil
	self.controlsModule = nil

	-- References
	self.player = Players.LocalPlayer
	self.camera = Workspace.CurrentCamera

	-- Connections
	self.connections = {}

	-- Setup input modules
	self.inputHandler:SetDesktopInput(self.desktopInput)
	self.inputHandler:SetMobileInput(self.mobileInput)

	-- Setup input event handler
	self.inputHandler:OnInputEvent(function(event)
		self:HandleInputEvent(event)
	end)

	-- Sync keybindings with desktop input
	self:SyncKeybindings()

	CameraDebug:info("StudioCameraController created")

	return self
end

function StudioCameraController:Initialize(startPosition: Vector3)
	if self.enabled then
		return
	end

	self.enabled = true

	-- Initialize camera rig
	self.cameraRig:Initialize(startPosition)

	-- Set camera to Scriptable
	self.camera.CameraType = Enum.CameraType.Scriptable

	-- Enable input
	self.inputHandler:Enable()

	-- Setup update loop
	table.insert(
		self.connections,
		RunService.RenderStepped:Connect(function(deltaTime)
			self:Update(deltaTime)
		end)
	)

	CameraDebug:info("StudioCameraController initialized", {
		startPosition = startPosition,
		isMobile = self.inputHandler:IsMobile(),
		isDesktop = self.inputHandler:IsDesktop(),
	})
end

function StudioCameraController:Update(deltaTime: number)
	if not self.enabled then
		return
	end

	if self.currentMode == CameraMode.RTS then
		-- Update animator (handles smooth transitions and inertia)
		self.animator:Update(deltaTime)

		-- Apply bounds constraints
		if self.boundsManager.enabled then
			local currentFocal = self.cameraRig:GetFocalPoint()
			local clampedFocal = self.boundsManager:SoftClampPosition(
				currentFocal,
				self.animator:GetDampingFactor()
			)
			if clampedFocal ~= currentFocal then
				self.cameraRig:SetFocalPoint(clampedFocal)
			end
		end

		-- Update camera transform
		self.cameraRig:UpdateCamera()

	elseif self.currentMode == CameraMode.King then
		-- King Mode: First-person camera (handled by Roblox's built-in system)
		-- Check if King still exists
		if not self.kingModel or not self.kingModel.Parent then
			CameraDebug:warn("King no longer exists, switching back to RTS mode")
			self:SwitchToRTS()
		end
	end
end

function StudioCameraController:HandleInputEvent(event)
	if not self.enabled or self.currentMode ~= CameraMode.RTS then
		return
	end

	if event.Type == "Pan" and event.IsActive and event.Delta then
		self.cameraRig:Pan(event.Delta.X, event.Delta.Y)
		-- Cancel animations on manual input
		self.animator:CancelAnimations()

	elseif event.Type == "Rotate" and event.IsActive and event.Delta then
		self.cameraRig:Rotate(event.Delta.X, event.Delta.Y)
		-- Cancel animations on manual input
		self.animator:CancelAnimations()

	elseif event.Type == "Zoom" and event.IsActive and event.ZoomDelta then
		self.cameraRig:Zoom(event.ZoomDelta)
		-- Cancel zoom animations
		self.animator:CancelAnimations("Focus")

	elseif event.Type == "Move" and event.IsActive and event.MoveDirection then
		self.cameraRig:Move(event.MoveDirection, 1 / 60) -- Approximate deltaTime
		-- Cancel animations on manual input
		self.animator:CancelAnimations()

	elseif event.Type == "Focus" and event.IsActive then
		-- Focus on current focal point (reset camera)
		self:FocusOnPoint(self.cameraRig:GetFocalPoint())
	end
end

function StudioCameraController:FocusOnPoint(position: Vector3, distance: number?)
	self.animator:AnimateFocusOn(position, distance)
end

function StudioCameraController:FocusOnPart(part: BasePart)
	local position = part.Position
	local size = part.Size
	local distance = math.max(size.X, size.Y, size.Z) * 2
	self:FocusOnPoint(position, distance)
end

function StudioCameraController:ResetCamera(position: Vector3?)
	if position then
		self.cameraRig:Reset(position)
	else
		self.cameraRig:Reset()
	end
	self.animator:CancelAnimations()
end

function StudioCameraController:SwitchToKing()
	if self.currentMode == CameraMode.King then
		return
	end

	-- Find King
	local character = self.player.Character
	if character and character:GetAttribute("IsKing") then
		self.kingModel = character
		self.currentMode = CameraMode.King

		-- Disable RTS input
		self.inputHandler:Disable()

		-- Enable character controls
		if not self.controlsModule then
			self.controlsModule = self.player.PlayerScripts:WaitForChild("PlayerModule"):WaitForChild("ControlModule")
		end
		if self.controlsModule then
			self.controlsModule:Enable()
		end

		-- Switch to first-person camera
		self.player.CameraMode = Enum.CameraMode.LockFirstPerson
		self.player.CameraMaxZoomDistance = 0.5
		self.player.CameraMinZoomDistance = 0.5

		CameraDebug:info("Switched to King mode")

		-- Fire event to notify HUD
		local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
		local gameEvent = RemoteEvents:WaitForChild("GameEvent")
		gameEvent:FireServer("CameraModeChanged", CameraMode.King)
	else
		CameraDebug:warn("Cannot switch to King mode - King not found")
	end
end

function StudioCameraController:SwitchToRTS()
	if self.currentMode == CameraMode.RTS then
		return
	end

	self.currentMode = CameraMode.RTS

	-- Disable character controls
	if self.controlsModule then
		self.controlsModule:Disable()
	end

	-- Re-enable RTS input
	self.inputHandler:Enable()

	-- Switch back to scriptable camera
	self.camera.CameraType = Enum.CameraType.Scriptable
	self.player.CameraMode = Enum.CameraMode.Classic

	CameraDebug:info("Switched to RTS mode")

	-- Fire event to notify HUD
	local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
	local gameEvent = RemoteEvents:WaitForChild("GameEvent")
	gameEvent:FireServer("CameraModeChanged", CameraMode.RTS)
end

function StudioCameraController:ToggleCameraMode()
	if self.currentMode == CameraMode.RTS then
		self:SwitchToKing()
	else
		self:SwitchToRTS()
	end
end

function StudioCameraController:GetCurrentMode(): string
	return self.currentMode
end

function StudioCameraController:SetBounds(bounds)
	self.boundsManager:SetBounds(bounds)
	self.boundsManager:SetEnabled(true)
end

function StudioCameraController:SetBoundsFromPart(part: BasePart, padding: number?)
	self.boundsManager:SetBoundsFromPart(part, padding)
	self.boundsManager:SetEnabled(true)
end

function StudioCameraController:ClearBounds()
	self.boundsManager:ClearBounds()
	self.boundsManager:SetEnabled(false)
end

function StudioCameraController:SyncKeybindings()
	-- Sync keybindings from KeybindingsManager to DesktopInput
	local keybindings = KeybindingsManager.GetAllKeybindings()
	for action, keyCode in pairs(keybindings) do
		if action ~= "ResetCamera" and action ~= "ToggleCameraMode" then
			self.desktopInput:SetKeybinding(action, keyCode)
		end
	end

	-- Listen for keybinding changes
	for _, action in ipairs(KeybindingsManager.GetAllActions()) do
		KeybindingsManager.OnKeybindingChanged(action, function(keyCode)
			if action ~= "ResetCamera" and action ~= "ToggleCameraMode" then
				self.desktopInput:SetKeybinding(action, keyCode)
			end
		end)
	end
end

function StudioCameraController:Disable()
	if not self.enabled then
		return
	end

	self.enabled = false

	-- Disable input
	self.inputHandler:Disable()

	-- Disconnect all connections
	for _, connection in ipairs(self.connections) do
		connection:Disconnect()
	end
	self.connections = {}

	CameraDebug:info("StudioCameraController disabled")
end

function StudioCameraController:Destroy()
	self:Disable()

	-- Cleanup modules
	self.inputHandler:Destroy()
	self.desktopInput:Destroy()
	self.mobileInput:Destroy()
	self.animator:Destroy()

	CameraDebug:info("StudioCameraController destroyed")
end

return StudioCameraController
