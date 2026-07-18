--!strict
-- WallBuilderController - Integrated from working test system
-- Features: Smart Snapping, Drag Building, Path Generation

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local mouse = player:GetMouse()
local camera = Workspace.CurrentCamera

-- === ASSETS & EVENTS ===
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local gameEvent = RemoteEvents:WaitForChild("GameEvent")
local placePathEvent = RemoteEvents:WaitForChild("PlaceWallPath")
local removePieceEvent = RemoteEvents:WaitForChild("RemoveWallPiece")

local Assets = ReplicatedStorage:WaitForChild("Assets")
local Buildings = Assets:WaitForChild("Buildings")

-- Wait for GetWallEndpoints RemoteFunction (may be created by server)
local getEndpointsEvent: RemoteFunction? = nil

-- === CONFIGURATION ===
local CONFIG = {
	GridSize = 4,
	MinCameraDistance = 20,
	MaxCameraDistance = 300,
	SnapDistance = 40, -- Increased from 24 to 40 for much more pronounced magnetic snapping

	-- Input bindings (the mode UI derives its key labels from these)
	Keybinds = {
		Rotate = Enum.KeyCode.R,
		Continue = Enum.KeyCode.C,
		ToggleMode = Enum.KeyCode.B,
		ConfirmPath = Enum.KeyCode.Return,
	},

	-- Dimensions (based on actual model sizes from debug)
	WallLengthLong = 16, -- Stone_Wall_Straight is 16.0 studs wide
	WallLengthShort = 10, -- Stone_Wall_Short_Straight is 10.0 studs wide
	TowerRadius = 12, -- Stone_Wall_Small_Tower is 24.0 studs (radius = 12)
	GatehouseSpacing = 58, -- Stone_Wall_Gatehouse is 58.5 studs wide

	-- How corner towers are oriented:
	-- "Keep"   = face the player's zone center (keep), snapped to 45° — consistent look everywhere
	-- "Axis"   = corner rotation snapped to nearest 90° — aligns with the tower's cardinal connection points
	-- "Corner" = legacy dirIn/dirOut rotation (poor at 45° corners)
	TowerFacing = "Keep",

	PieceTypes = {
		Tower = "Stone_Wall_Small_Tower",
		Tower45 = "Stone_Wall_Small_Tower_90_to_45", -- 45° corner variant (faces 135° apart)
		Straight = "Stone_Wall_Straight",
		Short = "Stone_Wall_Short_Straight",
		Corner = "Stone_Wall_Small_Tower", -- No corner model, use tower
		Gatehouse = "Stone_Wall_Gatehouse",
		Ladder = "Stone_Wall_Ladder",
	},
}

-- === STATE ===
local selectedPiece: string? = nil
local isDragging = false
local startPosition: Vector3? = nil
local startIncomingDir: Vector3? = nil
local currentRotation = 0
local manualRotationOffset = 0 -- Manual rotation adjustment on top of snap rotation
local previewModels: { Model } = {}
local snapIndicators: { Part } = {}
local wallEndpoints: { { position: Vector3, incomingDir: Vector3 } } = {}
local lastWallEndpoint: Vector3? = nil
local lastWallDir: Vector3? = nil
local isPlacingWalls = false
local isDeleteModeActive = false -- Track delete mode from HUD

-- === POLYGON PLOT MODE STATE ===
-- "Drag" = classic click-and-drag path building
-- "Polygon" = click-to-plot nodes; towers auto-inserted at corners; close loop or Enter to confirm
type BuildMode = "Drag" | "Polygon"
local buildMode: BuildMode = "Polygon" -- Polygon plot is the default wall-building mode

type PolyNode = {
	position: Vector3,
	incomingDir: Vector3?, -- set when this node was snapped to an existing wall endpoint (wall-off anchor)
	groundY: number,
}
local polygonNodes: { PolyNode } = {}
local committedPreviewModels: { Model } = {} -- cached ghosts for already-plotted segments
local committedPreviewDirty = true

-- Zone bounds (set on GameStarted)
local playerZoneCenter: Vector3? = nil
local playerZoneRadius: number? = nil

local function isInPlayerZone(pos: Vector3): boolean
	if not playerZoneCenter or not playerZoneRadius then return true end
	local dx = pos.X - playerZoneCenter.X
	local dz = pos.Z - playerZoneCenter.Z
	return (dx * dx + dz * dz) <= (playerZoneRadius * playerZoneRadius)
end

-- === UTILITIES ===

local function snapToGrid(position: Vector3): Vector3
	return Vector3.new(
		math.round(position.X / CONFIG.GridSize) * CONFIG.GridSize,
		position.Y,
		math.round(position.Z / CONFIG.GridSize) * CONFIG.GridSize
	)
end

local function getWallEndpoints(centerPos: Vector3, rotation: number, length: number): (Vector3, Vector3)
	local cf = CFrame.new(centerPos) * CFrame.Angles(0, rotation, 0)
	local direction = cf.RightVector
	return centerPos - (direction * (length / 2)), centerPos + (direction * (length / 2))
end

local function getIgnoreList(): { Instance }
	local list: { Instance } = { camera, player.Character }
	for _, m in ipairs(previewModels) do
		table.insert(list, m)
	end
	for _, m in ipairs(committedPreviewModels) do
		table.insert(list, m)
	end
	return list
end

local function getGroundHeight(position: Vector3): number
	local params = RaycastParams.new()
	local ignore = getIgnoreList()
	local placedWalls = Workspace:FindFirstChild("Buildings") or Workspace:FindFirstChild("PlacedWalls")
	if placedWalls then
		table.insert(ignore, placedWalls)
	end

	params.FilterDescendantsInstances = ignore
	params.FilterType = Enum.RaycastFilterType.Exclude

	local result = Workspace:Raycast(position + Vector3.new(0, 100, 0), Vector3.new(0, -200, 0), params)
	return result and result.Position.Y or 0
end

local function getMouseRay(): (Vector3, Vector3)
	local unitRay = camera:ScreenPointToRay(mouse.X, mouse.Y)
	return unitRay.Origin, unitRay.Direction * CONFIG.MaxCameraDistance
end

local function calculateCornerRotation(dirIn: Vector3, dirOut: Vector3): number
	local baseAngle = math.atan2(dirIn.X, dirIn.Z)
	local crossY = dirIn:Cross(dirOut).Y
	if crossY < -0.1 then
		return baseAngle + math.rad(180) -- Right Turn
	else
		return baseAngle + math.rad(90) -- Left Turn / Straight
	end
end

-- Single source of truth for corner tower orientation (see CONFIG.TowerFacing)
local function computeTowerRotation(position: Vector3, dirIn: Vector3, dirOut: Vector3?): number
	-- Wall alignment: the tower's faces sit flush with the incoming wall
	local wallAngle = math.atan2(dirIn.X, dirIn.Z)

	if CONFIG.TowerFacing == "Keep" and playerZoneCenter then
		local toKeep = Vector3.new(playerZoneCenter.X - position.X, 0, playerZoneCenter.Z - position.Z)
		if toKeep.Magnitude > 0.001 then
			-- Stay wall-aligned, but of the four 90°-symmetric orientations,
			-- pick the one whose front points closest to the keep
			local keepAngle = math.atan2(toKeep.X, toKeep.Z)
			local delta = keepAngle - wallAngle
			local snappedDelta = math.round(delta / math.rad(90)) * math.rad(90)
			return wallAngle + snappedDelta
		end
	end

	-- Base rotation from the walls meeting at this vertex
	local base: number
	if dirOut then
		base = calculateCornerRotation(dirIn, dirOut)
	else
		base = wallAngle + math.rad(90)
	end

	if CONFIG.TowerFacing == "Axis" then
		-- Snap to cardinal so the tower's connection points line up with the grid
		return math.round(base / math.rad(90)) * math.rad(90)
	end

	return base -- "Corner" (legacy), also the fallback before the zone center is known
end

-- === MARKER-BASED TOWER ROTATION ===
-- Reads the actual ConnectionPoint markers from the tower templates instead of
-- assuming face bearings, so rotation always matches the real model geometry
-- (doorways line up with the walls).

local function angleDiff(a: number, b: number): number
	return math.abs(((a - b + math.pi) % (2 * math.pi)) - math.pi)
end

type TowerFaceData = { bearings: { number }, doorBearing: number? }
local towerFaceCache: { [string]: TowerFaceData } = {}

local function getTowerFaceData(pieceType: string): TowerFaceData
	local cached = towerFaceCache[pieceType]
	if cached then
		return cached
	end

	-- Fallbacks if the template has no markers
	local data: TowerFaceData = {
		bearings = if pieceType == "Tower45"
			then { 0, math.rad(135) }
			else { 0, math.rad(90), math.rad(180), math.rad(270) },
		doorBearing = nil,
	}

	local template = Buildings:FindFirstChild(CONFIG.PieceTypes[pieceType])
	if template and template:IsA("Model") then
		local pivot = template:GetPivot()
		local folder = template:FindFirstChild("ConnectionPoints")
		if folder then
			local found: { number } = {}
			for _, cp in ipairs(folder:GetChildren()) do
				if cp:IsA("BasePart") and cp.Name == "ConnectionPoint" then
					local localPos = pivot:PointToObjectSpace(cp.Position)
					local flat = Vector3.new(localPos.X, 0, localPos.Z)
					if flat.Magnitude > 0.05 then
						table.insert(found, math.atan2(flat.X, flat.Z))
					end
				end
			end
			if #found >= 2 then
				data.bearings = found
			end
		end
		local gd = template:FindFirstChild("GroundDoor")
		if gd and gd:IsA("BasePart") then
			local localPos = pivot:PointToObjectSpace(gd.Position)
			local flat = Vector3.new(localPos.X, 0, localPos.Z)
			if flat.Magnitude > 0.05 then
				data.doorBearing = math.atan2(flat.X, flat.Z)
			end
		end
	end

	towerFaceCache[pieceType] = data
	return data
end

-- Finds the model rotation that puts a marker face on EVERY required world bearing.
-- When multiple rotations work (symmetric models), the one whose ground door
-- faces closest to the keep wins. Returns nil if no rotation fits.
local function solveTowerRotation(pieceType: string, required: { number }, position: Vector3): number?
	local data = getTowerFaceData(pieceType)
	local locals = data.bearings

	local candidates: { number } = {}
	for _, l in ipairs(locals) do
		local r = required[1] - l
		local allMatched = true
		for _, req in ipairs(required) do
			local matched = false
			for _, l2 in ipairs(locals) do
				if angleDiff(l2 + r, req) < math.rad(5) then
					matched = true
					break
				end
			end
			if not matched then
				allMatched = false
				break
			end
		end
		if allMatched then
			local dup = false
			for _, c in ipairs(candidates) do
				if angleDiff(c, r) < math.rad(1) then
					dup = true
					break
				end
			end
			if not dup then
				table.insert(candidates, r)
			end
		end
	end

	if #candidates == 0 then
		return nil
	end
	if #candidates == 1 or not playerZoneCenter then
		return candidates[1]
	end

	-- Tie-break symmetric candidates: ground door toward the keep
	local doorLocal = data.doorBearing or 0
	local toKeep = Vector3.new(playerZoneCenter.X - position.X, 0, playerZoneCenter.Z - position.Z)
	if toKeep.Magnitude < 0.001 then
		return candidates[1]
	end
	local keepBearing = math.atan2(toKeep.X, toKeep.Z)

	local best, bestErr = candidates[1], math.huge
	for _, r in ipairs(candidates) do
		local err = angleDiff(doorLocal + r, keepBearing)
		if err < bestErr then
			best, bestErr = r, err
		end
	end
	return best
end

-- === SNAP LOGIC ===

local function registerWallEndpoints(startPos: Vector3, endPos: Vector3)
	local dir = (endPos - startPos).Unit
	table.insert(wallEndpoints, { position = startPos, incomingDir = -dir })
	table.insert(wallEndpoints, { position = endPos, incomingDir = dir })
end

local function findNearbyWallEndpoints(flatMouse: Vector3): (Vector3?, Vector3?)
	local nearestEndpoint: Vector3? = nil
	local nearestDir: Vector3? = nil
	local nearestDistance = CONFIG.SnapDistance

	for _, endpoint in ipairs(wallEndpoints) do
		local flatEndpoint = Vector3.new(endpoint.position.X, 0, endpoint.position.Z)
		local dist = (flatEndpoint - flatMouse).Magnitude

		if dist < nearestDistance then
			nearestDistance = dist
			nearestEndpoint = endpoint.position
			nearestDir = endpoint.incomingDir
		end
	end
	return nearestEndpoint, nearestDir
end

local function findWallIntersection(): (Vector3?, Vector3?, boolean)
	local origin, direction = getMouseRay()
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { camera, player.Character }
	for _, m in ipairs(previewModels) do
		table.insert(params.FilterDescendantsInstances, m)
	end
	params.FilterType = Enum.RaycastFilterType.Exclude

	local result = Workspace:Raycast(origin, direction, params)

	if result and result.Instance then
		local model = result.Instance:FindFirstAncestor("Buildings") and result.Instance:FindFirstAncestorOfClass("Model")
		if model and model.PrimaryPart then
			local cf = model:GetPrimaryPartCFrame()
			local wallLine = cf.RightVector
			local toHit = result.Position - cf.Position
			local projection = wallLine * toHit:Dot(wallLine)
			local intersectPos = snapToGrid(cf.Position + projection)
			return intersectPos, wallLine, true
		end
	end
	return nil, nil, false
end

local function getSmartSnap(rawMousePos: Vector3): (Vector3?, Vector3?, boolean)
	local flatMouse = Vector3.new(rawMousePos.X, 0, rawMousePos.Z)
	local endPos, endDir = findNearbyWallEndpoints(flatMouse)
	if endPos then
		return endPos, endDir, false
	end

	local intPos, intDir, isInt = findWallIntersection()
	if intPos then
		return intPos, intDir, true
	end

	return nil, nil, false
end

-- === PATH GENERATION ===
type PathPoint = {
	position: Vector3,
	type: string,
	rotation: number,
}

-- Fills a straight leg with Long then Short pieces (last Short may overlap remainder)
local function fillLegPieces(path: { PathPoint }, p1: Vector3, dir: Vector3, len: number, angle: number)
	local remaining = len
	local pos = 0
	while remaining >= CONFIG.WallLengthLong do
		table.insert(path, {
			position = p1 + (dir * (pos + CONFIG.WallLengthLong / 2)),
			type = "Straight",
			rotation = angle,
		})
		pos = pos + CONFIG.WallLengthLong
		remaining = remaining - CONFIG.WallLengthLong
	end
	while remaining >= CONFIG.WallLengthShort do
		table.insert(path, {
			position = p1 + (dir * (pos + CONFIG.WallLengthShort / 2)),
			type = "Short",
			rotation = angle,
		})
		pos = pos + CONFIG.WallLengthShort
		remaining = remaining - CONFIG.WallLengthShort
	end
	if remaining > 0 then
		table.insert(path, {
			position = p1 + (dir * (pos + CONFIG.WallLengthShort / 2)),
			type = "Short",
			rotation = angle,
		})
	end
end

local function calculateSmartWallPath(
	startPos: Vector3,
	endPos: Vector3,
	startDirIn: Vector3?,
	isEndIntersection: boolean
): ({ PathPoint }, boolean)
	local path: { PathPoint } = {}
	local valid = true
	local currentStart = startPos

	-- A. HANDLE START CORNER
	if startDirIn then
		local dragDir = (endPos - startPos)
		if dragDir.Magnitude > CONFIG.GridSize then
			local dot = math.abs(startDirIn:Dot(dragDir.Unit))
			if dot < 0.5 then
				local towerRot = calculateCornerRotation(startDirIn, dragDir.Unit)
				table.insert(path, { position = startPos, type = "Tower", rotation = towerRot })
				currentStart = startPos + (dragDir.Unit * CONFIG.TowerRadius)
			end
		end
	end

	-- B. HANDLE END T-JUNCTION
	local finalPos = endPos
	if isEndIntersection then
		local dirToEnd = (endPos - currentStart).Unit
		finalPos = endPos - (dirToEnd * CONFIG.TowerRadius)
	end

	-- C. GENERATE WALLS (L-SHAPE)
	local dX = finalPos.X - currentStart.X
	local dZ = finalPos.Z - currentStart.Z
	local legs: {
		{
			p1: Vector3,
			dir: Vector3,
			len: number,
			angle: number,
		}
	} = {}
	local isLShape = (math.abs(dX) > CONFIG.GridSize * 2 and math.abs(dZ) > CONFIG.GridSize * 2)

	if isLShape then
		local cornerPos: Vector3
		local leg1Dir: Vector3
		local leg2Dir: Vector3

		if math.abs(dX) >= math.abs(dZ) then
			cornerPos = Vector3.new(finalPos.X, currentStart.Y, currentStart.Z)
		else
			cornerPos = Vector3.new(currentStart.X, currentStart.Y, finalPos.Z)
		end

		leg1Dir = (cornerPos - currentStart).Unit
		leg2Dir = (finalPos - cornerPos).Unit

		table.insert(legs, {
			p1 = currentStart,
			dir = leg1Dir,
			len = (cornerPos - currentStart).Magnitude - CONFIG.TowerRadius,
			angle = math.atan2(leg1Dir.X, leg1Dir.Z) + math.rad(90),
		})

		local elbowRot = calculateCornerRotation(leg1Dir, leg2Dir)
		table.insert(path, { position = cornerPos, type = "Tower", rotation = elbowRot })

		table.insert(legs, {
			p1 = cornerPos + leg2Dir * CONFIG.TowerRadius,
			dir = leg2Dir,
			len = (finalPos - cornerPos).Magnitude,
			angle = math.atan2(leg2Dir.X, leg2Dir.Z) + math.rad(90),
		})
	else
		local dir = (finalPos - currentStart).Unit
		table.insert(legs, {
			p1 = currentStart,
			dir = dir,
			len = (finalPos - currentStart).Magnitude,
			angle = math.atan2(dir.X, dir.Z) + math.rad(90),
		})
	end

	for _, leg in ipairs(legs) do
		fillLegPieces(path, leg.p1, leg.dir, leg.len, leg.angle)
	end

	if isEndIntersection then
		local incDir = (endPos - currentStart).Unit
		local endRot = math.atan2(incDir.X, incDir.Z) + math.rad(90)
		table.insert(path, { position = endPos, type = "Tower", rotation = endRot })
	end

	return path, valid
end

-- === POLYGON PLOT MODE ===

-- Polygon mode only applies to linear pieces; Towers/Gatehouses stay click-to-place
local function isLinearPiece(piece: string?): boolean
	return piece == "Straight" or piece == "Short" or piece == "Ladder"
end

-- Snaps the cursor to a 45° increment direction from the last node (covers 90° too),
-- with the length quantized to the grid
local function snapPolygonCursor(lastNode: Vector3, rawPos: Vector3): Vector3
	local delta = Vector3.new(rawPos.X - lastNode.X, 0, rawPos.Z - lastNode.Z)
	local dist = delta.Magnitude
	if dist < 0.001 then
		return lastNode
	end
	local angle = math.atan2(delta.X, delta.Z)
	local snappedAngle = math.round(angle / math.rad(45)) * math.rad(45)
	local dir = Vector3.new(math.sin(snappedAngle), 0, math.cos(snappedAngle))
	local len = math.max(math.round(dist / CONFIG.GridSize) * CONFIG.GridSize, 0)
	return Vector3.new(lastNode.X, rawPos.Y, lastNode.Z) + dir * len
end

-- Resolves the polygon cursor position with priority:
-- 1. close-loop snap to first node, 2. existing wall endpoint/intersection, 3. 45° snap from last node, 4. grid
-- Returns (cursorPos, wallSnapDir?, canCloseLoop)
local function getPolygonCursor(): (Vector3, Vector3?, boolean)
	local origin, dirRay = getMouseRay()
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = getIgnoreList()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local hit = Workspace:Raycast(origin, dirRay, params)
	local rawPos = hit and hit.Position or (camera.CFrame.Position + camera.CFrame.LookVector * 100)

	-- 1. Close-loop snap (needs at least 3 nodes to form an enclosure)
	if #polygonNodes >= 3 then
		local first = polygonNodes[1].position
		local flatDist = Vector3.new(rawPos.X - first.X, 0, rawPos.Z - first.Z).Magnitude
		if flatDist <= CONFIG.GridSize * 2 then
			return first, nil, true
		end
	end

	-- 2. Smart snap to existing wall endpoints / intersections (wall-off anchoring)
	local snapPos, snapDir, _ = getSmartSnap(rawPos)
	if snapPos then
		return snapPos, snapDir, false
	end

	-- 3. 45° angle snap relative to the last plotted node
	if #polygonNodes > 0 then
		return snapPolygonCursor(polygonNodes[#polygonNodes].position, rawPos), nil, false
	end

	-- 4. Plain grid snap for the first node
	return snapToGrid(rawPos), nil, false
end

-- Classifies a corner by the angle between its two connection faces and
-- returns the tower variant + exact rotation, or nil (no tower) / invalid (hairpin).
-- faceA points along the wall arriving at the vertex, faceB along the wall leaving,
-- both pointing AWAY from the vertex.
--   faces ~180° apart -> walls pass straight through, no tower
--   faces ~135° apart -> 45° corner  -> Tower45 (model faces at local 0° and 135°)
--   faces ~90° apart  -> 90° corner  -> Tower (existing)
--   faces ~45° apart  -> hairpin turn -> INVALID, build refused
type TowerSpec = { pieceType: string, rotation: number }

local function classifyCorner(faceA: Vector3, faceB: Vector3, position: Vector3): (TowerSpec?, boolean)
	local dot = faceA:Dot(faceB)

	if dot <= -0.92 then
		-- ~180°: collinear continuation
		return nil, true
	elseif dot <= -0.38 then
		-- ~135°: 45° corner. Rotation solved against the model's REAL marker faces.
		local bearingA = math.atan2(faceA.X, faceA.Z)
		local bearingB = math.atan2(faceB.X, faceB.Z)
		local rotation = solveTowerRotation("Tower45", { bearingA, bearingB }, position)
		if not rotation then
			return nil, false -- model faces can't fit this corner; refuse rather than place twisted
		end
		return { pieceType = "Tower45", rotation = rotation }, true
	elseif dot <= 0.38 then
		-- ~90°: standard corner tower; marker-solved, keep-facing tie-break,
		-- legacy math as fallback if the template has no usable markers
		local bearingA = math.atan2(faceA.X, faceA.Z)
		local bearingB = math.atan2(faceB.X, faceB.Z)
		local rotation = solveTowerRotation("Tower", { bearingA, bearingB }, position)
			or computeTowerRotation(position, -faceA, faceB)
		return { pieceType = "Tower", rotation = rotation }, true
	else
		-- ~45° or degenerate: banned
		return nil, false
	end
end

-- Builds a full piece path from an ordered list of vertices.
-- Every direction change gets the correct tower variant (90° or 45° corner)
-- with exact rotation; adjacent legs are shortened by TowerRadius so pieces
-- don't clip. Hairpin turns (135°) make the whole path invalid (returns {}).
-- Pieces are emitted in spatial order (tower -> leg -> tower -> leg ...) so the
-- server's consecutive-gap validation always passes.
local function buildPolygonPath(
	points: { Vector3 },
	firstDirIn: Vector3?, -- direction into vertex 1 (existing wall anchor or previous segment)
	closed: boolean,
	endAnchorDir: Vector3? -- set when the last vertex snapped to an existing wall endpoint
): { PathPoint }
	local path: { PathPoint } = {}
	local n = #points
	if n < 2 then
		return path
	end

	local segCount = if closed then n else n - 1
	local dirs: { Vector3 } = {}
	for i = 1, segCount do
		local j = (i % n) + 1
		local d = Vector3.new(points[j].X - points[i].X, 0, points[j].Z - points[i].Z)
		if d.Magnitude < 0.001 then
			return {} -- degenerate segment; refuse to build
		end
		dirs[i] = d.Unit
	end

	-- Decide which vertices get corner towers (and which variant)
	-- Face convention: each face points AWAY from the vertex along its wall.
	local towers: { [number]: TowerSpec } = {}
	for i = 1, n do
		local faceA: Vector3? -- along the wall arriving at this vertex
		local faceB: Vector3? -- along the wall leaving this vertex
		if closed then
			faceA = -dirs[if i == 1 then segCount else i - 1]
			faceB = dirs[i]
		else
			if i == 1 then
				-- firstDirIn points INTO the vertex (existing wall's incomingDir)
				faceA = if firstDirIn then -firstDirIn else nil
				faceB = dirs[1]
			elseif i <= segCount then
				faceA = -dirs[i - 1]
				faceB = dirs[i]
			else
				-- open end; endAnchorDir points INTO the vertex along the existing wall
				faceA = -dirs[i - 1]
				faceB = if endAnchorDir then -endAnchorDir else nil
			end
		end

		if faceA and faceB then
			local spec, valid = classifyCorner(faceA, faceB, points[i])
			if not valid then
				return {} -- hairpin turn somewhere in the path: refuse to build
			end
			towers[i] = spec
		end
	end

	-- Emit towers and legs in spatial order
	for i = 1, segCount do
		local j = (i % n) + 1
		local spec = towers[i]
		if spec then
			table.insert(path, { position = points[i], type = spec.pieceType, rotation = spec.rotation })
		end
		local rStart = if towers[i] then CONFIG.TowerRadius else 0
		local rEnd = if towers[j] then CONFIG.TowerRadius else 0
		local legStart = points[i] + dirs[i] * rStart
		local legLen = (points[j] - points[i]).Magnitude - rStart - rEnd
		if legLen >= CONFIG.WallLengthShort * 0.5 then
			local angle = math.atan2(dirs[i].X, dirs[i].Z) + math.rad(90)
			fillLegPieces(path, legStart, dirs[i], legLen, angle)
		end
	end
	local endSpec = if not closed then towers[n] else nil
	if endSpec then
		table.insert(path, { position = points[n], type = endSpec.pieceType, rotation = endSpec.rotation })
	end

	return path
end

local function resetPolygonState()
	polygonNodes = {}
	for _, g in ipairs(committedPreviewModels) do
		g:Destroy()
	end
	committedPreviewModels = {}
	committedPreviewDirty = true
end

-- === UPDATE LOOP ===

local function getActivePath(): ({ PathPoint }, boolean)
	if not selectedPiece then
		return {}, false
	end

	local rawMouse = getMouseRay()
	local hitOrigin, hitDir = getMouseRay()
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = getIgnoreList()
	local hit = Workspace:Raycast(hitOrigin, hitDir, params)
	local rawPos = hit and hit.Position or (camera.CFrame.Position + camera.CFrame.LookVector * 100)

	local snappedPos = snapToGrid(rawPos)
	local snapPos, snapDir, isIntersection = getSmartSnap(rawPos)
	local currentPos = snapPos or snappedPos

	local dist = startPosition and (currentPos - startPosition).Magnitude or 0

	-- Single Click / Hover
	if not isDragging or not startPosition or dist < CONFIG.GridSize then
		local rot = currentRotation
		local finalPos = currentPos

		if snapDir then
			-- Calculate base rotation from snap direction
			rot = math.atan2(snapDir.X, snapDir.Z) + math.rad(90)

			-- Apply manual rotation offset on top of snap rotation
			rot = rot + manualRotationOffset

			-- Offset large pieces so they align with wall endpoints
			if selectedPiece == "Gatehouse" then
				-- Gatehouse is 58.5 studs wide with pivot at walkway (like regular walls)
				-- Regular wall is 16 studs wide
				-- Offset = (gatehouse_width - wall_width) / 2 to align the gatehouse edge with wall edge
				local offset = (CONFIG.GatehouseSpacing - CONFIG.WallLengthLong) / 2
				finalPos = currentPos + snapDir * offset
			elseif selectedPiece == "Tower" then
				-- Tower is 24 studs wide (radius 12)
				-- No offset needed - tower center should be at wall endpoint for proper corner placement
				finalPos = currentPos
			end
		end

		return { { position = finalPos, type = selectedPiece, rotation = rot } }, isInPlayerZone(finalPos)
	end

	-- Dragging
	local dragPath: { PathPoint }
	local dragValid: boolean
	if selectedPiece == "Straight" or selectedPiece == "Short" then
		dragPath, dragValid = calculateSmartWallPath(startPosition, currentPos, startIncomingDir, isIntersection)
	else
		dragPath = { { position = currentPos, type = selectedPiece, rotation = currentRotation } }
		dragValid = true
	end
	if dragValid then
		for _, pt in ipairs(dragPath) do
			if not isInPlayerZone(pt.position) then
				dragValid = false
				break
			end
		end
	end
	return dragPath, dragValid
end

-- === MODE INDICATOR UI ===
-- Lightweight imperative GUI owned by this controller (palette matches UIConfig)

local KEY_DISPLAY: { [string]: string } = {
	Return = "Enter",
}

local function keyName(key: Enum.KeyCode): string
	return KEY_DISPLAY[key.Name] or key.Name
end

local modeGui: ScreenGui? = nil
local modeLabel: TextLabel? = nil
local hintLabel: TextLabel? = nil
local lastModeText = ""
local lastHintText = ""

local function ensureModeUI()
	if modeGui then
		return
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "WallBuildModeUI"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 10
	gui.Enabled = false

	local frame = Instance.new("Frame")
	frame.Name = "Container"
	frame.AnchorPoint = Vector2.new(0.5, 1)
	frame.Position = UDim2.new(0.5, 0, 1, -150) -- sits above the bottom build bar
	frame.Size = UDim2.new(0, 520, 0, 62)
	frame.BackgroundColor3 = Color3.fromRGB(76, 62, 62) -- Tundora (matches UIConfig)
	frame.BackgroundTransparency = 0.15
	frame.BorderSizePixel = 0
	frame.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(218, 165, 32) -- AccentGold
	stroke.Thickness = 1.5
	stroke.Transparency = 0.3
	stroke.Parent = frame

	local mode = Instance.new("TextLabel")
	mode.Name = "ModeLabel"
	mode.Size = UDim2.new(1, -16, 0, 28)
	mode.Position = UDim2.new(0, 8, 0, 4)
	mode.BackgroundTransparency = 1
	mode.Font = Enum.Font.GothamBold
	mode.TextSize = 18
	mode.TextColor3 = Color3.fromRGB(218, 165, 32) -- AccentGold
	mode.TextXAlignment = Enum.TextXAlignment.Center
	mode.Text = ""
	mode.Parent = frame

	local hint = Instance.new("TextLabel")
	hint.Name = "HintLabel"
	hint.Size = UDim2.new(1, -16, 0, 22)
	hint.Position = UDim2.new(0, 8, 0, 34)
	hint.BackgroundTransparency = 1
	hint.Font = Enum.Font.Gotham
	hint.TextSize = 14
	hint.TextColor3 = Color3.fromRGB(199, 166, 122) -- StatTextColor (Tan)
	hint.TextXAlignment = Enum.TextXAlignment.Center
	hint.Text = ""
	hint.Parent = frame

	gui.Parent = player:WaitForChild("PlayerGui")
	modeGui = gui
	modeLabel = mode
	hintLabel = hint
end

local function setModeUIVisible(visible: boolean)
	ensureModeUI()
	if modeGui then
		modeGui.Enabled = visible
	end
end

local function updateModeUI(canClose: boolean)
	if not modeGui or not modeGui.Enabled or not modeLabel or not hintLabel then
		return
	end

	local kb = CONFIG.Keybinds
	local modeText: string
	local hintText: string

	if not isLinearPiece(selectedPiece) then
		modeText = string.format("Placing: %s", selectedPiece or "")
		hintText = string.format("Click to place  •  [%s] rotate  •  Right-Click cancel", keyName(kb.Rotate))
	elseif buildMode == "Polygon" then
		modeText = string.format("Wall Mode: POLYGON  •  [%s] switch to Drag", keyName(kb.ToggleMode))
		if #polygonNodes == 0 then
			hintText = "Click to plot your first node"
		elseif #polygonNodes == 1 then
			hintText = "Click to plot nodes  •  Right-Click undo"
		elseif canClose then
			hintText = "Click to CLOSE THE LOOP and build!"
		else
			hintText = string.format(
				"[%s] place wall  •  Click first node to close loop  •  Right-Click undo",
				keyName(kb.ConfirmPath)
			)
		end
	else
		modeText = string.format("Wall Mode: DRAG  •  [%s] switch to Polygon", keyName(kb.ToggleMode))
		hintText = string.format(
			"Click & drag to build  •  [%s] rotate  •  [%s] continue from last wall",
			keyName(kb.Rotate),
			keyName(kb.Continue)
		)
	end

	-- Only touch properties when the text actually changed
	if modeText ~= lastModeText then
		modeLabel.Text = modeText
		lastModeText = modeText
	end
	if hintText ~= lastHintText then
		hintLabel.Text = hintText
		lastHintText = hintText
	end
end

-- === TOWER SELECTION & OPTIONS ===
-- Click one of your placed towers (outside placement/delete modes) to select it
-- and get an options panel: rotate ±45°, delete, close.

local rotatePieceEvent: RemoteEvent? = nil
task.spawn(function()
	rotatePieceEvent = RemoteEvents:WaitForChild("RotateWallPiece", 10) :: RemoteEvent?
end)

local selectedTower: Model? = nil
local towerSelectionBox: SelectionBox? = nil
local towerOptionsGui: ScreenGui? = nil

local deselectTower -- forward declaration (used by button callbacks)

local function rotateSelectedTower(delta: number)
	if selectedTower and selectedTower.Parent and rotatePieceEvent then
		rotatePieceEvent:FireServer(selectedTower, delta)
	end
end

local function deleteSelectedTower()
	if selectedTower and selectedTower.Parent then
		removePieceEvent:FireServer(selectedTower)
	end
	deselectTower()
end

local function ensureTowerOptionsUI(): ScreenGui
	if towerOptionsGui then
		return towerOptionsGui
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "TowerOptionsUI"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 11
	gui.Enabled = false

	local frame = Instance.new("Frame")
	frame.Name = "Container"
	frame.AnchorPoint = Vector2.new(0.5, 1)
	frame.Position = UDim2.new(0.5, 0, 1, -150) -- same slot as the mode UI (never visible together)
	frame.Size = UDim2.new(0, 420, 0, 78)
	frame.BackgroundColor3 = Color3.fromRGB(76, 62, 62) -- Tundora
	frame.BackgroundTransparency = 0.15
	frame.BorderSizePixel = 0
	frame.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(218, 165, 32) -- AccentGold
	stroke.Thickness = 1.5
	stroke.Transparency = 0.3
	stroke.Parent = frame

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -16, 0, 22)
	title.Position = UDim2.new(0, 8, 0, 4)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextSize = 15
	title.TextColor3 = Color3.fromRGB(218, 165, 32)
	title.Text = "Tower Options"
	title.Parent = frame

	local buttonRow = Instance.new("Frame")
	buttonRow.Size = UDim2.new(1, -16, 0, 36)
	buttonRow.Position = UDim2.new(0, 8, 0, 30)
	buttonRow.BackgroundTransparency = 1
	buttonRow.Parent = frame

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 8)
	layout.Parent = buttonRow

	local function makeButton(text: string, color: Color3, callback: () -> ())
		local b = Instance.new("TextButton")
		b.Size = UDim2.new(0, 92, 0, 32)
		b.BackgroundColor3 = color
		b.AutoButtonColor = true
		b.Font = Enum.Font.GothamBold
		b.TextSize = 14
		b.TextColor3 = Color3.fromRGB(255, 255, 255)
		b.Text = text

		local bc = Instance.new("UICorner")
		bc.CornerRadius = UDim.new(0, 6)
		bc.Parent = b

		b.Activated:Connect(callback)
		b.Parent = buttonRow
	end

	local opium = Color3.fromRGB(138, 106, 106)
	makeButton("⟲ Rotate 45°", opium, function()
		rotateSelectedTower(-math.rad(45))
	end)
	makeButton("⟳ Rotate 45°", opium, function()
		rotateSelectedTower(math.rad(45))
	end)
	makeButton("Delete", Color3.fromRGB(140, 60, 60), deleteSelectedTower)
	makeButton("Close", Color3.fromRGB(90, 78, 78), function()
		deselectTower()
	end)

	gui.Parent = player:WaitForChild("PlayerGui")
	towerOptionsGui = gui
	return gui
end

function deselectTower()
	selectedTower = nil
	if towerSelectionBox then
		towerSelectionBox:Destroy()
		towerSelectionBox = nil
	end
	if towerOptionsGui then
		towerOptionsGui.Enabled = false
	end
end

local function selectTower(model: Model)
	deselectTower()
	selectedTower = model

	local box = Instance.new("SelectionBox")
	box.Adornee = model
	box.Color3 = Color3.fromRGB(218, 165, 32)
	box.LineThickness = 0.05
	box.Transparency = 0.2
	box.Parent = model
	towerSelectionBox = box

	ensureTowerOptionsUI().Enabled = true
end

-- True when the cursor is over the tower options panel (so clicks on its
-- buttons don't fall through and deselect the tower mid-press)
local function isMouseOverTowerUI(): boolean
	if not towerOptionsGui or not towerOptionsGui.Enabled then
		return false
	end
	local playerGui = player:FindFirstChild("PlayerGui") :: PlayerGui?
	if not playerGui then
		return false
	end
	for _, obj in ipairs(playerGui:GetGuiObjectsAtPosition(mouse.X, mouse.Y)) do
		if obj:IsDescendantOf(towerOptionsGui) then
			return true
		end
	end
	return false
end

-- === VISUALS (PREVIEW) ===

local function createGhost(point: PathPoint, color: Color3): Model?
	local modelName = CONFIG.PieceTypes[point.type]
	local template = Buildings:FindFirstChild(modelName)
	if not template then
		return nil
	end
	local ghost = template:Clone() :: Model
	do
		local BuildingScaleConfig = require(ReplicatedStorage.Shared.GameData.BuildingScaleConfig)
		BuildingScaleConfig.applyToModel(ghost)
	end
	for _, p in ipairs(ghost:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Transparency, p.CanCollide, p.Anchored = 0.5, false, true
			p.Color, p.Material = color, Enum.Material.Neon
		end
	end
	ghost.Parent = Workspace
	if ghost.PrimaryPart then
		local groundY = getGroundHeight(point.position)
		local cf, size = ghost:GetBoundingBox()
		local offset = ghost.PrimaryPart.Position.Y - (cf.Position.Y - size.Y / 2)
		ghost:SetPrimaryPartCFrame(
			CFrame.new(Vector3.new(point.position.X, groundY + offset, point.position.Z))
				* CFrame.Angles(0, point.rotation, 0)
		)
	end
	return ghost
end

local function createNodeMarker(position: Vector3, groundY: number, size: number, color: Color3)
	local m = Instance.new("Part")
	m.Shape = Enum.PartType.Ball
	m.Size = Vector3.new(size, size, size)
	m.Position = Vector3.new(position.X, groundY + 2, position.Z)
	m.Anchored, m.CanCollide, m.Transparency = true, false, 0.2
	m.Color, m.Material, m.Parent = color, Enum.Material.Neon, Workspace
	table.insert(snapIndicators, m)
end

local function updatePolygonPreview()
	local cursorPos, cursorSnapDir, canClose = getPolygonCursor()
	updateModeUI(canClose)

	-- Committed segments: only rebuilt when nodes change (cheap per-frame)
	if committedPreviewDirty then
		for _, g in ipairs(committedPreviewModels) do
			g:Destroy()
		end
		committedPreviewModels = {}
		if #polygonNodes >= 2 then
			local pts: { Vector3 } = {}
			for _, node in ipairs(polygonNodes) do
				table.insert(pts, node.position)
			end
			local committedPath = buildPolygonPath(pts, polygonNodes[1].incomingDir, false, nil)
			for _, point in ipairs(committedPath) do
				local g = createGhost(point, Color3.new(0, 1, 1))
				if g then
					table.insert(committedPreviewModels, g)
				end
			end
		end
		committedPreviewDirty = false
	end

	-- Node markers (first node glows yellow when the loop can be closed)
	for i, node in ipairs(polygonNodes) do
		local isCloseTarget = (i == 1) and canClose
		createNodeMarker(
			node.position,
			node.groundY,
			if isCloseTarget then 8 else 4,
			if isCloseTarget then Color3.new(1, 1, 0) else Color3.new(1, 0.6, 0)
		)
	end

	-- Hovering the first node: preview the closing leg
	if canClose and #polygonNodes >= 3 then
		local lastNode = polygonNodes[#polygonNodes]
		local prev = polygonNodes[#polygonNodes - 1].position
		local d = Vector3.new(lastNode.position.X - prev.X, 0, lastNode.position.Z - prev.Z)
		local dirIn = if d.Magnitude > 0.001 then d.Unit else nil
		local closingPath = buildPolygonPath({ lastNode.position, polygonNodes[1].position }, dirIn, false, nil)
		for _, point in ipairs(closingPath) do
			local g = createGhost(point, Color3.new(1, 1, 0.3))
			if g then
				table.insert(previewModels, g)
			end
		end
	end

	-- Active segment: last node -> cursor, re-rendered every frame
	if #polygonNodes > 0 and not canClose then
		local lastNode = polygonNodes[#polygonNodes]
		local dirIn: Vector3? = nil
		if #polygonNodes >= 2 then
			local prev = polygonNodes[#polygonNodes - 1].position
			local d = Vector3.new(lastNode.position.X - prev.X, 0, lastNode.position.Z - prev.Z)
			if d.Magnitude > 0.001 then
				dirIn = d.Unit
			end
		else
			dirIn = lastNode.incomingDir
		end

		local activePath = buildPolygonPath({ lastNode.position, cursorPos }, dirIn, false, cursorSnapDir)
		local valid = true
		for _, pt in ipairs(activePath) do
			if not isInPlayerZone(pt.position) then
				valid = false
				break
			end
		end
		local color = if valid then Color3.new(0.4, 1, 0.4) else Color3.new(1, 0.2, 0.2)
		for _, point in ipairs(activePath) do
			local g = createGhost(point, color)
			if g then
				table.insert(previewModels, g)
			end
		end
	end

	-- Cursor indicator
	if not canClose then
		local cursorColor = if cursorSnapDir then Color3.new(0, 1, 1) else Color3.new(0, 1, 0)
		createNodeMarker(cursorPos, getGroundHeight(cursorPos), 5, cursorColor)
	end
end

local function updatePreview()
	-- Drop tower selection if the model was destroyed (e.g. deleted by another system)
	if selectedTower and not selectedTower.Parent then
		deselectTower()
	end

	-- Clear old previews
	for _, g in ipairs(previewModels) do
		g:Destroy()
	end
	previewModels = {}
	for _, i in ipairs(snapIndicators) do
		i:Destroy()
	end
	snapIndicators = {}

	if not selectedPiece or not isPlacingWalls then
		if #committedPreviewModels > 0 then
			for _, g in ipairs(committedPreviewModels) do
				g:Destroy()
			end
			committedPreviewModels = {}
			committedPreviewDirty = true
		end
		return
	end

	-- Polygon plot mode has its own renderer
	if buildMode == "Polygon" and isLinearPiece(selectedPiece) then
		updatePolygonPreview()
		return
	end

	updateModeUI(false)

	local rawOrigin, rawDir = getMouseRay()
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { camera, player.Character }
	local hit = Workspace:Raycast(rawOrigin, rawDir * 500, params)
	local rawPos = hit and hit.Position or (rawOrigin + rawDir * 50)

	local snapPos, _, isInt = getSmartSnap(rawPos)

	if snapPos then
		-- Create larger, more visible snap indicator
		local color = isInt and Color3.new(0, 1, 1) or Color3.new(0, 1, 0) -- Cyan for intersection, green for endpoint

		-- Main indicator sphere - larger and brighter
		local s = Instance.new("Part")
		s.Shape, s.Size, s.Position = Enum.PartType.Ball, Vector3.new(6, 6, 6), snapPos
		s.Anchored, s.CanCollide, s.Transparency = true, false, 0.2
		s.Color, s.Material, s.Parent = color, Enum.Material.Neon, Workspace
		table.insert(snapIndicators, s)

		-- Add pulsing outer ring for extra visibility
		local ring = Instance.new("Part")
		ring.Shape, ring.Size, ring.Position = Enum.PartType.Ball, Vector3.new(10, 10, 10), snapPos
		ring.Anchored, ring.CanCollide, ring.Transparency = true, false, 0.7
		ring.Color, ring.Material, ring.Parent = color, Enum.Material.ForceField, Workspace
		table.insert(snapIndicators, ring)
	end

	local path, valid = getActivePath()
	for _, point in ipairs(path) do
		-- Green for valid placement (brighter cyan when snapped), red for invalid
		local isSnapped = snapPos ~= nil
		local ghostColor
		if valid then
			ghostColor = isSnapped and Color3.new(0, 1, 1) or Color3.new(0.4, 1, 0.4)
		else
			ghostColor = Color3.new(1, 0.2, 0.2)
		end

		local ghost = createGhost(point, ghostColor)
		if ghost then
			table.insert(previewModels, ghost)
		end
	end
end

-- === PLACEMENT & EVENTS ===

-- Server caps paths at 200 pieces; fire contiguous slices so large polygons still validate
local function firePathInChunks(path: { PathPoint })
	local CHUNK_SIZE = 150
	local batch: { PathPoint } = {}
	for _, point in ipairs(path) do
		table.insert(batch, point)
		if #batch >= CHUNK_SIZE then
			placePathEvent:FireServer(batch)
			batch = {}
		end
	end
	if #batch > 0 then
		placePathEvent:FireServer(batch)
	end
end

local function getPieceLength(pieceType: string): number
	if pieceType == "Straight" or pieceType == "Ladder" then
		return CONFIG.WallLengthLong
	elseif pieceType == "Short" then
		return CONFIG.WallLengthShort
	elseif pieceType == "Gatehouse" then
		return CONFIG.GatehouseSpacing
	end
	return 0
end

-- Registers endpoints for local snapping and updates the C-continue anchor
local function registerPlacedPath(path: { PathPoint })
	for _, point in ipairs(path) do
		local len = getPieceLength(point.type)
		if len > 0 then
			local p1, p2 = getWallEndpoints(point.position, point.rotation, len)
			registerWallEndpoints(p1, p2)
		end
	end

	local lastP = path[#path]
	local len = getPieceLength(lastP.type)
	if len > 0 then
		local _, endP = getWallEndpoints(lastP.position, lastP.rotation, len)
		lastWallEndpoint = endP
		local cf = CFrame.Angles(0, lastP.rotation, 0)
		lastWallDir = cf.RightVector
	end
end

local function notifyPlaced(count: number)
	local StarterGui = game:GetService("StarterGui")
	StarterGui:SetCore("ChatMakeSystemMessage", {
		Text = string.format("[Wall System] Placed %d wall pieces!", count),
		Color = Color3.fromRGB(100, 255, 100),
	})
end

local function placeCurrentPath()
	local path, _ = getActivePath()
	if #path == 0 then
		return
	end

	firePathInChunks(path)
	notifyPlaced(#path)
	registerPlacedPath(path)

	isDragging = false
	startPosition = nil
	startIncomingDir = nil
end

local function placePolygonPath(closed: boolean)
	if #polygonNodes < 2 then
		return
	end

	local pts: { Vector3 } = {}
	for _, node in ipairs(polygonNodes) do
		table.insert(pts, node.position)
	end

	local path: { PathPoint }
	if closed then
		path = buildPolygonPath(pts, nil, true, nil)
	else
		local endAnchorDir = polygonNodes[#polygonNodes].incomingDir
		path = buildPolygonPath(pts, polygonNodes[1].incomingDir, false, endAnchorDir)
	end

	if #path == 0 then
		return
	end

	firePathInChunks(path)
	notifyPlaced(#path)
	registerPlacedPath(path)
	resetPolygonState()
end

local function cancelBuild()
	selectedPiece = nil
	isDragging = false
	startPosition = nil
	startIncomingDir = nil
	isPlacingWalls = false
	manualRotationOffset = 0 -- Reset rotation offset
	resetPolygonState()
	setModeUIVisible(false)

	-- Clear all previews
	for _, g in ipairs(previewModels) do
		g:Destroy()
	end
	previewModels = {}
	for _, i in ipairs(snapIndicators) do
		i:Destroy()
	end
	snapIndicators = {}

	-- Notify player
	local StarterGui = game:GetService("StarterGui")
	StarterGui:SetCore("ChatMakeSystemMessage", {
		Text = "[Wall System] Wall placement canceled.",
		Color = Color3.fromRGB(255, 200, 100),
	})
end

-- === INPUT HANDLING ===

mouse.Button1Down:Connect(function()
	if not isPlacingWalls or not selectedPiece then
		-- Clicks on the tower options panel are handled by its buttons
		if isMouseOverTowerUI() then
			return
		end

		-- Only allow wall deletion when delete mode is active
		if isDeleteModeActive then
			local target = mouse.Target
			local model = target and target:FindFirstAncestorOfClass("Model")
			if model and model:FindFirstChild("PlacedPiece") then
				-- Check if it's owned by the player
				if model:GetAttribute("OwnerId") == player.UserId then
					removePieceEvent:FireServer(model)
					-- print("[WallBuilderController] Removing wall piece:", model.Name)
				end
			end
			return
		end

		-- Tower selection: click one of your own placed towers for options
		local target = mouse.Target
		local model = target and target:FindFirstAncestorOfClass("Model")
		if model and model:FindFirstChild("PlacedPiece") and model:GetAttribute("OwnerId") == player.UserId then
			local wallPieceType = tostring(model:GetAttribute("WallPieceType") or "")
			if string.find(wallPieceType, "Tower") then
				selectTower(model)
				return
			end
		end
		deselectTower() -- clicked elsewhere: clear any selection
		return
	end

	-- Polygon plot mode: click plots a node / closes the loop
	if buildMode == "Polygon" and isLinearPiece(selectedPiece) then
		local cursorPos, cursorSnapDir, canClose = getPolygonCursor()

		if canClose then
			placePolygonPath(true)
			return
		end

		if not isInPlayerZone(cursorPos) then
			local StarterGui = game:GetService("StarterGui")
			StarterGui:SetCore("ChatMakeSystemMessage", {
				Text = "[Wall System] Can't place a node outside your zone.",
				Color = Color3.fromRGB(255, 100, 100),
			})
			return
		end

		-- Ignore duplicate clicks on the same spot
		local lastNode = polygonNodes[#polygonNodes]
		if lastNode and (cursorPos - lastNode.position).Magnitude < 1 then
			return
		end

		table.insert(polygonNodes, {
			position = cursorPos,
			incomingDir = cursorSnapDir,
			groundY = getGroundHeight(cursorPos),
		})
		committedPreviewDirty = true
		return
	end

	if not startPosition then
		local rawOrigin, rawDir = getMouseRay()
		local params = RaycastParams.new()
		params.FilterDescendantsInstances = { camera, player.Character }
		local hit = Workspace:Raycast(rawOrigin, rawDir * 500, params)
		local rawPos = hit and hit.Position or (rawOrigin + rawDir * 50)

		local snapPos, snapDir, _ = getSmartSnap(rawPos)

		if snapPos then
			startPosition = snapPos
			startIncomingDir = snapDir
		else
			startPosition = snapToGrid(rawPos)
			startIncomingDir = nil
		end
	end
	isDragging = true
end)

mouse.Button1Up:Connect(function()
	-- Single pieces (Tower/Gatehouse) place normally regardless of build mode
	if isDragging and selectedPiece and (buildMode == "Drag" or not isLinearPiece(selectedPiece)) then
		placeCurrentPath()
	end
end)

-- Right-click: undo last polygon node, or cancel the build
mouse.Button2Down:Connect(function()
	if not isPlacingWalls then
		return
	end
	if buildMode == "Polygon" and #polygonNodes > 0 then
		table.remove(polygonNodes)
		committedPreviewDirty = true
	else
		cancelBuild()
	end
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if not isPlacingWalls then
		return
	end

	-- ESC always works, even if UI has focus
	if input.KeyCode == Enum.KeyCode.Escape then
		cancelBuild()
		return
	end

	-- Other keys only work if UI doesn't have focus
	if processed then
		return
	end

	if input.KeyCode == CONFIG.Keybinds.Rotate then
		-- Increment manual rotation offset (works even when snapped)
		manualRotationOffset = (manualRotationOffset + math.rad(45)) % math.rad(360)
		-- Also update base rotation for when not snapped
		currentRotation = (currentRotation + math.rad(45)) % math.rad(360)
	elseif input.KeyCode == CONFIG.Keybinds.Continue and lastWallEndpoint then
		startPosition = lastWallEndpoint
		startIncomingDir = lastWallDir
	elseif input.KeyCode == CONFIG.Keybinds.ToggleMode then
		-- Toggle between Drag and Polygon plot modes (linear wall pieces only)
		if isLinearPiece(selectedPiece) then
			buildMode = if buildMode == "Drag" then "Polygon" else "Drag"
			resetPolygonState()
			isDragging = false
			startPosition = nil
			startIncomingDir = nil
		end
	elseif input.KeyCode == CONFIG.Keybinds.ConfirmPath then
		-- Confirm an open polygon path
		if buildMode == "Polygon" and #polygonNodes >= 2 then
			placePolygonPath(false)
		end
	end
end)

RunService.RenderStepped:Connect(updatePreview)

-- === INTERFACE WITH GAME SYSTEM ===

gameEvent.OnClientEvent:Connect(function(action, data)
	if action == "GameStarted" then
		if data and data.zoneCenter then
			playerZoneCenter = data.zoneCenter
			playerZoneRadius = data.zoneRadius
		end
	elseif action == "StartPlacement" then
		-- Check if it's a wall building request
		if data and (data == "Stone_Wall" or string.find(tostring(data), "Wall")) then
			-- print("[WallBuilderController] Starting wall placement:", data)

			-- Reset any existing wall placement state
			isDragging = false
			startPosition = nil
			startIncomingDir = nil
			resetPolygonState()
			deselectTower()

			-- Enter wall placement mode
			isPlacingWalls = true
			manualRotationOffset = 0 -- Reset rotation offset for new placement

			-- Map building type to piece type
			if data == "Wall_Tower" then
				selectedPiece = "Tower"
			elseif data == "Wall_Gatehouse" then
				selectedPiece = "Gatehouse"
			elseif data == "Wall_Ladder" then
				selectedPiece = "Ladder"
			else
				-- Default for "Stone_Wall" and others
				selectedPiece = "Straight"
			end

			-- Show the mode indicator UI (it carries the contextual control hints)
			setModeUIVisible(true)
			updateModeUI(false)
		end
	elseif action == "PlacementEnded" then
		cancelBuild()
	end
end)

-- === LISTEN FOR DELETE MODE ===
local deleteModeEvent = ReplicatedStorage:FindFirstChild("DeleteModeChanged")
if not deleteModeEvent then
	deleteModeEvent = Instance.new("BindableEvent")
	deleteModeEvent.Name = "DeleteModeChanged"
	deleteModeEvent.Parent = ReplicatedStorage
end

deleteModeEvent.Event:Connect(function(isActive: boolean)
	isDeleteModeActive = isActive
	if isActive then
		deselectTower()
	end
	-- print("[WallBuilderController] Delete mode:", isActive)
end)

-- === SYNC ENDPOINTS FROM SERVER ===
task.spawn(function()
	getEndpointsEvent = RemoteEvents:WaitForChild("GetWallEndpoints", 10) :: RemoteFunction?
	if getEndpointsEvent then
		-- Sync existing wall endpoints from server
		local success, serverEndpoints = pcall(function()
			return getEndpointsEvent:InvokeServer()
		end)
		if success and serverEndpoints then
			wallEndpoints = serverEndpoints
			-- print(string.format("[WallBuilderController] Synced %d wall endpoints from server", #wallEndpoints))
		else
			warn("[WallBuilderController] Failed to sync endpoints from server")
		end
	else
		warn("[WallBuilderController] GetWallEndpoints remote not found - endpoints won't persist across sessions")
	end
end)

-- print("[WallBuilderController] Wall Builder Ready")

return {}
