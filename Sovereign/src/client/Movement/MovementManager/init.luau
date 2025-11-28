--!strict
-- MovementManager: Handles unit movement and attack commands

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DebugManager = require(ReplicatedStorage.Shared.DebugManager)
local MovementDebug = DebugManager.createChannel("Movement", false)

local SelectionManager = require(script.Parent.Parent.Selection.SelectionManager)

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

-- Get unit or enemy at mouse position
local function getUnitAtMouse(mousePosition: Vector2): Model?
	local ray = camera:ScreenPointToRay(mousePosition.X, mousePosition.Y)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude

	local filterList = { player.Character }
	if workspace:FindFirstChild("Terrain") then
		table.insert(filterList, workspace.Terrain)
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

-- Handle right-click movement and attack
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	-- Right mouse button - move or attack command
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		local selectedUnits = SelectionManager.getSelectedUnits()

		if #selectedUnits > 0 then
			local mousePosition = UserInputService:GetMouseLocation()

			-- Check if right-clicking on a unit
			local targetUnit = getUnitAtMouse(mousePosition)

			if targetUnit then
				-- Check if it's an enemy
				local targetOwner = targetUnit:GetAttribute("Owner")

				if targetOwner ~= player.UserId then
					-- It's an enemy - attack!
					MovementManager.attackTarget(selectedUnits, targetUnit)
					MovementDebug:info("Attack command issued", {
						targetOwner = targetOwner,
						playerUserId = player.UserId,
					})
					return
				end
			end

			-- No enemy clicked - move to ground
			-- Raycast to find ground position
			local ray = camera:ScreenPointToRay(mousePosition.X, mousePosition.Y)

			local raycastParams = RaycastParams.new()
			raycastParams.FilterType = Enum.RaycastFilterType.Exclude
			raycastParams.FilterDescendantsInstances = { player.Character }

			local result = workspace:Raycast(ray.Origin, ray.Direction * 1000, raycastParams)

			if result then
				MovementManager.moveUnitsTo(selectedUnits, result.Position)
			end
		end
	end
end)

MovementDebug:info("Initialized")

return MovementManager
