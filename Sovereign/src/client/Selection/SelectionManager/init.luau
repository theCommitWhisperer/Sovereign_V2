local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DebugManager = require(ReplicatedStorage.Shared.DebugManager)
local SelectionDebug = DebugManager.createChannel("Selection", false) -- Enable for now

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local SelectionManager = {}

SelectionDebug:info("Script loading...")

-- State
local selectedUnits: { Model } = {}
local isBoxSelecting = false
local boxStartPosition: Vector2? = nil
local selectionBox: Frame? = nil

local selectionChangedEvent = Instance.new("BindableEvent")
SelectionManager.SelectionChanged = selectionChangedEvent.Event

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
	SelectionDebug:info(`addToSelection called for {unit.Name}`)

	-- Check if unit belongs to player
	local owner = unit:GetAttribute("Owner")
	SelectionDebug:info("Unit owner check", {
		owner = owner,
		playerId = player.UserId,
	})

	if owner ~= player.UserId then
		SelectionDebug:warn("Unit doesn't belong to player, rejecting")
		return
	end

	-- Check if already selected
	for _, selectedUnit in selectedUnits do
		if selectedUnit == unit then
			SelectionDebug:info("Unit already selected")
			return
		end
	end

	table.insert(selectedUnits, unit)
	SelectionDebug:info(`Added to selection`, { totalSelected = #selectedUnits })

	-- Create visual indicator
	local indicator = createSelectionIndicator(unit)
	if indicator then
		selectionIndicators[unit] = indicator
		SelectionDebug:info("Created selection indicator")
	else
		SelectionDebug:warn("Failed to create selection indicator")
	end

	-- Fire selection changed event
	selectionChangedEvent:Fire(selectedUnits)

	SelectionDebug:info(`Successfully selected {unit.Name}`)
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

	-- Fire selection changed event
	selectionChangedEvent:Fire(selectedUnits)

	SelectionDebug:info("Cleared selection")
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
	SelectionDebug:info("getUnitAtMouse", { position = mousePosition })

	local ray = camera:ScreenPointToRay(mousePosition.X, mousePosition.Y)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude

	-- Exclude player character AND terrain
	local filterList = { player.Character }
	if workspace:FindFirstChild("Terrain") then
		table.insert(filterList, workspace.Terrain)
	end
	raycastParams.FilterDescendantsInstances = filterList

	local result = workspace:Raycast(ray.Origin, ray.Direction * 1000, raycastParams)

	if result and result.Instance then
		SelectionDebug:info("Raycast hit", {
			instanceName = result.Instance.Name,
			parent = result.Instance.Parent and result.Instance.Parent.Name or "nil",
		})

		-- Check if we hit a unit
		local model = result.Instance:FindFirstAncestorOfClass("Model")
		SelectionDebug:info("Found model", { model = model and model.Name or "nil" })

		if model then
			local unitType = model:GetAttribute("UnitType")
			SelectionDebug:info("Model UnitType", { unitType = unitType })

			if unitType then
				SelectionDebug:info(`Found unit: {model.Name}`)
				return model
			end
		end
	else
		SelectionDebug:info("Raycast didn't hit anything")
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
	SelectionDebug:info("Input detected", {
		inputType = tostring(input.UserInputType),
		gameProcessed = gameProcessed,
	})

	if gameProcessed then
		SelectionDebug:info("Input was processed by game, ignoring")
		return
	end

	-- Left mouse button - start selection
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		SelectionDebug:info("Left mouse clicked")
		local mousePosition = UserInputService:GetMouseLocation()
		SelectionDebug:info("Mouse position", { position = mousePosition })

		-- Try to select a unit
		local unit = getUnitAtMouse(mousePosition)
		SelectionDebug:info("Unit at mouse", { unit = unit and unit.Name or "nil" })

		if unit then
			SelectionDebug:info("Found unit", {
				name = unit.Name,
				owner = unit:GetAttribute("Owner"),
				playerId = player.UserId,
			})
			-- Single unit selection
			if not UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
				SelectionManager.clearSelection()
			end
			SelectionManager.addToSelection(unit)
		else
			SelectionDebug:info("No unit found, starting box selection")
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

		-- Fire selection changed event (in case box selection added units)
		selectionChangedEvent:Fire(selectedUnits)
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
