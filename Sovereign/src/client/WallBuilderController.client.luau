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

-- === CONFIGURATION ===
local CONFIG = {
	GridSize = 4,
	MinCameraDistance = 20,
	MaxCameraDistance = 300,
	SnapDistance = 16,

	-- Dimensions (based on actual model sizes from debug)
	WallLengthLong = 16, -- Stone_Wall_Straight is 16.0 studs wide
	WallLengthShort = 10, -- Stone_Wall_Short_Straight is 10.0 studs wide
	TowerRadius = 12, -- Stone_Wall_Small_Tower is 24.0 studs (radius = 12)
	GatehouseSpacing = 58, -- Stone_Wall_Gatehouse is 58.5 studs wide

	PieceTypes = {
		Tower = "Stone_Wall_Small_Tower",
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
local previewModels: { Model } = {}
local snapIndicators: { Part } = {}
local wallEndpoints: { { position: Vector3, incomingDir: Vector3 } } = {}
local lastWallEndpoint: Vector3? = nil
local lastWallDir: Vector3? = nil
local isPlacingWalls = false

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
		if model then
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
		local remaining = leg.len
		local pos = 0
		while remaining >= CONFIG.WallLengthLong do
			table.insert(path, {
				position = leg.p1 + (leg.dir * (pos + CONFIG.WallLengthLong / 2)),
				type = "Straight",
				rotation = leg.angle,
			})
			pos = pos + CONFIG.WallLengthLong
			remaining = remaining - CONFIG.WallLengthLong
		end
		while remaining >= CONFIG.WallLengthShort do
			table.insert(path, {
				position = leg.p1 + (leg.dir * (pos + CONFIG.WallLengthShort / 2)),
				type = "Short",
				rotation = leg.angle,
			})
			pos = pos + CONFIG.WallLengthShort
			remaining = remaining - CONFIG.WallLengthShort
		end
		if remaining > 0 then
			table.insert(path, {
				position = leg.p1 + (leg.dir * (pos + CONFIG.WallLengthShort / 2)),
				type = "Short",
				rotation = leg.angle,
			})
		end
	end

	if isEndIntersection then
		local incDir = (endPos - currentStart).Unit
		local endRot = math.atan2(incDir.X, incDir.Z) + math.rad(90)
		table.insert(path, { position = endPos, type = "Tower", rotation = endRot })
	end

	return path, valid
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
		if snapDir then
			rot = math.atan2(snapDir.X, snapDir.Z) + math.rad(90)
		end

		return { { position = currentPos, type = selectedPiece, rotation = rot } }, true
	end

	-- Dragging
	if selectedPiece == "Straight" or selectedPiece == "Short" then
		return calculateSmartWallPath(startPosition, currentPos, startIncomingDir, isIntersection)
	else
		-- Simple linear placement for other types
		return { { position = currentPos, type = selectedPiece, rotation = currentRotation } }, true
	end
end

-- === VISUALS (PREVIEW) ===

local function updatePreview()
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
		return
	end

	local rawOrigin, rawDir = getMouseRay()
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { camera, player.Character }
	local hit = Workspace:Raycast(rawOrigin, rawDir * 500, params)
	local rawPos = hit and hit.Position or (rawOrigin + rawDir * 50)

	local snapPos, _, isInt = getSmartSnap(rawPos)

	if snapPos then
		local color = isInt and Color3.new(0, 1, 1) or Color3.new(0, 1, 0)
		local s = Instance.new("Part")
		s.Shape, s.Size, s.Position = Enum.PartType.Ball, Vector3.new(2, 2, 2), snapPos
		s.Anchored, s.CanCollide, s.Transparency = true, false, 0.3
		s.Color, s.Material, s.Parent = color, Enum.Material.Neon, Workspace
		table.insert(snapIndicators, s)
	end

	local path, valid = getActivePath()
	for _, point in ipairs(path) do
		local modelName = CONFIG.PieceTypes[point.type]
		local template = Buildings:FindFirstChild(modelName)
		if template then
			local ghost = template:Clone() :: Model
			for _, p in ipairs(ghost:GetDescendants()) do
				if p:IsA("BasePart") then
					p.Transparency, p.CanCollide, p.Anchored = 0.5, false, true
					p.Color, p.Material = valid and Color3.new(0.4, 1, 0.4) or Color3.new(1, 0.2, 0.2),
						Enum.Material.Neon
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
			table.insert(previewModels, ghost)
		end
	end
end

-- === PLACEMENT & EVENTS ===

local function placeCurrentPath()
	local path, _ = getActivePath()
	if #path == 0 then
		return
	end

	-- Send to server
	placePathEvent:FireServer(path)

	-- Notify player
	local StarterGui = game:GetService("StarterGui")
	StarterGui:SetCore("ChatMakeSystemMessage", {
		Text = string.format("[Wall System] Placed %d wall pieces!", #path),
		Color = Color3.fromRGB(100, 255, 100),
	})

	-- Register endpoints for snapping
	for _, point in ipairs(path) do
		local len = 0
		if point.type == "Straight" then
			len = CONFIG.WallLengthLong
		elseif point.type == "Short" then
			len = CONFIG.WallLengthShort
		elseif point.type == "Gatehouse" then
			len = CONFIG.GatehouseSpacing
		end

		if len > 0 then
			local p1, p2 = getWallEndpoints(point.position, point.rotation, len)
			registerWallEndpoints(p1, p2)
		end
	end

	-- Update continue functionality
	if #path > 0 then
		local lastP = path[#path]
		local len = 0
		if lastP.type == "Straight" then
			len = CONFIG.WallLengthLong
		elseif lastP.type == "Short" then
			len = CONFIG.WallLengthShort
		elseif lastP.type == "Gatehouse" then
			len = CONFIG.GatehouseSpacing
		end

		if len > 0 then
			local _, endP = getWallEndpoints(lastP.position, lastP.rotation, len)
			lastWallEndpoint = endP
			local cf = CFrame.Angles(0, lastP.rotation, 0)
			lastWallDir = cf.RightVector
		end
	end

	isDragging = false
	startPosition = nil
	startIncomingDir = nil
end

local function cancelBuild()
	selectedPiece = nil
	isDragging = false
	startPosition = nil
	startIncomingDir = nil
	isPlacingWalls = false

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
		-- Try to remove a wall piece
		local target = mouse.Target
		local model = target and target:FindFirstAncestorOfClass("Model")
		if model and model:FindFirstChild("PlacedPiece") then
			removePieceEvent:FireServer(model)
		end
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
	if isDragging and selectedPiece then
		placeCurrentPath()
	end
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or not isPlacingWalls then
		return
	end
	if input.KeyCode == Enum.KeyCode.Escape then
		cancelBuild()
	elseif input.KeyCode == Enum.KeyCode.R then
		currentRotation = (currentRotation + math.rad(45)) % math.rad(360)
	elseif input.KeyCode == Enum.KeyCode.C and lastWallEndpoint then
		startPosition = lastWallEndpoint
		startIncomingDir = lastWallDir
	end
end)

RunService.RenderStepped:Connect(updatePreview)

-- === INTERFACE WITH GAME SYSTEM ===

gameEvent.OnClientEvent:Connect(function(action, data)
	if action == "StartPlacement" then
		-- Check if it's a wall building request
		if data and (data == "Stone_Wall" or string.find(tostring(data), "Wall")) then
			print("[WallBuilderController] Starting wall placement:", data)
			isPlacingWalls = true
			selectedPiece = "Straight" -- Default to straight walls

			-- Notify player
			local StarterGui = game:GetService("StarterGui")
			StarterGui:SetCore("ChatMakeSystemMessage", {
				Text = "[Wall System] Click and drag to build walls! Press R to rotate, C to continue from last wall, ESC to cancel.",
				Color = Color3.fromRGB(100, 200, 255),
			})
		end
	elseif action == "PlacementEnded" then
		cancelBuild()
	end
end)

print("[WallBuilderController] Wall Builder Ready")

return {}
