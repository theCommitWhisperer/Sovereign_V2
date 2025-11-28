--!strict
-- StanceController: Handles client-side UI and commands for unit stances.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)
local StanceDebug = DebugManager.createChannel("Stance", false)

local SelectionManager
local GameEvent

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local StanceController = {}

-- Finds the appropriate remote event reference.
local function setupRemotes()
	local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
	GameEvent = RemoteEvents:WaitForChild("GameEvent")
end

local function onStanceButtonClicked(stanceName: string)
	if not SelectionManager then
		return
	end

	local selectedUnits = SelectionManager.getSelectedUnits()
	if #selectedUnits == 0 then
		return
	end

	local unitIDs: { string } = {}
	for _, unit in selectedUnits do
		-- Use the Model.Name, which serves as the UnitId in the V2 UnitManager
		table.insert(unitIDs, unit.Name)
	end

	StanceDebug:info(`Sending SetStance command: {stanceName}`, { UnitCount = #unitIDs })

	if GameEvent then
		GameEvent:FireServer("SetStance", {
			UnitIDs = unitIDs,
			Stance = stanceName,
		})
	end
end

function StanceController.init()
	setupRemotes()

	task.spawn(function()
		-- Load SelectionManager from the refactored path in V2
		local ClientScripts = player:WaitForChild("PlayerScripts"):WaitForChild("Client")
		SelectionManager = require(ClientScripts.Selection.SelectionManager)

		local hudGui = playerGui:WaitForChild("HUDGui", 20)
		if not hudGui then
			return
		end

		-- Hook up to the React-rendered buttons in HUD.luau
		-- Assumes the buttons are direct descendants of a frame named "UnitControlsFrame"
		local unitControlsFrame = hudGui:FindFirstChild("SovereignApp", true)
			and hudGui.SovereignApp:FindFirstChild("UnitControlsFrame", true)

		if not unitControlsFrame then
			StanceDebug:warn("Could not find UnitControlsFrame in HUD.")
			return
		end

		-- Connect handlers to the buttons
		unitControlsFrame:WaitForChild("AggressiveStanceButton").MouseButton1Click:Connect(function()
			onStanceButtonClicked("Aggressive")
		end)
		unitControlsFrame:WaitForChild("DefensiveStanceButton").MouseButton1Click:Connect(function()
			onStanceButtonClicked("Defensive")
		end)
		unitControlsFrame:WaitForChild("HoldPositionStanceButton").MouseButton1Click:Connect(function()
			onStanceButtonClicked("Hold")
		end)

		StanceDebug:info("Initialized.")
	end)
end

return StanceController
