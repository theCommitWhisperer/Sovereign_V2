--!strict
-- CameraController: Studio-style hybrid camera system with RTS and King modes
-- Press Tab to toggle between modes
-- Now using modular StudioCameraController for better mobile support

local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

local DebugManager = require(ReplicatedStorage.Shared.DebugManager)
local CameraDebug = DebugManager.createChannel("Camera", false)

-- Import the new Studio Camera Controller
local StudioCameraController = require(script.Parent.Camera.StudioCameraController)

-- Wait for game to start
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local gameEvent = RemoteEvents:WaitForChild("GameEvent")

-- Create camera controller instance
local cameraController = nil
local cameraEnabled = false

-- Initialize camera when game starts
gameEvent.OnClientEvent:Connect(function(action, data)
	if action == "GameStarted" and not cameraEnabled then
		cameraEnabled = true

		-- Wait for character
		local character = player.Character or player.CharacterAdded:Wait()
		local humanoidRootPart = character:WaitForChild("HumanoidRootPart") :: BasePart

		-- Create and initialize the new camera controller
		cameraController = StudioCameraController.new()

		-- Store spawn position and start camera above it
		local spawnPosition = humanoidRootPart.Position
		cameraController:Initialize(spawnPosition)

		CameraDebug:info("Camera system initialized with StudioCameraController", {
			spawnPos = spawnPosition,
			isMobile = cameraController.inputHandler:IsMobile(),
			isDesktop = cameraController.inputHandler:IsDesktop(),
		})

		-- Optional: Set up camera bounds (if you have a playable area defined)
		-- Example: cameraController:SetBoundsFromPart(workspace.MapBounds)
	end
end)

-- Handle Tab key for mode switching
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if input.KeyCode == Enum.KeyCode.Tab and cameraEnabled and cameraController then
		CameraDebug:info("Tab pressed, switching camera mode")
		cameraController:ToggleCameraMode()
		return
	end

	-- Handle Reset Camera (Home key)
	if input.KeyCode == Enum.KeyCode.Home and cameraEnabled and cameraController then
		CameraDebug:info("Home pressed, resetting camera")
		local character = player.Character
		if character then
			local humanoidRootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart
			if humanoidRootPart then
				cameraController:ResetCamera(humanoidRootPart.Position)
			end
		end
	end
end)

CameraDebug:info("Camera controller loaded with Studio-style controls")
