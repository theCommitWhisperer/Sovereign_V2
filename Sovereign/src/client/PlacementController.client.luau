--!strict
-- PlacementController: Robust Logic & Safe Snapping

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local DebugManager = require(ReplicatedStorage.Shared.DebugManager)
local WallGridConfig = require(ReplicatedStorage.Shared.WallGridConfig)
local BuildingScaleConfig = require(ReplicatedStorage.Shared.GameData.BuildingScaleConfig)
-- Single source of truth for which view the player is in. Do not "clean this up"
-- as unused — it is read by the hero-view placement cancel below.
local ViewMode = require(ReplicatedStorage.Shared.ViewMode)
local PlacementDebug = DebugManager.createChannel("Placement", true)

-- Events
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local gameEvent = RemoteEvents:WaitForChild("GameEvent")

local wallPieceEvent = ReplicatedStorage:FindFirstChild("WallPieceChanged")
	or Instance.new("BindableEvent", ReplicatedStorage)
wallPieceEvent.Name = "WallPieceChanged"

local resetWallPieceFunc = ReplicatedStorage:FindFirstChild("ResetWallPiece")
	or Instance.new("BindableFunction", ReplicatedStorage)
resetWallPieceFunc.Name = "ResetWallPiece"

-- Cancel channel for the HUD's own Cancel button.
--
-- Placement was only ever cancellable with MouseButton2. A touch device has no
-- right-click, so on mobile a player who started placing a building had no way
-- out at all -- and because `isPlacing` gates ALL RTS selection and orders via
-- ViewMode.shouldBlockRTSInput(), being stuck in placement wedged the entire
-- game, not just the build menu. HUDStore fires this; the listener is installed
-- further down, once cleanup() exists.
local cancelPlacementEvent = ReplicatedStorage:FindFirstChild("CancelPlacement")
	or Instance.new("BindableEvent", ReplicatedStorage)
cancelPlacementEvent.Name = "CancelPlacement"
cancelPlacementEvent.Parent = ReplicatedStorage

-- Configuration
local SNAP_RADIUS = 20
local CONNECTION_TOLERANCE = 4.0
local WALL_GRID_SIZE = 1
local CONNECTION_OFFSET = 0.05 -- A small offset to prevent wall meshes from overlapping/Z-fighting.

-- State
local isPlacing = false
local currentBuildingName = nil
local ghostBuilding = nil
local canPlace = false
local manualRotation = 0
local wallPieceIndex = 1
local lastPlacedWallPosition = nil
local lastPlacedWallRotation = 0
local wallChainDirection = Vector3.new(1, 0, 0)
local lastGridTargetPos = nil

-- Zone bounds (set on GameStarted, used to validate placement position)
local playerZoneCenter: Vector3? = nil
local playerZoneRadius: number? = nil

local function isInPlayerZone(pos: Vector3): boolean
	if not playerZoneCenter or not playerZoneRadius then return true end
	local dx = pos.X - playerZoneCenter.X
	local dz = pos.Z - playerZoneCenter.Z
	return (dx * dx + dz * dz) <= (playerZoneRadius * playerZoneRadius)
end

-- Debug Visuals
local debugFolder = workspace:FindFirstChild("PlacementDebug") or Instance.new("Folder")
debugFolder.Name = "PlacementDebug"
debugFolder.Parent = workspace

local DIRECTIONS = {
	{ x = 0, z = -1, bit = 1 }, -- North
	{ x = 1, z = 0, bit = 2 }, -- East
	{ x = 0, z = 1, bit = 4 }, -- South
	{ x = -1, z = 0, bit = 8 }, -- West
}

local WALL_PIECES = {
	{ name = "Wall Segment", rotation = 0 },
	{ name = "Wall Corner", rotation = 0 },
	{ name = "Wall Corner Reverse", rotation = 0 },
	{ name = "Tower", rotation = 0 },
	{ name = "Gatehouse", rotation = 0 },
	{ name = "Ladder Wall Segment", rotation = 0 },
}

local GameData = require(ReplicatedStorage.Shared.GameData)
local KeybindingsManager = require(script.Parent.Camera.KeybindingsManager)

-- // HELPER FUNCTIONS //

local function getSafeBounds(obj: Instance)
	if obj:IsA("Model") then
		local cf, size = obj:GetBoundingBox()
		if size.Magnitude == 0 and obj.PrimaryPart then
			size = obj.PrimaryPart.Size
		end
		return cf, size
	elseif obj:IsA("BasePart") then
		return obj.CFrame, obj.Size
	end
	return CFrame.new(), Vector3.new(1, 1, 1)
end

-- Walk up from a part to find the top-level building Model that actually
-- carries the BuildingType attribute. Many visible wall parts live inside
-- nested Models (e.g. "Visuals"), so part.Parent is often *not* the
-- building instance we care about.
local function findBuildingModelFromPart(part: BasePart): Model?
	local current: Instance? = part
	while current do
		if current:IsA("Model") then
			local bType = current:GetAttribute("BuildingType")
			if bType ~= nil then
				return current
			end
		end
		current = current.Parent
	end
	return nil
end

local function getWallAssetName(bitmask)
	if bitmask == 15 then
		return "Tower", 0
	end
	if bitmask == 7 then
		return "Tower", 0
	end
	if bitmask == 11 then
		return "Tower", 180
	end
	if bitmask == 13 then
		return "Tower", 90
	end
	if bitmask == 14 then
		return "Tower", 270
	end
	if bitmask == 3 then
		return "Wall Corner", 0
	end
	if bitmask == 6 then
		return "Wall Corner", 270
	end
	if bitmask == 9 then
		return "Wall Corner", 90
	end
	if bitmask == 12 then
		return "Wall Corner", 180
	end
	if bitmask == 1 or bitmask == 4 or bitmask == 5 then
		return "Wall Segment", 90
	end
	return "Wall Segment", 0
end

-- Finds all floor-level ConnectionPoints on a model.
--
-- Contract for wall assets:
--   * Each model has one or more BaseParts named "ConnectionPoint" (or "ConnectionPoint_1", etc.)
--   * These parts sit at the desired floor level for that model.
--   * Their LookVector should point OUTWARD from the model along the connection direction.
--
-- This helper:
--   * Collects all matching parts (optionally inside a "ConnectionPoints" folder)
--   * Keeps only those at the lowest local Y ("floor" level) with a small tolerance
--   * Sorts them deterministically by local X/Z so index 1 is stable across runs
local function findConnectionPoints(model: Model): { BasePart }
	if not model or not model:IsA("Model") then
		return {}
	end

	local allPoints = {} :: { BasePart }

	-- 1) Prefer an explicit ConnectionPoints folder if present
	local cpFolder = model:FindFirstChild("ConnectionPoints")
	if cpFolder then
		for _, child in cpFolder:GetDescendants() do
			if child:IsA("BasePart") and string.match(child.Name, "^ConnectionPoint[_%d]*$") then
				table.insert(allPoints, child)
			end
		end
	end

	-- 2) Fallback: search entire model for ConnectionPoint parts
	if #allPoints == 0 then
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BasePart") and string.match(descendant.Name, "^ConnectionPoint[_%d]*$") then
				table.insert(allPoints, descendant)
			end
		end
	end

	if #allPoints == 0 then
		return {}
	end

	local pivot = model:GetPivot()

	-- 3) Find the lowest local Y among all connection points (their floor level)
	local minLocalY = math.huge
	for _, cp in allPoints do
		local localPos = pivot:PointToObjectSpace(cp.Position)
		if localPos.Y < minLocalY then
			minLocalY = localPos.Y
		end
	end

	-- 4) Keep only CPs that share this floor level (with tolerance).
	local floorPoints = {} :: { BasePart }
	for _, cp in allPoints do
		local localPos = pivot:PointToObjectSpace(cp.Position)
		if math.abs(localPos.Y - minLocalY) < 0.2 then
			table.insert(floorPoints, cp)
		end
	end

	if #floorPoints == 0 then
		-- If our floor filter is too strict for some asset, fall back to all CPs
		floorPoints = allPoints
	end

	-- 5) Sort deterministically by local X/Z for predictable primary CP selection
	table.sort(floorPoints, function(a, b)
		local aLocal = pivot:PointToObjectSpace(a.Position)
		local bLocal = pivot:PointToObjectSpace(b.Position)
		if math.abs(aLocal.X - bLocal.X) > 0.01 then
			return aLocal.X < bLocal.X
		end
		return aLocal.Z < bLocal.Z
	end)

	return floorPoints
end

-- // VISUAL DEBUGGING //
local function updateDebugVisuals(ghostCP: Vector3?, neighborCP: Vector3?)
	debugFolder:ClearAllChildren()
	if ghostCP then
		local gPart = Instance.new("Part")
		gPart.Name = "GhostCP"
		gPart.Size = Vector3.new(1.5, 0.5, 1.5)
		gPart.Shape = Enum.PartType.Ball
		gPart.Color = Color3.new(1, 0, 0)
		gPart.Material = Enum.Material.Neon
		gPart.Anchored = true
		gPart.CanCollide = false
		gPart.Position = ghostCP
		gPart.Parent = debugFolder
	end
	if neighborCP then
		local nPart = Instance.new("Part")
		nPart.Name = "NeighborCP"
		nPart.Size = Vector3.new(1.5, 0.5, 1.5)
		nPart.Shape = Enum.PartType.Ball
		nPart.Color = Color3.new(0, 1, 0)
		nPart.Material = Enum.Material.Neon
		nPart.Anchored = true
		nPart.CanCollide = false
		nPart.Position = neighborCP
		nPart.Parent = debugFolder
		local dist = (ghostCP - neighborCP).Magnitude
		if dist > 0.05 then
			local line = Instance.new("Part")
			line.Name = "SnapLine"
			line.Anchored = true
			line.CanCollide = false
			line.Color = Color3.new(0, 0, 1)
			line.Material = Enum.Material.Neon
			line.Size = Vector3.new(0.2, 0.2, dist)
			line.CFrame = CFrame.lookAt(ghostCP, neighborCP) * CFrame.new(0, 0, -dist / 2)
			line.Parent = debugFolder
		end
	end
end

-- NOTE:
--   We intentionally do NOT require ConnectionPoint normals to face directly
--   toward each other here. Corners, towers, and T-junctions often have
--   ConnectionPoints whose LookVectors are at 90° or otherwise not perfectly
--   opposite, but their positions still represent valid joints.
--
--   To support all those shapes, we simply pick the closest pair of
--   ConnectionPoints between the ghost model and a neighbor, as long as
--   they are within a reasonable snapping radius. Orientation is handled
--   separately by the wall bitmask / asset selection logic.
local function findNearestConnectionPoints(ghostModel: Model, neighborModel: Model): (BasePart?, BasePart?)
	local ghostCPs = findConnectionPoints(ghostModel)
	local neighborCPs = findConnectionPoints(neighborModel)
	if #ghostCPs == 0 or #neighborCPs == 0 then
		return nil, nil
	end

	local minDistance = math.huge
	local bestGCP, bestNCP = nil, nil

	for _, gCP in ghostCPs do
		for _, nCP in neighborCPs do
			local dist = (gCP.Position - nCP.Position).Magnitude
			if dist < minDistance then
				minDistance = dist
				bestGCP = gCP
				bestNCP = nCP
			end
		end
	end

	-- Only treat as a valid candidate if the closest pair is reasonably near;
	-- this prevents snapping to walls that are visually far away.
	if minDistance <= SNAP_RADIUS * 2 then
		return bestGCP, bestNCP
	end

	return nil, nil
end

local function areModelsConnected(ghost: Model, other: Model): boolean
	local gCP, nCP = findNearestConnectionPoints(ghost, other)
	if gCP and nCP then
		if (gCP.Position - nCP.Position).Magnitude < CONNECTION_TOLERANCE then
			return true
		end
	end
	return false
end

-- // CORE LOGIC //

local function updateGhostPosition()
	if not (isPlacing and ghostBuilding) then
		return
	end

	local mouseLocation = UserInputService:GetMouseLocation()
	local mouseRay = camera:ScreenPointToRay(mouseLocation.X, mouseLocation.Y)

	local rayParams = RaycastParams.new()
	rayParams.FilterDescendantsInstances = { ghostBuilding, player.Character, debugFolder }
	rayParams.FilterType = Enum.RaycastFilterType.Exclude

	local result = Workspace:Raycast(mouseRay.Origin, mouseRay.Direction * 1000, rayParams)
	if not result then
		return
	end

	local pos = result.Position
	local isWallBuilding = currentBuildingName == "Stone_Wall"
		or currentBuildingName == "Wall_Segment"
		or currentBuildingName == "Wall_Corner"
		or currentBuildingName == "Wall_Corner_Reverse"
		or currentBuildingName == "Wall_Tower"
		or currentBuildingName == "Wall_Gatehouse"
		or currentBuildingName == "Ladder_Wall_Segment"

	-- Grid & Ground
	local gridSize = isWallBuilding and WallGridConfig.GRID_SIZE or 4
	local snappedX = math.floor(pos.X / gridSize + 0.5) * gridSize
	local snappedZ = math.floor(pos.Z / gridSize + 0.5) * gridSize

	local groundRaycastStart = Vector3.new(snappedX, 1000, snappedZ)
	local groundRaycastDir = Vector3.new(0, -2000, 0)
	local groundRaycastParams = RaycastParams.new()
	local groundIgnoreList = { player.Character, ghostBuilding, debugFolder }
	groundRaycastParams.FilterDescendantsInstances = groundIgnoreList
	groundRaycastParams.FilterType = Enum.RaycastFilterType.Exclude

	local groundResult = Workspace:Raycast(groundRaycastStart, groundRaycastDir, groundRaycastParams)
	local groundY = pos.Y
	if groundResult then
		groundY = groundResult.Position.Y
	end

	-- Determine Asset/Rotation
	local bitmask = 0
	if isWallBuilding then
		local checkParams = OverlapParams.new()
		checkParams.FilterDescendantsInstances = groundIgnoreList
		for _, dir in ipairs(DIRECTIONS) do
			local checkPos = Vector3.new(snappedX, groundY, snappedZ)
				+ Vector3.new(dir.x * WallGridConfig.GRID_SIZE, 0, dir.z * WallGridConfig.GRID_SIZE)
			local parts = Workspace:GetPartBoundsInBox(CFrame.new(checkPos), Vector3.new(10, 10, 10), checkParams)
			if #parts > 0 then
				bitmask = bit32.bor(bitmask, dir.bit)
			end
		end
	end

	local assetName, rotation
	if wallPieceIndex > 1 then
		assetName = WALL_PIECES[wallPieceIndex].name
		rotation = WALL_PIECES[wallPieceIndex].rotation + manualRotation
	else
		assetName, rotation = getWallAssetName(bitmask)
		rotation = rotation + manualRotation
	end

	-- Swap Ghost Mesh
	local assets = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Buildings")
	if assets and isWallBuilding then
		local template = assets:FindFirstChild(assetName)
		if template and ghostBuilding.Name ~= assetName then
			ghostBuilding:Destroy()
			ghostBuilding = template:Clone()
			BuildingScaleConfig.applyToModel(ghostBuilding)
			ghostBuilding.Name = assetName
			ghostBuilding.Parent = Workspace
			for _, v in ghostBuilding:GetDescendants() do
				if v:IsA("BasePart") then
					v.Transparency = 0.5
					v.CanCollide = false
					v.Anchored = true
					v.Color = Color3.new(0, 1, 0)
					if v.Name == "ConnectionPoint" then
						v.Anchored = true
						v.Transparency = 0.5
						v.Color = Color3.new(1, 0, 1) -- Debug Pink
					end
				end
			end
		end
	end

	-- // SNAP LOGIC //
	if isWallBuilding then
		local ghostCPs = findConnectionPoints(ghostBuilding)
		local connectedNeighbor = nil
		local bestGCP = nil
		local bestNCP = nil

		-- 1. Initial Grid Placement (Establish Orientation)
		local startHeight = 5
		if #ghostCPs > 0 then
			local pivot = ghostBuilding:GetPivot()
			if ghostCPs[1] then
				local relY = (pivot:Inverse() * ghostCPs[1].CFrame).Y
				startHeight = -relY
			end
		elseif ghostBuilding.PrimaryPart then
			startHeight = ghostBuilding.PrimaryPart.Size.Y / 2
		end

		ghostBuilding:PivotTo(
			CFrame.new(snappedX, groundY + startHeight, snappedZ) * CFrame.Angles(0, math.rad(rotation), 0)
		)

		if #ghostCPs > 0 then
			-- 2. Scan for neighbors
			local neighborParams = OverlapParams.new()
			neighborParams.FilterDescendantsInstances = { ghostBuilding, player.Character, debugFolder }
			neighborParams.FilterType = Enum.RaycastFilterType.Exclude

			local minDist = SNAP_RADIUS

			for _, part in ipairs(nearbyParts) do
				local model = findBuildingModelFromPart(part)
				if model and model ~= ghostBuilding then
					local bType = model:GetAttribute("BuildingType")
					if bType and (bType == "Stone_Wall" or string.find(bType, "Wall") or bType == "Tower") then
						local gCP, nCP = findNearestConnectionPoints(ghostBuilding, model)
						if gCP and nCP then
							local d = (gCP.Position - nCP.Position).Magnitude
							if d < minDist then
								minDist = d
								connectedNeighbor = model
								bestGCP = gCP
								bestNCP = nCP
							end
						end
					end
				end
			end
		end

		-- 3. EXECUTE SNAP
		if connectedNeighbor and bestGCP and bestNCP then
			local snapDist = (bestGCP.Position - bestNCP.Position).Magnitude
			-- A. Calculate Vector Diff for perfect alignment.
			local diffVector = bestNCP.Position - bestGCP.Position
			-- B. Add a small "nudge" to prevent Z-fighting/overlap.
			-- This moves the ghost slightly away from the neighbor along the connection axis.
			local nudgeVector = bestGCP.CFrame.LookVector * CONNECTION_OFFSET
			-- C. Shift Ghost by the combined vector.
			ghostBuilding:PivotTo(ghostBuilding:GetPivot() + diffVector + nudgeVector)
			-- D. Debug
			updateDebugVisuals(bestGCP.Position + diffVector + nudgeVector, bestNCP.Position)
		else
			-- GRID PLACEMENT: No neighbor to snap to.
			-- Use WallGridConfig to properly position the model based on its connection points
			local gridX, gridZ = WallGridConfig.toGrid(Vector3.new(snappedX, 0, snappedZ))
			local modelCFrame = WallGridConfig.getModelCFrame(assetName, gridX, gridZ, rotation)

			if modelCFrame then
				-- Use the precise CFrame from WallGridConfig
				-- Adjust Y position to ground level
				local adjustedCF = CFrame.new(
					modelCFrame.Position.X,
					groundY + modelCFrame.Position.Y - 10, -- Adjust from CP ground level (Y=10) to actual ground
					modelCFrame.Position.Z
				) * (modelCFrame - modelCFrame.Position)

				ghostBuilding:PivotTo(adjustedCF)

				if #ghostCPs > 0 then
					updateDebugVisuals(ghostCPs[1].Position, nil)
				end
			elseif #ghostCPs > 0 then
				-- Fallback to old method if WallGridConfig doesn't have this piece
				local primaryCP = ghostCPs[1]
				local targetPos = Vector3.new(snappedX, groundY, snappedZ)

				local rotatedCF = CFrame.new(ghostBuilding:GetPivot().Position)
					* CFrame.Angles(0, math.rad(rotation), 0)
				ghostBuilding:PivotTo(rotatedCF)

				local currentCPPos = primaryCP.Position
				local diff = targetPos - currentCPPos

				ghostBuilding:PivotTo(ghostBuilding:GetPivot() + diff)
				updateDebugVisuals(primaryCP.Position, nil)
			else
				-- No CPs, just place the pivot on the grid.
				debugFolder:ClearAllChildren()
			end
		end -- Collision Logic
		local collisionIgnore = { ghostBuilding, player.Character, debugFolder }
		if connectedNeighbor then
			table.insert(collisionIgnore, connectedNeighbor)
		end

		local collisionParams = OverlapParams.new()
		collisionParams.FilterDescendantsInstances = collisionIgnore
		collisionParams.FilterType = Enum.RaycastFilterType.Exclude

		local collisionCF, size = getSafeBounds(ghostBuilding)
		local collisions = Workspace:GetPartBoundsInBox(collisionCF, size * 0.8, collisionParams)

		-- Allow wall pieces to collide/overlap with each other.
		-- We only block placement if the ghost intersects with non-wall
		-- geometry (e.g. other buildings, props, terrain).
		canPlace = true
		for _, p in ipairs(collisions) do
			if p.Name ~= "Baseplate" and not p:IsA("Terrain") and p.Name ~= "ConnectionPoint" then
				local pModel = findBuildingModelFromPart(p)
				local isWallNeighbor = false
				if pModel then
					local bType = pModel:GetAttribute("BuildingType")
					if bType and (bType == "Stone_Wall" or string.find(bType, "Wall") or bType == "Tower") then
						isWallNeighbor = true
					end
				end

				-- If this collision is not another wall-type building, block placement.
				if not isWallNeighbor then
					canPlace = false
					break
				end
			end
		end
	else
		-- Non-wall placement (works for both Model ghosts and Part placeholders)
		if ghostBuilding then
			-- First position at ground level to get accurate bounding box
			local tempPos = Vector3.new(snappedX, groundY, snappedZ)
			ghostBuilding:PivotTo(CFrame.new(tempPos) * CFrame.Angles(0, math.rad(manualRotation), 0))

			-- Calculate correct Y position based on bounding box bottom
			local boundingCFrame, boundingSize = getSafeBounds(ghostBuilding)
			local currentPivot = ghostBuilding:GetPivot()

			-- Calculate how far the bottom of the model is from the pivot
			local bottomOffset = (boundingCFrame.Position.Y - boundingSize.Y / 2) - currentPivot.Position.Y

			-- Position so the bottom sits on the ground
			local finalY = groundY - bottomOffset
			local snappedPos = Vector3.new(snappedX, finalY, snappedZ)
			ghostBuilding:PivotTo(CFrame.new(snappedPos) * CFrame.Angles(0, math.rad(manualRotation), 0))
		end

		local collisionParams = OverlapParams.new()
		collisionParams.FilterDescendantsInstances = { ghostBuilding, player.Character, debugFolder }
		collisionParams.FilterType = Enum.RaycastFilterType.Exclude

		local collisionCF, newSize = getSafeBounds(ghostBuilding)
		canPlace = #Workspace:GetPartBoundsInBox(collisionCF, newSize * 0.9, collisionParams) == 0
		if canPlace then
			canPlace = isInPlayerZone(ghostBuilding:GetPivot().Position)
		end
	end

	local color = canPlace and Color3.new(0, 1, 0) or Color3.new(1, 0, 0)
	-- Tint the ghost itself if it is a plain Part placeholder (no descendants)
	if ghostBuilding:IsA("BasePart") then
		ghostBuilding.Color = color
	end
	for _, v in ghostBuilding:GetDescendants() do
		if v:IsA("BasePart") then
			v.Color = color
		end
	end
end

-- Input & Cleanup

-- The ONE writer of `isPlacing`. It mirrors the flag onto ViewMode so the RTS
-- input handlers can see it.
--
-- WHY: right-click was bound twice. This controller cancels the ghost on
-- MouseButton2, and MovementManager's consolidated order dispatcher issues a
-- move/attack on MouseButton2. Both are independent InputBegan listeners, so a
-- single right-click during placement did both — the ghost disappeared AND the
-- selected army walked to the cursor. ViewMode.shouldBlockRTSInput() now reports
-- true while placing, which MovementManager and SelectionManager already honour,
-- so the cancel wins and nothing else fires.
--
-- Every set of isPlacing goes through here precisely so no exit path can forget
-- to clear the shared flag: a stuck-true value disables ALL RTS selection and
-- orders game-wide, which is a much worse bug than the one being fixed.
local HUDStoreRef: any = nil
local function getHUDStore()
	if not HUDStoreRef then
		pcall(function()
			HUDStoreRef = require(player.PlayerScripts.UI.state.HUDStore)
		end)
	end
	return HUDStoreRef
end

local function setPlacing(value: boolean)
	isPlacing = value
	ViewMode.setPlacementActive(value)
	local store = getHUDStore()
	if store then
		if value then
			store.setState({ isPlacingBuilding = true, selectedBuilding = currentBuildingName })
		else
			store.setState({ isPlacingBuilding = false, selectedBuilding = store.None })
		end
	end
end

local function cleanup()
	if ghostBuilding then
		ghostBuilding:Destroy()
	end
	ghostBuilding = nil
	setPlacing(false)
	currentBuildingName = nil
	lastGridTargetPos = nil
	debugFolder:ClearAllChildren()
	gameEvent:FireServer("PlacementEnded")
	wallPieceEvent:Fire({ currentPiece = WALL_PIECES[wallPieceIndex].name, isPlacingWalls = false })
end

-- Installed here rather than at the declaration above because cleanup() is the
-- single exit path every other cancel route already funnels through, and it is
-- only defined by this point.
cancelPlacementEvent.Event:Connect(function()
	if isPlacing then
		cleanup()
	end
end)

local function startPlacement(buildingName: string)
	cleanup()
	local info = GameData.Buildings[buildingName]
	if not info then
		return
	end

	-- NOTE: `isPlacing` is armed at the BOTTOM of this function, once a ghost
	-- actually exists. It used to be set here, which meant any error while
	-- resolving the model asset left the flag true with no ghost to cancel — and
	-- now that the flag also gates RTS input, that would have wedged selection and
	-- move orders for the rest of the session. Failing this direction leaves an
	-- orphan ghost at worst.
	currentBuildingName = buildingName
	manualRotation = 0

	-- This controller only handles non-wall buildings.
	-- The model name should come directly from the building's data definition.
	local assetName = info.model_asset_name

	local assets = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Buildings")
	local template

	if assets and assetName then
		if string.find(assetName, "/") then
			-- Slash-path asset names (e.g. "Siege_Camps/Red_Siege_Camp"): walk the
			-- folder segments, then fall back to a recursive leaf-name search.
			local current: Instance? = assets
			for segment in string.gmatch(assetName, "[^/]+") do
				current = current and current:FindFirstChild(segment)
			end
			template = current
			if not template then
				local leaf = string.match(assetName, "([^/]+)$")
				template = if leaf then assets:FindFirstChild(leaf, true) else nil
			end
		else
			-- Use recursive find (true) to search the whole folder,
			-- which supports asset names that are nested (e.g., "Houses/House_01").
			template = assets:FindFirstChild(assetName, true)
		end
	end

	-- Fallback for legacy buildings that might use their dictionary key as the model name.
	if not template and assets then
		template = assets:FindFirstChild(buildingName, true)
	end

	if template then
		ghostBuilding = template:Clone()
		if ghostBuilding:IsA("Model") then
			BuildingScaleConfig.applyToModel(ghostBuilding)
		end
		ghostBuilding.Name = "GhostBuildingPreview" -- Use a generic name to avoid conflicts
		ghostBuilding.Parent = Workspace
		for _, v in ghostBuilding:GetDescendants() do
			if v:IsA("BasePart") then
				v.Anchored = true
				v.CanCollide = false
				v.Transparency = 0.5
				v.Color = Color3.new(0, 1, 0)
				-- ConnectionPoints aren't used by non-wall buildings, but keeping this is harmless.
				if v.Name == "ConnectionPoint" then
					v.Transparency = 0.5
					v.Color = Color3.new(1, 0, 1)
				end
			end
		end
	else
		-- If no model is found (either by assetName or buildingName), create a placeholder part.
		-- This is the source of the "square" previews and is the expected behavior for
		-- buildings that have `model_asset_name = nil` in their data.
		ghostBuilding = Instance.new("Part")
		ghostBuilding.Name = "Ghost"
		ghostBuilding.Size = (info.size or Vector3.new(4, 4, 4)) * BuildingScaleConfig.GlobalScale
		ghostBuilding.Anchored = true
		ghostBuilding.CanCollide = false
		ghostBuilding.Transparency = 0.5
		ghostBuilding.Parent = Workspace
	end

	-- Ghost exists — now it is safe to claim the mouse.
	setPlacing(true)
end

-- Entering hero view (V toggle) hands the mouse to combat — cancel any active
-- placement so a stray click can't drop a building mid-fight.
--
-- Previously this watched `player.CameraMode`. Hero view is third person now and
-- never changes CameraMode, so that signal stopped firing entirely and a
-- half-placed building would survive into combat, eating the first attack click.
ViewMode.Changed:connect(function(newMode: string)
	if newMode == ViewMode.Modes.Hero and isPlacing then
		PlacementDebug:info("Entered hero view - cancelling active placement")
		cleanup()
	end
end)

-- Dying or respawning mid-placement is an exit path too. Nothing else cancels
-- here: updateGhostPosition filters against `player.Character`, so after a
-- respawn the ghost would keep tracking a destroyed model, and — now that
-- placement gates RTS input — the stuck flag would leave the player unable to
-- select or order anything with no visible cause. Belt and braces on top of
-- setPlacing() being the single writer.
local function cancelOnCharacterLoss(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Died:Connect(function()
			if isPlacing then
				PlacementDebug:info("Character died - cancelling active placement")
				cleanup()
			end
		end)
	end
end

if player.Character then
	cancelOnCharacterLoss(player.Character)
end
player.CharacterRemoving:Connect(function()
	if isPlacing then
		PlacementDebug:info("Character removing - cancelling active placement")
		cleanup()
	end
end)
player.CharacterAdded:Connect(cancelOnCharacterLoss)

local function resetWallPieceSelection()
	wallPieceIndex = 1
	wallPieceEvent:Fire({
		currentPiece = WALL_PIECES[wallPieceIndex].name,
		isPlacingWalls = isPlacing and (currentBuildingName == "Stone_Wall" or currentBuildingName == "Wall_Segment"),
	})
end
resetWallPieceFunc.OnInvoke = resetWallPieceSelection

UserInputService.InputBegan:Connect(function(input, gp)
	if not isPlacing then
		return
	end
	if input.KeyCode == KeybindingsManager.GetKeybinding("RotatePlacement") then
		manualRotation = (manualRotation + 90) % 360
		if currentBuildingName and (currentBuildingName == "Stone_Wall" or currentBuildingName == "Wall_Segment") then
			local rad = math.rad(manualRotation)
			wallChainDirection = Vector3.new(math.cos(rad), 0, math.sin(rad))
		end
	elseif input.KeyCode == KeybindingsManager.GetKeybinding("CyclePlacementType") then
		if currentBuildingName and (currentBuildingName == "Stone_Wall" or currentBuildingName == "Wall_Segment") then
			wallPieceIndex = (wallPieceIndex % #WALL_PIECES) + 1
			wallPieceEvent:Fire({ currentPiece = WALL_PIECES[wallPieceIndex].name, isPlacingWalls = true })
		end
	elseif input.UserInputType == Enum.UserInputType.MouseButton1 and not gp then
		if canPlace and ghostBuilding then
			local pivot = ghostBuilding:GetPivot()
			local pieceType = (wallPieceIndex > 1) and WALL_PIECES[wallPieceIndex].name or nil
			local data = {
				buildingName = currentBuildingName,
				position = pivot.Position,
				cframe = pivot,
				manualRotation = manualRotation,
				wallPieceType = pieceType,
			}
			gameEvent:FireServer("PlaceBuilding", data)

			local isWall = currentBuildingName == "Stone_Wall" or currentBuildingName == "Wall_Segment"
			if isWall then
				lastPlacedWallPosition = pivot.Position
				lastPlacedWallRotation = pivot.Rotation.Y
				local rad = math.rad(manualRotation)
				wallChainDirection = Vector3.new(math.cos(rad), 0, math.sin(rad))
			else
				cleanup()
			end
		end
	elseif input.KeyCode == Enum.KeyCode.Escape or input.UserInputType == Enum.UserInputType.MouseButton2 then
		cleanup()
	end
end)

gameEvent.OnClientEvent:Connect(function(act, data)
	if act == "GameStarted" then
		if data and data.zoneCenter then
			playerZoneCenter = data.zoneCenter
			playerZoneRadius = data.zoneRadius
		end
	elseif act == "StartPlacement" then
		-- Check if this is a wall building - if so, let WallBuilderController handle it
		local isWallBuilding = data == "Stone_Wall" or string.find(tostring(data), "Wall")

		if not isWallBuilding then
			-- Cancel any active wall placement before starting regular building placement
			gameEvent:FireServer("PlacementEnded")
			-- Start regular building placement
			startPlacement(data)
		else
			-- Cancel regular placement before starting wall placement.
			-- Must go through setPlacing: WallBuilderController takes the mouse from
			-- here, and leaving the shared placement flag true would freeze RTS
			-- selection and orders for the rest of the session.
			if isPlacing then
				setPlacing(false)
				if ghostBuilding then
					ghostBuilding:Destroy()
					ghostBuilding = nil
				end
			end
		end
		-- Wall buildings are handled by WallBuilderController.client.luau
	end
end)

RunService.RenderStepped:Connect(updateGhostPosition)

return {
	resetWallPieceSelection = resetWallPieceSelection,
	getCurrentWallPiece = function()
		return WALL_PIECES[wallPieceIndex].name
	end,
	getWallPieceIndex = function()
		return wallPieceIndex
	end,
	isPlacingWalls = function()
		return isPlacing
	end,
}
