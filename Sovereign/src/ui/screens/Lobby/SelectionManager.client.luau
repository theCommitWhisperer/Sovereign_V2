--!strict
-- SelectionManager: Handles unit selection and visual feedback

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local DebugManager = require(ReplicatedStorage.Shared.DebugManager)
local SelectionDebug = DebugManager.createChannel("Selection", false)

local SelectionManager = {}

-- State
local selectedUnits: { Model } = {}
local isBoxSelecting = false
local boxStartPosition: Vector2? = nil
local selectionBox: Frame? = nil

-- Selection indicators
local selectionIndicators: { [Model]: Instance } = {}

-- Create selection indicator for a unit
local function createSelectionIndicator(unit: Model): Instance
	if not unit.PrimaryPart then
		return nil
	end

	-- Create a selection circle at the unit's feet
	local indicator = Instance.new("Part")
	indicator.Name = "SelectionIndicator"
	indicator.Size = Vector3.new(4, 0.2, 4)
	indicator.Anchored = true
	indicator.CanCollide = false
	indicator.Transparency = 0.5
	indicator.Color = Color3.fromRGB(0, 255, 0) -- Green
	indicator.Material = Enum.Material.Neon

	-- Make it a cylinder
	local mesh = Instance.new("CylinderMesh")
	mesh.Parent = indicator

	indicator.Parent = workspace

	return indicator
end

-- Update indicator position to follow unit
local function updateIndicatorPosition(unit: Model, indicator: Instance)
	if not unit.PrimaryPart or not indicator then
		return
	end

	local position = unit.PrimaryPart.Position
	indicator.CFrame = CFrame.new(position.X, position.Y - 1, position.Z)
end

-- Add a unit to selection
function SelectionManager.addToSelection(unit: Model)
	-- Check if unit belongs to player
	local owner = unit:GetAttribute("Owner")
	if owner ~= player.UserId then
		return
	end

	-- Check if already selected
	for _, selectedUnit in selectedUnits do
		if selectedUnit == unit then
			return
		end
	end

	table.insert(selectedUnits, unit)

	-- Create visual indicator
	local indicator = createSelectionIndicator(unit)
	if indicator then
		selectionIndicators[unit] = indicator
	end

	SelectionDebug:info(`Selected {unit.Name}`)
end

-- Remove a unit from selection
function SelectionManager.removeFromSelection(unit: Model)
	for i, selectedUnit in selectedUnits do
		if selectedUnit == unit then
			table.remove(selectedUnits, i)

			-- Remove indicator
			if selectionIndicators[unit] then
				selectionIndicators[unit]:Destroy()
				selectionIndicators[unit] = nil
			end

			break
		end
	end
end

-- Clear all selections
function SelectionManager.clearSelection()
	for _, unit in selectedUnits do
		if selectionIndicators[unit] then
			selectionIndicators[unit]:Destroy()
			selectionIndicators[unit] = nil
		end
	end

	selectedUnits = {}
	SelectionDebug:info("Cleared selection")
end

-- Get currently selected units
function SelectionManager.getSelectedUnits(): { Model }
	return selectedUnits
end

-- Check if a position is on screen
local function worldToScreen(position: Vector3): (Vector2, boolean)
	local screenPos, onScreen = camera:WorldToViewportPoint(position)
	return Vector2.new(screenPos.X, screenPos.Y), onScreen
end

-- Get unit at mouse position
local function getUnitAtMouse(mousePosition: Vector2): Model?
	local ray = camera:ScreenPointToRay(mousePosition.X, mousePosition.Y)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { player.Character }

	local result = workspace:Raycast(ray.Origin, ray.Direction * 1000, raycastParams)

	if result and result.Instance then
		-- Check if we hit a unit
		local model = result.Instance:FindFirstAncestorOfClass("Model")
		if model and model:GetAttribute("UnitType") then
			return model
		end
	end

	return nil
end

-- Get all units in box
local function getUnitsInBox(topLeft: Vector2, bottomRight: Vector2): { Model }
	local unitsInBox = {}

	-- Get all units in workspace
	local unitsFolder = workspace:FindFirstChild("Units")
	if not unitsFolder then
		return unitsInBox
	end

	for _, unit in unitsFolder:GetChildren() do
		if unit:IsA("Model") and unit:GetAttribute("UnitType") and unit.PrimaryPart then
			-- Check if unit belongs to player
			if unit:GetAttribute("Owner") == player.UserId then
				-- Convert world position to screen position
				local screenPos, onScreen = worldToScreen(unit.PrimaryPart.Position)

				if onScreen then
					-- Check if in box
					if
						screenPos.X >= math.min(topLeft.X, bottomRight.X)
						and screenPos.X <= math.max(topLeft.X, bottomRight.X)
						and screenPos.Y >= math.min(topLeft.Y, bottomRight.Y)
						and screenPos.Y <= math.max(topLeft.Y, bottomRight.Y)
					then
						table.insert(unitsInBox, unit)
					end
				end
			end
		end
	end

	return unitsInBox
end

-- Create selection box UI
local function createSelectionBoxUI(): Frame
	local playerGui = player:WaitForChild("PlayerGui")

	local box = Instance.new("Frame")
	box.Name = "SelectionBox"
	box.BorderSizePixel = 2
	box.BorderColor3 = Color3.fromRGB(0, 255, 0)
	box.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
	box.BackgroundTransparency = 0.8
	box.ZIndex = 100
	box.Parent = playerGui:FindFirstChild("ScreenGui") or playerGui

	return box
end

-- Handle mouse input
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	-- Left mouse button - start selection
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		local mousePosition = UserInputService:GetMouseLocation()

		-- Try to select a unit
		local unit = getUnitAtMouse(mousePosition)

		if unit then
			-- Single unit selection
			if not UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
				SelectionManager.clearSelection()
			end
			SelectionManager.addToSelection(unit)
		else
			-- Start box selection
			if not UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
				SelectionManager.clearSelection()
			end

			isBoxSelecting = true
			boxStartPosition = mousePosition

			if not selectionBox then
				selectionBox = createSelectionBoxUI()
			end
		end
	end
end)

UserInputService.InputEnded:Connect(function(input)
	-- End box selection
	if input.UserInputType == Enum.UserInputType.MouseButton1 and isBoxSelecting then
		isBoxSelecting = false

		if boxStartPosition and selectionBox then
			local mousePosition = UserInputService:GetMouseLocation()

			-- Get units in box
			local units = getUnitsInBox(boxStartPosition, mousePosition)
			for _, unit in units do
				SelectionManager.addToSelection(unit)
			end
		end

		-- Hide selection box
		if selectionBox then
			selectionBox.Visible = false
		end

		boxStartPosition = nil
	end
end)

-- Update selection box and indicators
RunService.RenderStepped:Connect(function()
	-- Update selection box during drag
	if isBoxSelecting and boxStartPosition and selectionBox then
		local mousePosition = UserInputService:GetMouseLocation()

		local topLeft =
			Vector2.new(math.min(boxStartPosition.X, mousePosition.X), math.min(boxStartPosition.Y, mousePosition.Y))

		local bottomRight =
			Vector2.new(math.max(boxStartPosition.X, mousePosition.X), math.max(boxStartPosition.Y, mousePosition.Y))

		selectionBox.Position = UDim2.fromOffset(topLeft.X, topLeft.Y)
		selectionBox.Size = UDim2.fromOffset(bottomRight.X - topLeft.X, bottomRight.Y - topLeft.Y)
		selectionBox.Visible = true
	end

	-- Update indicator positions
	for unit, indicator in selectionIndicators do
		if unit and unit.Parent then
			updateIndicatorPosition(unit, indicator)
		else
			-- Unit was destroyed, remove indicator
			if indicator then
				indicator:Destroy()
			end
			selectionIndicators[unit] = nil
		end
	end
end)

SelectionDebug:info("Initialized")

return SelectionManager
