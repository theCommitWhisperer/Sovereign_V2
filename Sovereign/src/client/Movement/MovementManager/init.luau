--!strict
-- MovementManager: Handles unit movement and attack commands

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DebugManager = require(ReplicatedStorage.Shared.DebugManager)
local MovementDebug = DebugManager.createChannel("Movement", false)

local SelectionManager = require(script.Parent.Parent.Selection.SelectionManager)
-- The Lord is moved client-side, never through GameEvent. See LordController's
-- header for the full reasoning (short version: the player's Character has no
-- UnitId and is not in workspace.Units, so every server order action is a
-- guaranteed no-op for him, and parenting him into workspace.Units breaks ~10
-- systems including EliminationManager, which would DESTROY the Character).
local LordController = require(script.Parent.LordController)

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local MovementManager = {}

-- Get RemoteEvent for movement and combat
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local GameEvent = RemoteEvents:WaitForChild("GameEvent")

-- Visual feedback for move command
local function createMoveMarker(position: Vector3)
	local marker = Instance.new("Part")
	marker.Name = "MoveMarker"
	marker.Size = Vector3.new(2, 0.5, 2)
	marker.Position = position + Vector3.new(0, 0.5, 0)
	marker.Anchored = true
	marker.CanCollide = false
	marker.Transparency = 0.5
	marker.Color = Color3.fromRGB(255, 255, 0)
	marker.Material = Enum.Material.Neon
	marker.Parent = workspace

	-- Add a cylinder mesh
	local mesh = Instance.new("CylinderMesh")
	mesh.Parent = marker

	-- Animate and remove
	task.spawn(function()
		for i = 1, 20 do
			marker.Transparency = 0.5 + (i / 40)
			marker.Size = marker.Size + Vector3.new(0.2, 0, 0.2)
			task.wait(0.05)
		end
		marker:Destroy()
	end)
end

-- Visual feedback for attack command
local function createAttackMarker(position: Vector3)
	local marker = Instance.new("Part")
	marker.Name = "AttackMarker"
	marker.Size = Vector3.new(2, 0.5, 2)
	marker.Position = position + Vector3.new(0, 3, 0)
	marker.Anchored = true
	marker.CanCollide = false
	marker.Transparency = 0.5
	marker.Color = Color3.fromRGB(255, 0, 0) -- Red for attack
	marker.Material = Enum.Material.Neon
	marker.Parent = workspace

	-- Add a sphere mesh
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = marker

	-- Animate and remove
	task.spawn(function()
		for i = 1, 20 do
			marker.Transparency = 0.5 + (i / 40)
			marker.Size = marker.Size + Vector3.new(0.2, 0.2, 0.2)
			task.wait(0.05)
		end
		marker:Destroy()
	end)
end

-- Calculate formation positions for multiple units
local function calculateFormationPositions(targetPosition: Vector3, unitCount: number): { Vector3 }
	local positions = {}

	if unitCount == 1 then
		table.insert(positions, targetPosition)
		return positions
	end

	-- Simple grid formation
	local unitsPerRow = math.ceil(math.sqrt(unitCount))
	local spacing = 5

	for i = 1, unitCount do
		local row = math.floor((i - 1) / unitsPerRow)
		local col = (i - 1) % unitsPerRow

		-- Center the formation
		local offsetX = (col - unitsPerRow / 2) * spacing
		local offsetZ = (row - unitsPerRow / 2) * spacing

		local position = targetPosition + Vector3.new(offsetX, 0, offsetZ)
		table.insert(positions, position)
	end

	return positions
end

-- Send move command to server
function MovementManager.moveUnitsTo(units: { Model }, targetPosition: Vector3, useFormation: boolean?)
	if #units == 0 then
		return
	end

	-- If moving multiple units, use formation by default
	local shouldUseFormation = useFormation ~= false and #units >= 2

	if shouldUseFormation then
		-- Send formation move command to server
		local unitIds = {}
		for _, unit in units do
			table.insert(unitIds, unit:GetAttribute("UnitId") or unit.Name)
		end

		-- Get selected formation type from SelectionManager
		local formationType = SelectionManager.getFormationType() or "Line"

		GameEvent:FireServer("MoveUnitsInFormation", {
			unitIds = unitIds,
			targetPosition = targetPosition,
			formationType = formationType,
			isMove = true, -- a real travel order (server applies March stance)
		})

		MovementDebug:info("Moving units in formation", {
			count = #units,
			targetPosition = targetPosition,
			formationType = formationType,
		})
	else
		-- Calculate formation positions for individual movement
		local positions = calculateFormationPositions(targetPosition, #units)

		-- Send command to server for each unit
		for i, unit in units do
			local unitId = unit:GetAttribute("UnitId") or unit.Name
			GameEvent:FireServer("MoveUnit", {
				unitId = unitId,
				targetPosition = positions[i],
			})
		end

		MovementDebug:info("Moving units individually", {
			count = #units,
			targetPosition = targetPosition,
		})
	end

	-- Visual feedback
	createMoveMarker(targetPosition)
end

-- Send attack command to server
function MovementManager.attackTarget(units: { Model }, target: Model)
	if #units == 0 or not target then
		return
	end

	local targetId = target:GetAttribute("UnitId") or target.Name

	-- Send attack command for each unit
	for _, unit in units do
		local unitId = unit:GetAttribute("UnitId") or unit.Name
		GameEvent:FireServer("AttackTarget", {
			unitId = unitId,
			targetId = targetId,
		})
	end

	-- Visual feedback
	if target.PrimaryPart then
		createAttackMarker(target.PrimaryPart.Position)
	end

	MovementDebug:info("Attacking target", {
		attackerCount = #units,
		target = target.Name,
	})
end

-- Send a move order for regular (server-owned) units only, splitting civilians
-- from army exactly the way SelectionManager always has. Civilians take
-- "MoveWorkers" (which also releases them from their job); army takes
-- "MoveUnitsInFormation" with the currently selected formation.
local function orderRegularUnits(units: { Model }, targetPosition: Vector3)
	if #units == 0 then
		return
	end

	local civilianIds: { string } = {}
	local militaryIds: { string } = {}
	for _, unit in units do
		local id = unit:GetAttribute("UnitId") or unit.Name
		if SelectionManager.isCivilian(unit) then
			table.insert(civilianIds, id)
		else
			table.insert(militaryIds, id)
		end
	end

	if #civilianIds > 0 then
		GameEvent:FireServer("MoveWorkers", {
			unitIds = civilianIds,
			targetPosition = targetPosition,
		})
	end
	if #militaryIds > 0 then
		GameEvent:FireServer("MoveUnitsInFormation", {
			unitIds = militaryIds,
			targetPosition = targetPosition,
			formationType = SelectionManager.getFormationType() or "Line",
			isMove = true,
		})
	end

	MovementDebug:info("Move order", {
		civilians = #civilianIds,
		military = #militaryIds,
		target = targetPosition,
	})
end

-- Get unit or enemy at mouse position.
--
-- The local player's own Character is excluded here on purpose: this ray only
-- answers "what am I ordering AGAINST?", and you can neither attack nor target
-- yourself. (Selection uses SelectionManager's own ray, which deliberately does
-- NOT exclude the Character — that exclusion was the bug that made the Lord
-- unclickable.)
local function getUnitAtMouse(mousePosition: Vector2): Model?
	local ray = camera:ScreenPointToRay(mousePosition.X, mousePosition.Y)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude

	local filterList: { Instance } = {}
	if player.Character then
		table.insert(filterList, player.Character)
	end
	if workspace:FindFirstChild("Terrain") then
		table.insert(filterList, workspace.Terrain)
	end
	-- Selection rings and the fading markers from the previous order are
	-- CanCollide=false but raycasts still hit them, so they would shadow the
	-- enemy standing underneath.
	for _, child in workspace:GetChildren() do
		if child.Name == "SelectionIndicator" or child.Name == "MoveMarker" or child.Name == "AttackMarker" then
			table.insert(filterList, child)
		end
	end
	raycastParams.FilterDescendantsInstances = filterList

	local result = workspace:Raycast(ray.Origin, ray.Direction * 1000, raycastParams)

	if result and result.Instance then
		-- Check if we hit a unit (part of a Model with UnitType)
		local model = result.Instance:FindFirstAncestorOfClass("Model")
		if model and model:GetAttribute("UnitType") then
			return model
		end

		-- Or if the instance itself is a unit Model
		if result.Instance:IsA("Model") and result.Instance:GetAttribute("UnitType") then
			return result.Instance
		end
	end

	return nil
end

--- The server resolves every order id with `workspace.Units:FindFirstChild(id)`.
--- Anything not parented there — most importantly ANOTHER PLAYER'S Character,
--- i.e. a rival Lord, which also carries UnitType/OwnerId — can never be found,
--- so "AttackTarget" against it was accepted by the client and silently dropped
--- by the server: the player saw an attack marker and his army did nothing.
local function isServerOrderable(model: Model): boolean
	local unitsFolder = workspace:FindFirstChild("Units")
	return unitsFolder ~= nil and model.Parent == unitsFolder
end

-- ═══════════════════════════════════════════════════════════════════════════
-- THE ONE RIGHT-CLICK HANDLER
-- ═══════════════════════════════════════════════════════════════════════════
-- SelectionManager used to own a second MouseButton2 connection that fired its
-- own move orders for the same click. Both ran, so every right click produced two
-- competing orders. This is now the only right-click order path in the client;
-- do not add another one.
--
-- Decision tree:
--   0. ViewMode says block (hero view / mid camera blend) → ignore entirely.
--   1. Split the selection into "the Lord" and "regular units".
--   2. Right-clicked an ENEMY that the server can actually resolve
--      (parented under workspace.Units):
--        regular units → "AttackTarget"; the Lord walks to it (he fights in hero
--        view, not by RTS order — an RTS attack-move for him would need a whole
--        client combat AI, and giving him a silent no-op is worse than walking).
--   3. Right-clicked an enemy the server CANNOT resolve (a rival player's Lord):
--      degrade to a move order onto his position for everyone, rather than
--      emitting an AttackTarget the server throws away.
--   4. Anything else → ground move: regular units through the remotes, the Lord
--      through LordController, so a mixed selection all walks to the same point.
UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end
	if input.UserInputType ~= Enum.UserInputType.MouseButton2 then
		return
	end
	-- Blocks hero view, the mid-blend camera window, AND an active building
	-- placement ghost. That last one matters here specifically: PlacementController
	-- also binds MouseButton2 (to cancel the ghost), and these are two independent
	-- InputBegan listeners, so before ViewMode carried a placement flag one
	-- right-click during placement cancelled the ghost and marched the whole
	-- selection to the cursor at the same time.
	if SelectionManager.shouldBlockRTSInput() then
		return
	end

	local selectedUnits = SelectionManager.getSelectedUnits()
	if #selectedUnits == 0 then
		return
	end

	local lordSelected = false
	local regularUnits: { Model } = {}
	for _, unit in selectedUnits do
		if SelectionManager.isLocalLord(unit) then
			lordSelected = true
		else
			table.insert(regularUnits, unit)
		end
	end

	local mousePosition = UserInputService:GetMouseLocation()
	local targetUnit = getUnitAtMouse(mousePosition)

	if targetUnit and targetUnit:GetAttribute("OwnerId") ~= player.UserId then
		local targetPosition = targetUnit.PrimaryPart and targetUnit.PrimaryPart.Position

		if isServerOrderable(targetUnit) then
			if #regularUnits > 0 then
				MovementManager.attackTarget(regularUnits, targetUnit)
			end
			if lordSelected and targetPosition then
				LordController.moveTo(targetPosition)
				if #regularUnits == 0 then
					createAttackMarker(targetPosition)
				end
			end
			MovementDebug:info("Attack order", {
				attackers = #regularUnits,
				lordWalking = lordSelected,
				target = targetUnit.Name,
			})
			return
		end

		if targetPosition then
			-- Rival Lord (a Character, not a workspace.Units entry). Walk at him
			-- instead of firing an order the server will discard.
			MovementDebug:info("Target not server-orderable (rival Lord); moving instead", {
				target = targetUnit.Name,
			})
			orderRegularUnits(regularUnits, targetPosition)
			if lordSelected then
				LordController.moveTo(targetPosition)
			end
			createMoveMarker(targetPosition)
			return
		end
	end

	local dest = SelectionManager.getGroundPointAtMouse(mousePosition)
	if not dest then
		return
	end

	orderRegularUnits(regularUnits, dest)
	if lordSelected then
		LordController.moveTo(dest)
	end
	createMoveMarker(dest)
end)

MovementDebug:info("Initialized")

return MovementManager
