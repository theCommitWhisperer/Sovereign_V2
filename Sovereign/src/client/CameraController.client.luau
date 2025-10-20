--!strict
-- CameraController: Sets up RTS-style camera controls

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local DebugManager = require(ReplicatedStorage.Shared.DebugManager)
local CameraDebug = DebugManager.createChannel("Camera", false)

-- Wait for game to start
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local gameEvent = RemoteEvents:WaitForChild("GameEvent")

local cameraEnabled = false

-- Camera settings
local CAMERA_HEIGHT = 50
local CAMERA_ANGLE = 60 -- degrees from horizontal
local CAMERA_DISTANCE = 40
local PAN_SPEED = 0.5
local ZOOM_SPEED = 5
local MIN_HEIGHT = 20
local MAX_HEIGHT = 100

-- Camera state
local cameraTarget = Vector3.new(0, 0, 0)
local currentHeight = CAMERA_HEIGHT
local isPanning = false
local lastMousePosition = Vector2.new()

-- Initialize camera when game starts
gameEvent.OnClientEvent:Connect(function(action, data)
	if action == "GameStarted" and not cameraEnabled then
		cameraEnabled = true

		-- Wait for character
		local character = player.Character or player.CharacterAdded:Wait()
		local humanoidRootPart = character:WaitForChild("HumanoidRootPart") :: BasePart

		-- Set camera to Scriptable
		camera.CameraType = Enum.CameraType.Scriptable

		-- Initialize camera position
		cameraTarget = humanoidRootPart.Position
		camera.CFrame = CFrame.new(cameraTarget + Vector3.new(0, currentHeight, CAMERA_DISTANCE), cameraTarget)

		CameraDebug:info("RTS camera initialized")
	end
end)

-- Handle mouse input for panning
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if not cameraEnabled or gameProcessed then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton3 then -- Middle mouse
		isPanning = true
		lastMousePosition = UserInputService:GetMouseLocation()
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if not cameraEnabled then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton3 then
		isPanning = false
	end
end)

-- Handle zoom with mouse wheel
UserInputService.InputChanged:Connect(function(input, gameProcessed)
	if not cameraEnabled or gameProcessed then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseWheel then
		currentHeight = math.clamp(currentHeight - input.Position.Z * ZOOM_SPEED, MIN_HEIGHT, MAX_HEIGHT)
	end
end)

-- Update camera every frame
RunService.RenderStepped:Connect(function(deltaTime)
	if not cameraEnabled then
		return
	end

	-- Pan camera if middle mouse is held
	if isPanning then
		local currentMousePosition = UserInputService:GetMouseLocation()
		local delta = currentMousePosition - lastMousePosition
		lastMousePosition = currentMousePosition

		-- Convert screen space movement to world space
		local right = camera.CFrame.RightVector
		local forward = (camera.CFrame.LookVector * Vector3.new(1, 0, 1)).Unit

		cameraTarget = cameraTarget - (right * delta.X * PAN_SPEED) + (forward * delta.Y * PAN_SPEED)
	end

	-- WASD camera movement
	local moveDirection = Vector3.new()
	if UserInputService:IsKeyDown(Enum.KeyCode.W) then
		moveDirection = moveDirection + Vector3.new(0, 0, -1)
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.S) then
		moveDirection = moveDirection + Vector3.new(0, 0, 1)
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.A) then
		moveDirection = moveDirection + Vector3.new(-1, 0, 0)
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.D) then
		moveDirection = moveDirection + Vector3.new(1, 0, 0)
	end

	if moveDirection.Magnitude > 0 then
		cameraTarget = cameraTarget + (moveDirection.Unit * deltaTime * 50)
	end

	-- Calculate camera position based on angle and height
	local angleRad = math.rad(CAMERA_ANGLE)
	local offset = Vector3.new(0, currentHeight, currentHeight / math.tan(angleRad))

	camera.CFrame = CFrame.new(cameraTarget + offset, cameraTarget)
end)
