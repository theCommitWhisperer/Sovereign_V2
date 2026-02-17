--!strict
-- MapEditorController: Client-side controller for the map editor
-- Handles editor camera (top-down pan/zoom), raycasting, brush ghost, and drag painting

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DebugManager = require(ReplicatedStorage.Shared.DebugManager)
local MapEditorControllerDebug = DebugManager.createChannel("MapEditorController", true)

local localPlayer = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- Editor state
local isEditorActive = false
local cameraPosition = Vector3.new(0, 300, 0)
local cameraHeight = 300
local cameraPanSpeed = 2
local cameraZoomSpeed = 30
local minZoom = 80
local maxZoom = 800

-- Input tracking
local keysDown: { [Enum.KeyCode]: boolean } = {}
local isPanning = false
local lastMousePosition: Vector2? = nil

-- Brush state (synced from UI via player attributes)
local brushGhost: BasePart? = nil
local activeTool = "Select"
local brushRadius = 20
local brushHeight = 10
local brushShape = "Block"
local brushMaterial = "Grass"

-- Painting state
local isPainting = false
local pendingStrokes: { any } = {}
local lastPaintPosition: Vector3? = nil
local PAINT_INTERVAL = 0.1 -- Batch send interval
local PAINT_MIN_DISTANCE = 5 -- Minimum distance between paint strokes
local lastFlushTime = 0

-- Material colors for brush ghost preview
local MATERIAL_COLORS: { [string]: Color3 } = {
	Grass = Color3.fromRGB(100, 180, 70),
	Sand = Color3.fromRGB(220, 200, 140),
	Rock = Color3.fromRGB(140, 130, 120),
	Water = Color3.fromRGB(50, 120, 200),
	Snow = Color3.fromRGB(240, 245, 255),
	LeafyGrass = Color3.fromRGB(40, 120, 30),
	Slate = Color3.fromRGB(100, 100, 110),
	Sandstone = Color3.fromRGB(180, 160, 100),
	Ground = Color3.fromRGB(130, 110, 80),
}

-- Store previous camera state to restore on exit
local savedCameraType: Enum.CameraType? = nil
local savedCameraSubject: Instance? = nil
local savedCameraCFrame: CFrame? = nil

-- Remote event reference
local MapEditorEvent: RemoteEvent? = nil

local function getMapEditorEvent(): RemoteEvent?
	if MapEditorEvent then return MapEditorEvent end
	local remoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")
	if remoteEvents then
		MapEditorEvent = remoteEvents:FindFirstChild("MapEditorEvent") :: RemoteEvent?
	end
	return MapEditorEvent
end

-- Read brush settings from player attributes (set by UI)
local function syncBrushSettings()
	activeTool = localPlayer:GetAttribute("EditorActiveTool") or "Select"
	brushRadius = localPlayer:GetAttribute("EditorBrushRadius") or 20
	brushHeight = localPlayer:GetAttribute("EditorBrushHeight") or 10
	brushShape = localPlayer:GetAttribute("EditorBrushShape") or "Block"
	brushMaterial = localPlayer:GetAttribute("EditorBrushMaterial") or "Grass"
end

-- Create or update brush ghost part
local function updateBrushGhost(position: Vector3)
	local isBrushTool = activeTool == "TerrainBrush" or activeTool == "Eraser"
	if not isBrushTool then
		if brushGhost then
			brushGhost.Parent = nil
		end
		return
	end

	if not brushGhost then
		brushGhost = Instance.new("Part")
		brushGhost.Name = "BrushGhost"
		brushGhost.Anchored = true
		brushGhost.CanCollide = false
		brushGhost.Transparency = 0.6
		brushGhost.Material = Enum.Material.Neon
		brushGhost.CastShadow = false
	end

	-- Update shape
	if brushShape == "Ball" then
		brushGhost.Shape = Enum.PartType.Ball
		brushGhost.Size = Vector3.new(brushRadius * 2, brushRadius * 2, brushRadius * 2)
	else
		brushGhost.Shape = Enum.PartType.Block
		brushGhost.Size = Vector3.new(brushRadius * 2, brushHeight, brushRadius * 2)
	end

	-- Update color based on tool
	if activeTool == "Eraser" then
		brushGhost.Color = Color3.fromRGB(255, 80, 80)
	else
		brushGhost.Color = MATERIAL_COLORS[brushMaterial] or Color3.fromRGB(200, 200, 200)
	end

	-- Position at terrain surface
	brushGhost.Position = Vector3.new(position.X, position.Y + brushHeight / 2, position.Z)
	brushGhost.Parent = workspace
end

-- Raycast from mouse to terrain
local function raycastToTerrain(): Vector3?
	local mouseLocation = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouseLocation.X, mouseLocation.Y)

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Include
	raycastParams.FilterDescendantsInstances = { workspace:WaitForChild("Terrain") }

	local result = workspace:Raycast(ray.Origin, ray.Direction * 2000, raycastParams)
	if result then
		return result.Position
	end

	-- Fallback: intersect with Y=0 plane
	if ray.Direction.Y ~= 0 then
		local t = -ray.Origin.Y / ray.Direction.Y
		if t > 0 then
			return ray.Origin + ray.Direction * t
		end
	end

	return nil
end

-- Add a brush stroke to pending batch
local function addStroke(position: Vector3)
	local stroke = {
		Position = { X = position.X, Z = position.Z },
		Radius = brushRadius,
		Material = activeTool == "Eraser" and "Air" or brushMaterial,
		Shape = brushShape,
		SizeY = brushHeight,
	}
	table.insert(pendingStrokes, stroke)
end

-- Flush pending strokes to server
local function flushStrokes()
	if #pendingStrokes == 0 then return end

	local event = getMapEditorEvent()
	if event then
		event:FireServer("PaintTerrain", pendingStrokes)
		MapEditorControllerDebug:info("Flushed " .. #pendingStrokes .. " strokes to server")
	end

	pendingStrokes = {}
end

local function activateEditor()
	if isEditorActive then return end
	isEditorActive = true
	MapEditorControllerDebug:info("Editor camera activated")

	savedCameraType = camera.CameraType
	savedCameraSubject = camera.CameraSubject
	savedCameraCFrame = camera.CFrame

	camera.CameraType = Enum.CameraType.Scriptable

	cameraPosition = Vector3.new(0, cameraHeight, 0)
	camera.CFrame = CFrame.new(cameraPosition, cameraPosition + Vector3.new(0, -1, -0.01))

	-- Set default brush attributes
	localPlayer:SetAttribute("EditorActiveTool", "Select")
	localPlayer:SetAttribute("EditorBrushRadius", 20)
	localPlayer:SetAttribute("EditorBrushHeight", 10)
	localPlayer:SetAttribute("EditorBrushShape", "Block")
	localPlayer:SetAttribute("EditorBrushMaterial", "Grass")
end

local function deactivateEditor()
	if not isEditorActive then return end
	isEditorActive = false
	MapEditorControllerDebug:info("Editor camera deactivated")

	-- Flush any remaining strokes
	flushStrokes()

	if savedCameraType then
		camera.CameraType = savedCameraType
	end
	if savedCameraSubject then
		camera.CameraSubject = savedCameraSubject
	end
	if savedCameraCFrame then
		camera.CFrame = savedCameraCFrame
	end

	-- Clean up brush ghost
	if brushGhost then
		brushGhost:Destroy()
		brushGhost = nil
	end

	isPainting = false
	lastPaintPosition = nil
end

-- Watch for MapEditorActive attribute
localPlayer:GetAttributeChangedSignal("MapEditorActive"):Connect(function()
	local active = localPlayer:GetAttribute("MapEditorActive")
	if active then
		activateEditor()
	else
		deactivateEditor()
	end
end)

-- Check on startup in case attribute was already set
if localPlayer:GetAttribute("MapEditorActive") then
	activateEditor()
end

-- Input handling
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if not isEditorActive or gameProcessed then return end

	if input.UserInputType == Enum.UserInputType.Keyboard then
		keysDown[input.KeyCode] = true
	end

	-- Middle mouse button for panning
	if input.UserInputType == Enum.UserInputType.MouseButton3 then
		isPanning = true
		lastMousePosition = UserInputService:GetMouseLocation()
	end

	-- Left mouse button for painting/interaction
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		syncBrushSettings()
		local isBrushTool = activeTool == "TerrainBrush" or activeTool == "Eraser"
		if isBrushTool then
			isPainting = true
			local hitPos = raycastToTerrain()
			if hitPos then
				addStroke(hitPos)
				lastPaintPosition = hitPos
			end
		end
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if not isEditorActive then return end

	if input.UserInputType == Enum.UserInputType.Keyboard then
		keysDown[input.KeyCode] = nil
	end

	if input.UserInputType == Enum.UserInputType.MouseButton3 then
		isPanning = false
		lastMousePosition = nil
	end

	-- Stop painting and flush remaining strokes
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if isPainting then
			isPainting = false
			lastPaintPosition = nil
			flushStrokes()
		end
	end
end)

-- Scroll to zoom
UserInputService.InputChanged:Connect(function(input)
	if not isEditorActive then return end

	if input.UserInputType == Enum.UserInputType.MouseWheel then
		cameraHeight = math.clamp(cameraHeight - input.Position.Z * cameraZoomSpeed, minZoom, maxZoom)
	end

	-- Middle mouse drag for panning
	if isPanning and input.UserInputType == Enum.UserInputType.MouseMovement then
		local currentPos = UserInputService:GetMouseLocation()
		if lastMousePosition then
			local delta = currentPos - lastMousePosition
			local panScale = cameraHeight / 300
			cameraPosition = cameraPosition + Vector3.new(-delta.X * panScale, 0, -delta.Y * panScale)
		end
		lastMousePosition = currentPos
	end
end)

-- Main update loop
RunService.RenderStepped:Connect(function(dt)
	if not isEditorActive then return end

	-- Sync brush settings from UI attributes
	syncBrushSettings()

	-- WASD camera panning
	local moveDir = Vector3.zero
	if keysDown[Enum.KeyCode.W] or keysDown[Enum.KeyCode.Up] then
		moveDir = moveDir + Vector3.new(0, 0, -1)
	end
	if keysDown[Enum.KeyCode.S] or keysDown[Enum.KeyCode.Down] then
		moveDir = moveDir + Vector3.new(0, 0, 1)
	end
	if keysDown[Enum.KeyCode.A] or keysDown[Enum.KeyCode.Left] then
		moveDir = moveDir + Vector3.new(-1, 0, 0)
	end
	if keysDown[Enum.KeyCode.D] or keysDown[Enum.KeyCode.Right] then
		moveDir = moveDir + Vector3.new(1, 0, 0)
	end

	if moveDir.Magnitude > 0 then
		local panScale = cameraHeight / 300
		cameraPosition = cameraPosition + moveDir.Unit * cameraPanSpeed * panScale * dt * 60
	end

	-- Update camera position (top-down view)
	local targetPos = Vector3.new(cameraPosition.X, cameraHeight, cameraPosition.Z)
	camera.CFrame = CFrame.new(targetPos, targetPos + Vector3.new(0, -1, -0.01))

	-- Update brush ghost position
	local hitPos = raycastToTerrain()
	if hitPos then
		updateBrushGhost(hitPos)

		-- Continuous painting while dragging
		if isPainting then
			if lastPaintPosition then
				local dist = (hitPos - lastPaintPosition).Magnitude
				if dist >= PAINT_MIN_DISTANCE then
					addStroke(hitPos)
					lastPaintPosition = hitPos
				end
			else
				addStroke(hitPos)
				lastPaintPosition = hitPos
			end
		end
	end

	-- Batch flush pending strokes at interval
	local now = tick()
	if now - lastFlushTime >= PAINT_INTERVAL and #pendingStrokes > 0 then
		flushStrokes()
		lastFlushTime = now
	end
end)

MapEditorControllerDebug:info("MapEditorController loaded")
