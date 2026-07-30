local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DebugManager = require(ReplicatedStorage.Shared.DebugManager)
local ViewMode = require(ReplicatedStorage.Shared.ViewMode)
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
local selectedFormationType: string = "Line" -- Default formation type

local selectionChangedEvent = Instance.new("BindableEvent")
SelectionManager.SelectionChanged = selectionChangedEvent.Event

-- Selection indicators
local selectionIndicators: { [Model]: Instance } = {}
-- Per-model distance from PrimaryPart origin down to the model's feet. Cached at
-- selection time; see getGroundOffset for why this can't be a constant.
local indicatorGroundOffsets: { [Model]: number } = {}

-- The local player's Lord IS his Character. He is deliberately NOT inside
-- workspace.Units (see Movement/LordController for the ten systems that breaks),
-- so every "is this the Lord?" test in RTS code has to be this identity check.
local function isLocalLord(model: Instance?): boolean
	return model ~= nil and model == player.Character
end
SelectionManager.isLocalLord = isLocalLord

-- The unit rigs are authored with their PrimaryPart roughly a stud above the
-- ground, so the old hard-coded `position.Y - 1` happened to land the ring on the
-- floor for them. An R15 Character's PrimaryPart is the HumanoidRootPart, which
-- sits ~3 studs up — the same constant floated the Lord's ring around his knees.
-- Derive the drop from the model's real extents so one code path fits both rigs.
local function getGroundOffset(unit: Model): number
	local primary = unit.PrimaryPart
	if not primary then
		return 1
	end
	local ok, boundingCFrame, size = pcall(function()
		return unit:GetBoundingBox()
	end)
	if not ok or not boundingCFrame or not size then
		return 1
	end
	local bottomY = boundingCFrame.Position.Y - (size.Y / 2)
	return math.max(primary.Position.Y - bottomY, 0)
end

-- Create selection indicator for a unit
local function createSelectionIndicator(unit: Model): Instance?
	if not unit.PrimaryPart then
		return nil
	end

	local lord = isLocalLord(unit)

	-- Create a selection circle at the unit's feet
	local indicator = Instance.new("Part")
	indicator.Name = "SelectionIndicator"
	-- The Lord gets a wider gold ring so he reads as the hero in a mixed
	-- selection rather than as "one more green dot".
	indicator.Size = if lord then Vector3.new(5.5, 0.2, 5.5) else Vector3.new(4, 0.2, 4)
	indicator.Anchored = true
	indicator.CanCollide = false
	indicator.Transparency = 0.5
	indicator.Color = if lord then Color3.fromRGB(255, 200, 60) else Color3.fromRGB(0, 255, 0)
	indicator.Material = Enum.Material.Neon

	-- Make it a cylinder
	local mesh = Instance.new("CylinderMesh")
	mesh.Parent = indicator

	indicator.Parent = workspace

	indicatorGroundOffsets[unit] = getGroundOffset(unit)

	return indicator
end

-- Update indicator position to follow unit
local function updateIndicatorPosition(unit: Model, indicator: Instance)
	if not unit.PrimaryPart or not indicator then
		return
	end

	local position = unit.PrimaryPart.Position
	local offset = indicatorGroundOffsets[unit] or 1
	indicator.CFrame = CFrame.new(position.X, position.Y - offset, position.Z)
end

-- Add a unit to selection
function SelectionManager.addToSelection(unit: Model)
	SelectionDebug:info(`addToSelection called for {unit.Name}`)

	-- Check if unit belongs to player
	local owner = unit:GetAttribute("OwnerId")
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

-- Clear all selections.
--
-- There used to be TWO definitions of this function. The second one won, and it
-- was the one that did NOT fire selectionChangedEvent — so the HUD's selection
-- panel kept rendering units the player had already deselected. Only this
-- signalling version exists now; do not re-add a "simpler" one below it.
function SelectionManager.clearSelection()
	for _, unit in selectedUnits do
		if selectionIndicators[unit] then
			selectionIndicators[unit]:Destroy()
			selectionIndicators[unit] = nil
		end
		indicatorGroundOffsets[unit] = nil
	end

	selectedUnits = {}

	-- Fire selection changed event
	selectionChangedEvent:Fire(selectedUnits)

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
			indicatorGroundOffsets[unit] = nil

			-- Same stale-panel bug as clearSelection: the HUD only learns about
			-- the new selection from this event.
			selectionChangedEvent:Fire(selectedUnits)

			break
		end
	end
end

-- Get currently selected units
function SelectionManager.getSelectedUnits(): { Model }
	return selectedUnits
end

-- Set the formation type
function SelectionManager.setFormationType(formationType: string)
	selectedFormationType = formationType
	SelectionDebug:info(`Formation type set to: {formationType}`)
end

-- Get the current formation type
function SelectionManager.getFormationType(): string
	return selectedFormationType
end

-- Check if a position is on screen
local function worldToScreen(position: Vector3): (Vector2, boolean)
	local screenPos, onScreen = camera:WorldToViewportPoint(position)
	return Vector2.new(screenPos.X, screenPos.Y), onScreen
end
-- Cosmetics that live loose in Workspace and would otherwise eat the pick ray.
-- Raycasts DO hit CanCollide=false parts, so the selection ring under a unit and
-- the move marker you just spawned are both solid as far as :Raycast is
-- concerned — without this, clicking a selected unit hits its own ring.
local IGNORED_PICK_NAMES: { [string]: boolean } = {
	SelectionIndicator = true,
	MoveMarker = true,
	AttackMarker = true,
	GhostBuildingPreview = true,
	Ghost = true,
	GhostCP = true,
	CombatEffects = true,
	Effects = true,
	HiddenByFog = true,
}

local function buildPickFilter(): { Instance }
	local filter: { Instance } = {}
	-- Terrain is excluded so the ray keeps travelling to whatever unit is
	-- standing on it rather than stopping at the ground.
	if workspace:FindFirstChild("Terrain") then
		table.insert(filter, workspace.Terrain)
	end
	for _, child in workspace:GetChildren() do
		if IGNORED_PICK_NAMES[child.Name] then
			table.insert(filter, child)
		end
	end
	return filter
end

-- Get unit at mouse position
--
-- NOTE: `player.Character` used to be in this exclude list. That single line was
-- the entire reason the player could not click his own Lord: the Character is
-- shaped exactly like a selectable unit (the server sets UnitType = "King",
-- IsKing and OwnerId on it) but the ray was told to pass straight through him.
local function getUnitAtMouse(mousePosition: Vector2): Model?
	SelectionDebug:info("getUnitAtMouse", { position = mousePosition })

	local ray = camera:ScreenPointToRay(mousePosition.X, mousePosition.Y)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = buildPickFilter()

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

	local minX, maxX = math.min(topLeft.X, bottomRight.X), math.max(topLeft.X, bottomRight.X)
	local minY, maxY = math.min(topLeft.Y, bottomRight.Y), math.max(topLeft.Y, bottomRight.Y)

	local function considerModel(unit: Model)
		if not unit.PrimaryPart or not unit:GetAttribute("UnitType") then
			return
		end
		if unit:GetAttribute("OwnerId") ~= player.UserId then
			return
		end
		local screenPos, onScreen = worldToScreen(unit.PrimaryPart.Position)
		if not onScreen then
			return
		end
		if screenPos.X >= minX and screenPos.X <= maxX and screenPos.Y >= minY and screenPos.Y <= maxY then
			table.insert(unitsInBox, unit)
		end
	end

	-- Get all units in workspace
	local unitsFolder = workspace:FindFirstChild("Units")
	if unitsFolder then
		for _, unit in unitsFolder:GetChildren() do
			if unit:IsA("Model") then
				considerModel(unit)
			end
		end
	end

	-- The Lord is the player's Character and lives directly under Workspace, not
	-- in the Units folder, so iterating that folder alone made him invisible to
	-- box-select. Add him explicitly; considerModel still checks UnitType/OwnerId,
	-- which the server stamps onto the Character.
	local lord = player.Character
	if lord then
		considerModel(lord)
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
-- In hero view the mouse drives combat, not RTS selection — clicks must not
-- select units or issue move orders.
--
-- This used to read `player.CameraMode == LockFirstPerson`. That check is now
-- permanently false: hero view is THIRD person and deliberately leaves
-- CameraMode as Classic (see Camera/HeroCamera.luau), so the old guard let every
-- combat click fall through into unit selection and move orders at the same time.
-- ViewMode is the single source of truth now, and it additionally reports the
-- mid-blend window — during the ~0.35s camera transition the camera CFrame
-- matches neither view, so a mouse raycast lands somewhere the player never
-- aimed at. Blocking that window is what stops "I pressed V and my whole army
-- walked into the sea".
local function inFirstPerson(): boolean
	return ViewMode.shouldBlockRTSInput()
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

	if inFirstPerson() then
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
				owner = unit:GetAttribute("OwnerId"),
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
	local removedAny = false
	for unit, indicator in selectionIndicators do
		if unit and unit.Parent then
			updateIndicatorPosition(unit, indicator)
		else
			-- Unit was destroyed, remove indicator
			if indicator then
				indicator:Destroy()
			end
			selectionIndicators[unit] = nil
			indicatorGroundOffsets[unit] = nil

			-- The old code dropped the indicator but left the dead model in
			-- selectedUnits forever. That matters far more now the Lord can be
			-- selected: on death his Character is replaced, and a stale entry
			-- would have every later right-click try to order a destroyed body
			-- (and keep the HUD panel showing a unit that no longer exists).
			local index = table.find(selectedUnits, unit)
			if index then
				table.remove(selectedUnits, index)
				removedAny = true
			end
		end
	end
	if removedAny then
		selectionChangedEvent:Fire(selectedUnits)
	end
end)

-- ============================================
-- RIGHT-CLICK ORDERS (move) — civilians vs army
-- ============================================

local GameData = require(ReplicatedStorage.Shared.GameData)

local function getGameEvent(): RemoteEvent?
	local re = ReplicatedStorage:FindFirstChild("RemoteEvents")
	local ev = re and re:FindFirstChild("GameEvent")
	return (ev and ev:IsA("RemoteEvent")) and ev or nil
end

-- Civilians (peasants + worker-subtype job units) take different orders from army.
-- Exported because the single right-click dispatcher now lives in
-- Movement/MovementManager (it owns the move/attack markers) and must apply the
-- exact same split.
local function isCivilian(unit: Model): boolean
	local t = unit:GetAttribute("UnitType")
	if t == "Peasant" then
		return true
	end
	local data = t and GameData.Units[t]
	return data ~= nil and data.subtype == "Worker"
end
SelectionManager.isCivilian = isCivilian

local function groundPointAtMouse(mousePosition: Vector2): Vector3?
	local ray = camera:ScreenPointToRay(mousePosition.X, mousePosition.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local filter: { Instance } = buildPickFilter()
	if player.Character then
		-- A move order must never resolve to a point on your own Lord's head.
		table.insert(filter, player.Character)
	end
	local unitsFolder = workspace:FindFirstChild("Units")
	if unitsFolder then
		table.insert(filter, unitsFolder) -- don't land the order on a unit
	end
	-- Terrain is IN buildPickFilter (unit picking wants to see past the ground);
	-- a ground order obviously needs it back.
	local terrainIndex = table.find(filter, workspace.Terrain)
	if terrainIndex then
		table.remove(filter, terrainIndex)
	end
	params.FilterDescendantsInstances = filter
	local result = workspace:Raycast(ray.Origin, ray.Direction * 2000, params)
	return result and result.Position or nil
end
SelectionManager.getGroundPointAtMouse = groundPointAtMouse

--- True when RTS mouse input should be ignored (hero view, or mid camera blend).
SelectionManager.shouldBlockRTSInput = inFirstPerson

-- Expose so a command panel can order the current selection to the Keep / unassign.
function SelectionManager.orderSelected(action: string, extra: { [string]: any }?)
	local gameEvent = getGameEvent()
	if not gameEvent or #selectedUnits == 0 then
		return
	end
	local ids = {}
	for _, unit in selectedUnits do
		table.insert(ids, unit:GetAttribute("UnitId") or unit.Name)
	end
	local payload: { [string]: any } = { unitIds = ids }
	if extra then
		for k, v in pairs(extra) do
			payload[k] = v
		end
	end
	gameEvent:FireServer(action, payload)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- NO RIGHT-CLICK HANDLER LIVES HERE ANY MORE
-- ═══════════════════════════════════════════════════════════════════════════
-- There used to be one here AND one in Movement/MovementManager, both bound to
-- MouseButton2. Every right click therefore fired TWO overlapping orders for the
-- same selection: this file sent "MoveWorkers"/"MoveUnitsInFormation" while
-- MovementManager sent "AttackTarget" or a second "MoveUnitsInFormation"/
-- "MoveUnit" for the identical units — units received contradicting orders in a
-- race and formations shuffled twice.
--
-- The consolidated dispatcher is now MovementManager's, because that is the
-- module that owns the attack-target detection and the move/attack marker VFX.
-- It calls back into the exports above (isCivilian, getGroundPointAtMouse,
-- getFormationType, shouldBlockRTSInput) so the civilian/army split and the
-- unit-excluding ground ray defined here remain the single implementation.
-- DO NOT re-add a MouseButton2 connection to this file.

SelectionDebug:info("Initialized")

return SelectionManager
