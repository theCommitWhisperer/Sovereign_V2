--!strict
-- HUDInput: the InputBegan handler HUD.luau ran unconditionally
-- (HUD:setupBuildingSelection), pulled out so it can be started/stopped as a
-- unit and gated on Platform.pointer. A touch device has no keyboard for
-- Ctrl+U/Escape and no mouse for the click-a-building raycast, so it must not
-- pay for this connection at all -- see AdaptiveHUD.luau for the gating.
--
-- Plain module, not a React component: input handling has no render output,
-- and Platform.luau/HUDStore.luau are already plain modules for the same
-- "this isn't UI, it's wiring" reason.
--
-- start()/stop() are idempotent so a caller that races Platform.onChanged
-- (gamepad plugged in mid-toggle, etc.) can't double-connect or double-warn on
-- an already-stopped handler.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameData = require(ReplicatedStorage.Shared.GameData)
local HUDStore = require(script.Parent.Parent.state.HUDStore)

local HUDInput = {}

local connection: RBXScriptConnection? = nil

local function handleLeftClick()
	local player = Players.LocalPlayer
	local mousePosition = UserInputService:GetMouseLocation()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local ray = camera:ScreenPointToRay(mousePosition.X, mousePosition.Y)

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	local filterList: { Instance } = {}
	if player.Character then
		table.insert(filterList, player.Character)
	end
	local terrain = Workspace:FindFirstChild("Terrain")
	if terrain then
		table.insert(filterList, terrain)
	end
	raycastParams.FilterDescendantsInstances = filterList

	local result = Workspace:Raycast(ray.Origin, ray.Direction * 1000, raycastParams)
	if not (result and result.Instance) then
		HUDStore.clearBuildingSelection()
		return
	end

	-- A building is either the hit instance itself (BuildingType attribute) or
	-- the nearest Model ancestor carrying one -- mirrors HUD.luau's lookup order.
	local building: Instance? = nil
	if result.Instance:GetAttribute("BuildingType") then
		building = result.Instance
	else
		local model = result.Instance:FindFirstAncestorOfClass("Model")
		if model and model:GetAttribute("BuildingType") then
			building = model
		end
	end

	if not building then
		HUDStore.clearBuildingSelection()
		return
	end

	local buildingType = building:GetAttribute("BuildingType")
	local owner = building:GetAttribute("OwnerId")
	if not (buildingType and owner == player.UserId) then
		HUDStore.clearBuildingSelection()
		return
	end

	-- In delete mode, DeletionInputHandler (src/client) owns this click.
	if HUDStore.get().isDeleteMode then
		return
	end

	local buildingInfo = GameData.Buildings[buildingType]
	if buildingInfo and buildingInfo.can_train_units then
		HUDStore.selectTrainingBuilding(building :: Model)
	elseif buildingInfo and buildingInfo.produces_resource then
		HUDStore.selectProductionBuilding(building :: Model)
	else
		HUDStore.clearBuildingSelection()
	end
end

local function onInputBegan(input: InputObject, gameProcessed: boolean)
	-- Ctrl+U undo -- checked before the gameProcessed guard below (matches
	-- HUD.luau: a text box swallowing focus should not eat the undo hotkey),
	-- and checked both key orders since either key can be the "second" one down.
	if input.KeyCode == Enum.KeyCode.U and input.UserInputType == Enum.UserInputType.Keyboard then
		if
			UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
			or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
		then
			HUDStore.undoLastDeletion()
			return
		end
	end
	if
		(input.KeyCode == Enum.KeyCode.LeftControl or input.KeyCode == Enum.KeyCode.RightControl)
		and input.UserInputType == Enum.UserInputType.Keyboard
	then
		if UserInputService:IsKeyDown(Enum.KeyCode.U) then
			HUDStore.undoLastDeletion()
			return
		end
	end

	if gameProcessed then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		handleLeftClick()
	end

	if input.KeyCode == Enum.KeyCode.Escape and HUDStore.get().isDeleteMode then
		HUDStore.setDeleteMode(false)
	end

	if input.UserInputType == Enum.UserInputType.MouseButton2 and HUDStore.get().isDeleteMode then
		HUDStore.setDeleteMode(false)
	end
end

function HUDInput.start()
	if connection then
		return
	end
	connection = UserInputService.InputBegan:Connect(onInputBegan)
end

function HUDInput.stop()
	if connection then
		connection:Disconnect()
		connection = nil
	end
end

return HUDInput
