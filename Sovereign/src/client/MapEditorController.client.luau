--!strict
-- MapEditorController: Client-side controller for the map editor
-- Handles editor camera (orbit/pan/zoom), raycasting, brush ghost, and drag painting/sculpting

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DebugManager = require(ReplicatedStorage.Shared.DebugManager)
local MapEditorControllerDebug = DebugManager.createChannel("MapEditorController", false)

local localPlayer = Players.LocalPlayer
local camera = workspace.CurrentCamera
local playerGui = localPlayer:WaitForChild("PlayerGui")

-- Returns true if the mouse cursor is currently over any GUI element.
-- gameProcessed is unreliable for custom React ScreenGuis, so we check manually.
local function isMouseOverGui(): boolean
	local mousePos = UserInputService:GetMouseLocation()
	local objects = playerGui:GetGuiObjectsAtPosition(mousePos.X, mousePos.Y)
	return #objects > 0
end

-- Editor state
local isEditorActive = false

-- Orbit camera state
local cameraFocus = Vector3.new(0, 0, 0) -- Point the camera orbits around
local cameraDistance = 300 -- Distance from focus point
local cameraYaw = 0 -- Horizontal rotation in radians
local cameraPitch = -math.rad(60) -- Vertical angle (-90 = top-down, 0 = horizon). Start angled down.
local cameraPanSpeed = 2
local cameraZoomSpeed = 30
local cameraRotateSpeed = 0.005
local minDistance = 30
local maxDistance = 1200
local minPitch = -math.rad(89) -- Nearly top-down
local maxPitch = -math.rad(10) -- Nearly horizontal

-- Input tracking
local keysDown: { [Enum.KeyCode]: boolean } = {}
local isRotating = false -- Right mouse drag to rotate
local isPanning = false -- Middle mouse drag to pan
local lastMousePosition: Vector2? = nil

-- Brush state (synced from UI via player attributes)
local brushGhost: BasePart? = nil
local activeTool = "Select"
local brushRadius = 20
local brushMode = "Raise" -- "Raise" | "Lower" | "Flatten" | "Paint"
local brushStrength = 0.5
local brushHardness = 0.5
local brushShape = "Circle" -- "Circle" | "Square"
local brushMaterial = "Grass"

-- Painting state
local isPainting = false
local pendingStrokes: { any } = {}
local pendingStrokeType = "Sculpt" -- "Sculpt" or "Paint"
local lastPaintPosition: Vector3? = nil
local PAINT_INTERVAL = 0.05 -- Batch send interval
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

-- Mode colors for brush ghost
local MODE_COLORS: { [string]: Color3 } = {
	Raise = Color3.fromRGB(80, 200, 80),
	Lower = Color3.fromRGB(200, 80, 80),
	Flatten = Color3.fromRGB(80, 130, 220),
}

-- Resource patch ghost
local resourceGhost: BasePart? = nil
-- Positions of all resource patches placed this session, used to prevent stacking.
local placedResourcePositions: { Vector2 } = {}

-- Select tool: currently selected resource patch
local selectedPatchId: string? = nil
local selectedPatchOriginalColor: Color3? = nil
local selectedPatchPart: BasePart? = nil

-- Returns true if hitPos is far enough from all existing patches to place a new one.
local function canPlaceResourcePatch(hitPos: Vector3, radius: number): boolean
	local p = Vector2.new(hitPos.X, hitPos.Z)
	local minDist = radius * 1.4
	for _, existing in ipairs(placedResourcePositions) do
		if (p - existing).Magnitude < minDist then
			return false
		end
	end
	return true
end

local function recordResourcePatch(hitPos: Vector3)
	table.insert(placedResourcePositions, Vector2.new(hitPos.X, hitPos.Z))
end

-- Clear the currently selected resource patch highlight
local function clearPatchSelection()
	if selectedPatchPart and selectedPatchOriginalColor then
		selectedPatchPart.Color = selectedPatchOriginalColor
	end
	selectedPatchId = nil
	selectedPatchOriginalColor = nil
	selectedPatchPart = nil
end

-- Find the nearest resource patch disc within maxDist studs of a world position
local function findNearestResourcePatch(worldPos: Vector3, maxDist: number): (string?, BasePart?)
	local resourceFolder = workspace:FindFirstChild("MapEditorResources")
	if not resourceFolder then return nil, nil end

	local bestId: string? = nil
	local bestPart: BasePart? = nil
	local bestDist = maxDist

	for _, child in ipairs(resourceFolder:GetChildren()) do
		-- Parts are named "Resource_<id>"
		local id = string.match(child.Name, "^Resource_(.+)$")
		if id and child:IsA("BasePart") then
			local d = (child.Position - worldPos).Magnitude
			if d < bestDist then
				bestDist = d
				bestId = id
				bestPart = child :: BasePart
			end
		end
	end

	return bestId, bestPart
end

local RESOURCE_COLORS: { [string]: Color3 } = {
	Wood     = Color3.fromRGB(60, 140, 40),
	Stone    = Color3.fromRGB(160, 155, 150),
	Food     = Color3.fromRGB(200, 180, 50),
	Iron_Ore = Color3.fromRGB(110, 80, 70),
}

-- Keep spawn ghost
local keepSpawnGhost: BasePart? = nil
local KEEP_SPAWN_COLORS: { [number]: Color3 } = {
	[1] = Color3.fromRGB(80, 120, 200),
	[2] = Color3.fromRGB(200, 80, 80),
	[3] = Color3.fromRGB(80, 180, 80),
	[4] = Color3.fromRGB(200, 160, 40),
}

-- Zone paint ghost
local zonePaintGhost: BasePart? = nil
local ZONE_PAINT_COLORS: { [number]: Color3 } = {
	[0] = Color3.fromRGB(140, 120, 80),  -- Neutral
	[1] = Color3.fromRGB(80, 120, 200),  -- Player 1
	[2] = Color3.fromRGB(200, 80, 80),   -- Player 2
	[3] = Color3.fromRGB(80, 180, 80),   -- Player 3
	[4] = Color3.fromRGB(200, 160, 40),  -- Player 4
	[5] = Color3.fromRGB(60, 55, 65),    -- Impassable (dark slate)
	[6] = Color3.fromRGB(190, 110, 40),  -- No Build (amber)
}

-- Zone overlay: server paints zone colors directly into terrain voxels when visible,
-- and regenerates real terrain when hidden. Client just fires Show/Hide events.
local zoneOverlayStrokes: { any } = {} -- local mirror for immediate ghost feedback

-- Returns the zone at an XZ point by replaying zone strokes (last writer wins).
local function getZoneAt(x: number, z: number): number
	local zone = -1
	for _, stroke in ipairs(zoneOverlayStrokes) do
		local dx = x - stroke.Position.X
		local dz = z - stroke.Position.Z
		local r = stroke.Radius or 40
		local inside = if stroke.Shape == "Square"
			then math.abs(dx) <= r and math.abs(dz) <= r
			else dx * dx + dz * dz <= r * r
		if inside then
			zone = stroke.Zone or 0
		end
	end
	return zone
end

-- Zone budget tracking (updated via ZoneStats server events)
-- Zones 0-4: territory (Neutral + 4 players).  Zones 5-6: map features (Impassable, No Build).
local zoneAreas: { [number]: number } = { [0]=0, [1]=0, [2]=0, [3]=0, [4]=0, [5]=0, [6]=0 }
-- Optimistic pending area: accumulates estimated % from strokes not yet confirmed by server.
-- Reset to zero when ZoneStats arrives so the server figure takes over.
local zonePendingArea: { [number]: number } = { [0]=0, [1]=0, [2]=0, [3]=0, [4]=0, [5]=0, [6]=0 }

-- Push server-confirmed zone areas to the UI attribute.
-- zonePendingArea is only used for the blocking check, not display,
-- because client estimates can't correctly account for overpainting.
-- Format: "z0,z1,z2,z3,z4,z5,z6" (tenths of a percent as integers)
local function pushZoneAreasToUI()
	local parts = {}
	for zone = 0, 6 do
		parts[zone + 1] = tostring(math.floor((zoneAreas[zone] or 0) * 10 + 0.5))
	end
	localPlayer:SetAttribute("EditorZoneAreas", table.concat(parts, ","))
end

-- ── Budget helpers ────────────────────────────────────────────────────────────
-- Parse "k1:v1,k2:v2" encoded attribute into table with numeric or string values.
local function parseBudgetTargets(encoded: string?): { [string]: number }
	local result: { [string]: number } = {}
	if not encoded or encoded == "" then return result end
	for pair in encoded:gmatch("[^,]+") do
		local k, v = pair:match("^(.+):(%d+%.?%d*)$")
		if k and v then result[k] = tonumber(v) or 0 end
	end
	return result
end

local function parseBudgetLocked(encoded: string?): { [string]: boolean }
	local result: { [string]: boolean } = {}
	if not encoded or encoded == "" then return result end
	for pair in encoded:gmatch("[^,]+") do
		local k, v = pair:match("^(.+):([01])$")
		if k and v then result[k] = v == "1" end
	end
	return result
end

-- Returns true if the given row (by key) is over its budget cap.
-- attrPrefix is "EditorZone" or "EditorResource".
-- rowKey is zone number (as string) for zone, or "zone_type" for resources.
local function isOverBudget(attrPrefix: string, rowKey: string, usedPct: number): boolean
	local mode: string = localPlayer:GetAttribute(attrPrefix .. "BudgetMode") or "Freeform"
	if mode == "Freeform" then return false end

	-- Equal mode: enforce cross-zone balance for player zones (P1-P4).
	-- A zone is over budget when it would exceed the current smallest zone
	-- by more than EQUAL_ZONE_TOLERANCE. Neutral zone (0) is uncapped.
	if mode == "Equal" and attrPrefix == "EditorZone" then
		local zoneNum = tonumber(rowKey)
		if zoneNum and zoneNum >= 1 and zoneNum <= 4 then
			local minOtherArea = math.huge
			for z = 1, 4 do
				if z ~= zoneNum then
					-- Include pending area so feedback is immediate
					local area = (zoneAreas[z] or 0) + (zonePendingArea[z] or 0)
					if area < minOtherArea then
						minOtherArea = area
					end
				end
			end
			if minOtherArea == math.huge then minOtherArea = 0 end
			local equalTolerance = (localPlayer:GetAttribute("EditorZoneEqualTolerance") :: number?) or 5
			return usedPct >= minOtherArea + equalTolerance
		end
		return false -- Neutral zone is never blocked in Equal mode
	end

	-- Custom mode: use per-zone locks and targets (original behaviour)
	local locked = parseBudgetLocked(localPlayer:GetAttribute(attrPrefix .. "BudgetLocked"))
	if not locked[rowKey] then return false end
	local targets = parseBudgetTargets(localPlayer:GetAttribute(attrPrefix .. "BudgetTargets"))
	local target = targets[rowKey] or 25
	return usedPct >= target
end

-- Read the server-confirmed area % for a given resource row key from EditorResourceAreas.
-- Format: "1_Wood=150;0_Stone=80;..." where values are tenths of a percent.
local function getResourceAreaPct(rowKey: string): number
	local encoded: string? = localPlayer:GetAttribute("EditorResourceAreas")
	if not encoded or encoded == "" then return 0 end
	for entry in encoded:gmatch("[^;]+") do
		local k, v = entry:match("^(.+)=(%d+)$")
		if k == rowKey and v then
			return (tonumber(v) or 0) / 10
		end
	end
	return 0
end

-- ── Polygon zone painter state ────────────────────────────────────────────────
-- Polygon mode is a sub-mode of ZonePaint (toggled via EditorZoneMode attribute).
-- All polygon geometry is local-only until committed.
local POLY_NODE_HIT   = 48  -- stud radius to grab a node for dragging
local POLY_CLOSE_SNAP = 64  -- stud radius to auto-close when clicking near first node
local POLY_EDGE_HIT   = 32  -- max stud dist from cursor to an edge to count as edge click
local POLY_PREVIEW_Y  = 302 -- floating Y for polygon parts (just above zone grid at 300)
local POLY_FILL_CELL  = 32  -- stud grid cell size for polygon fill preview
local ZONE_PLANE_Y   = 300  -- Y plane used for zone/polygon raycasting in overlay mode

local polyNodes: { { x: number, y: number, z: number } } = {}
local polyIsClosed = false
local polyDraggingNodeIdx: number? = nil
-- Debounce: only rebuild fill when the dragged node moves significantly
local polyLastDragX = 0
local polyLastDragZ = 0

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

-- Calculate camera CFrame from orbit parameters and apply it.
-- Also updates camera.Focus to the ground-level focus point so Roblox's
-- streaming system knows which terrain chunks to keep loaded. Without this,
-- the overhead map-editor camera has no CameraSubject and streaming unloads
-- terrain as you zoom in/out.
local function calculateCameraCFrame(): CFrame
	-- Spherical coordinates: yaw rotates around Y, pitch tilts up/down
	local offsetX = math.cos(cameraPitch) * math.sin(cameraYaw) * cameraDistance
	local offsetY = -math.sin(cameraPitch) * cameraDistance
	local offsetZ = math.cos(cameraPitch) * math.cos(cameraYaw) * cameraDistance

	local cameraPos = cameraFocus + Vector3.new(offsetX, offsetY, offsetZ)
	local cf = CFrame.lookAt(cameraPos, cameraFocus)

	-- Keep Focus at ground level so streaming loads what the camera is looking at
	camera.Focus = CFrame.new(cameraFocus)

	return cf
end

-- Periodically request terrain streaming around the current focus point.
-- workspace:RequestStreamAroundAsync is the proper API for forcing Roblox's
-- streaming engine to load terrain/parts near a position, regardless of where
-- the camera body is physically located.
local lastStreamRequest = 0
local lastStreamedPos = Vector3.new(math.huge, 0, math.huge)
local STREAM_REQUEST_INTERVAL = 1.0  -- seconds between requests
local STREAM_MOVE_THRESHOLD   = 50   -- studs moved before requesting again
local function maybeRequestStreaming()
	if not workspace.StreamingEnabled then return end
	local now = tick()
	if now - lastStreamRequest < STREAM_REQUEST_INTERVAL then return end
	local moved = (Vector3.new(cameraFocus.X, 0, cameraFocus.Z) - lastStreamedPos).Magnitude
	if moved < STREAM_MOVE_THRESHOLD then return end
	lastStreamRequest = now
	lastStreamedPos = Vector3.new(cameraFocus.X, 0, cameraFocus.Z)
	task.spawn(function()
		pcall(function()
			workspace:RequestStreamAroundAsync(cameraFocus, 0)
		end)
	end)
end

-- Get the camera's forward/right vectors projected onto XZ plane (for WASD movement)
local function getCameraDirections(): (Vector3, Vector3)
	local forward = Vector3.new(-math.sin(cameraYaw), 0, -math.cos(cameraYaw)).Unit
	local right = Vector3.new(-forward.Z, 0, forward.X) -- perpendicular on XZ (right-hand rule)
	return forward, right
end

-- ── Polygon helpers ───────────────────────────────────────────────────────────

local function polyGetFolder(): Folder
	local f = workspace:FindFirstChild("MapEditorPolyFolder")
	if not f then
		f = Instance.new("Folder")
		f.Name = "MapEditorPolyFolder"
		f.Parent = workspace
	end
	return f :: Folder
end

-- Ray-cast point-in-polygon test (XZ plane)
local function pointInPolygon(px: number, pz: number, nodes: { { x: number, z: number } }): boolean
	local inside = false
	local j = #nodes
	for i = 1, #nodes do
		local xi, zi = nodes[i].x, nodes[i].z
		local xj, zj = nodes[j].x, nodes[j].z
		if (zi > pz) ~= (zj > pz) then
			if px < (xj - xi) * (pz - zi) / (zj - zi) + xi then
				inside = not inside
			end
		end
		j = i
	end
	return inside
end

-- Closest point on segment a→b; returns (cx, cz, t) where t is 0..1 along the segment
local function closestPointOnSegment(ax: number, az: number, bx: number, bz: number, px: number, pz: number): (number, number, number)
	local dx, dz = bx - ax, bz - az
	local lenSq = dx * dx + dz * dz
	if lenSq < 0.001 then return ax, az, 0 end
	local t = math.clamp(((px - ax) * dx + (pz - az) * dz) / lenSq, 0, 1)
	return ax + t * dx, az + t * dz, t
end

-- Create a thin neon cylinder between two XZ world points at height Y
local function makeCylinder(ax: number, ay: number, az: number, bx: number, bz: number,
	color: Color3, transparency: number, parent: Instance): BasePart?
	local dx, dz = bx - ax, bz - az
	local len = math.sqrt(dx * dx + dz * dz)
	if len < 0.5 then return nil end
	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Cylinder
	-- Cylinder default: length along Y axis. We rotate to lay along the XZ direction.
	part.Size = Vector3.new(2, len, 2)
	local mid = Vector3.new((ax + bx) / 2, ay, (az + bz) / 2)
	-- atan2(dx, dz) gives yaw so the cylinder's Y axis points from a to b in XZ
	local yaw = math.atan2(dx, dz)
	part.CFrame = CFrame.new(mid) * CFrame.Angles(0, yaw, math.rad(90))
	part.Anchored = true
	part.CanCollide = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Transparency = transparency
	part.CastShadow = false
	part.Parent = parent
	return part
end

-- Full rebuild of all polygon visuals (nodes, edges, fill, preview edge)
local function polyRebuildVisuals(hitPos: Vector3?)
	local folder = polyGetFolder()
	folder:ClearAllChildren()
	local n = #polyNodes
	if n == 0 then
		localPlayer:SetAttribute("EditorPolygonNodeCount", 0)
		localPlayer:SetAttribute("EditorPolygonClosed", false)
		return
	end

	local zoneNum = localPlayer:GetAttribute("EditorZoneNumber") or 0
	local zoneColor = ZONE_PAINT_COLORS[zoneNum] or Color3.fromRGB(200, 200, 200)
	local edgeColor = if polyIsClosed then zoneColor else Color3.fromRGB(255, 255, 255)
	local NODE_LIFT = 6 -- studs above terrain surface

	-- Nodes (spheres — first node is white to mark the close target)
	for i, node in ipairs(polyNodes) do
		local part = Instance.new("Part")
		part.Shape = Enum.PartType.Ball
		part.Size = Vector3.new(8, 8, 8)
		part.Position = Vector3.new(node.x, node.y + NODE_LIFT, node.z)
		part.Anchored = true
		part.CanCollide = false
		part.Material = Enum.Material.Neon
		part.Color = if i == 1 then Color3.fromRGB(255, 255, 255) else zoneColor
		part.Transparency = 0.15
		part.CastShadow = false
		part.Parent = folder
	end

	-- Edges between consecutive nodes
	for i = 1, n do
		local j = (i % n) + 1
		if i < n or polyIsClosed then
			local midY = (polyNodes[i].y + polyNodes[j].y) / 2 + NODE_LIFT
			makeCylinder(polyNodes[i].x, midY, polyNodes[i].z,
				polyNodes[j].x, polyNodes[j].z, edgeColor, 0.25, folder)
		end
	end

	-- Fill whenever 3+ nodes exist (live preview, not just when closed)
	if n >= 3 then
		local minX, minZ, maxX, maxZ = math.huge, math.huge, -math.huge, -math.huge
		local avgY = 0
		for _, nd in ipairs(polyNodes) do
			minX = math.min(minX, nd.x); maxX = math.max(maxX, nd.x)
			minZ = math.min(minZ, nd.z); maxZ = math.max(maxZ, nd.z)
			avgY += nd.y
		end
		avgY = avgY / n + NODE_LIFT
		local cell = POLY_FILL_CELL
		local fx = minX + cell / 2
		while fx < maxX do
			local fz = minZ + cell / 2
			while fz < maxZ do
				if pointInPolygon(fx, fz, polyNodes) then
					local part = Instance.new("Part")
					part.Shape = Enum.PartType.Block
					part.Size = Vector3.new(cell, 3, cell)
					part.Position = Vector3.new(fx, avgY, fz)
					part.Anchored = true
					part.CanCollide = false
					part.Material = Enum.Material.Neon
					part.Color = zoneColor
					part.Transparency = 0.5
					part.CastShadow = false
					part.Parent = folder
				end
				fz += cell
			end
			fx += cell
		end
	end

	-- Preview edge: last node → current mouse position (open polygon only)
	if not polyIsClosed and hitPos and n > 0 then
		local last = polyNodes[n]
		local edgeY = (last.y + (hitPos.Y or last.y)) / 2 + NODE_LIFT
		local p = makeCylinder(last.x, edgeY, last.z, hitPos.X, hitPos.Z,
			Color3.fromRGB(210, 210, 210), 0.5, folder)
		if p then p.Name = "PreviewEdge" end
	end

	-- Write status attributes so the UI panel can react without polling
	localPlayer:SetAttribute("EditorPolygonNodeCount", n)
	localPlayer:SetAttribute("EditorPolygonClosed", polyIsClosed)
end

-- Update only the preview edge (cheap per-frame call when not dragging)
local function polyUpdatePreviewEdge(hitPos: Vector3?)
	local folder = workspace:FindFirstChild("MapEditorPolyFolder")
	if not folder then return end
	local prev = folder:FindFirstChild("PreviewEdge")
	if prev then prev:Destroy() end
	if hitPos and #polyNodes > 0 and not polyIsClosed then
		local last = polyNodes[#polyNodes]
		local edgeY = (last.y + hitPos.Y) / 2 + 6
		local p = makeCylinder(last.x, edgeY, last.z, hitPos.X, hitPos.Z,
			Color3.fromRGB(210, 210, 210), 0.5, folder)
		if p then p.Name = "PreviewEdge" end
	end
end

-- Clear all polygon state and destroy workspace folder
local function clearPolygon()
	polyNodes = {}
	polyIsClosed = false
	polyDraggingNodeIdx = nil
	polyLastDragX = 0
	polyLastDragZ = 0
	local f = workspace:FindFirstChild("MapEditorPolyFolder")
	if f then f:Destroy() end
	localPlayer:SetAttribute("EditorPolygonNodeCount", 0)
	localPlayer:SetAttribute("EditorPolygonClosed", false)
end

-- ── End polygon helpers ───────────────────────────────────────────────────────

-- Read brush settings from player attributes (set by UI)
local previousTool = "Select"
local function syncBrushSettings()
	local newTool = localPlayer:GetAttribute("EditorActiveTool") or "Select"
	if newTool ~= previousTool then
		local ev = getMapEditorEvent()
		if ev then
			-- Zone overlay
			if newTool == "ZonePaint" then
				ev:FireServer("ShowZoneOverlay")
			elseif previousTool == "ZonePaint" then
				ev:FireServer("HideZoneOverlay")
			end
			-- Resource overlay
			if newTool == "Resources" then
				ev:FireServer("ShowResourceOverlay")
			elseif previousTool == "Resources" then
				ev:FireServer("HideResourceOverlay")
			end
		end
		-- Clear resource patch selection when leaving Select tool
		if previousTool == "Select" then
			clearPatchSelection()
		end
		previousTool = newTool
	end
	activeTool = newTool
	brushRadius = localPlayer:GetAttribute("EditorBrushRadius") or 20
	brushMode = localPlayer:GetAttribute("EditorBrushMode") or "Raise"
	brushStrength = localPlayer:GetAttribute("EditorBrushStrength") or 0.5
	brushHardness = localPlayer:GetAttribute("EditorBrushHardness") or 0.5
	brushShape = localPlayer:GetAttribute("EditorBrushShape") or "Circle"
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

	-- Ghost is always a flat disc/square projected on terrain surface
	local ghostHeight = 4 -- thin visual indicator
	if brushShape == "Square" then
		brushGhost.Shape = Enum.PartType.Block
		brushGhost.Size = Vector3.new(brushRadius * 2, ghostHeight, brushRadius * 2)
	else
		-- Circle: use a cylinder
		brushGhost.Shape = Enum.PartType.Cylinder
		brushGhost.Size = Vector3.new(ghostHeight, brushRadius * 2, brushRadius * 2)
	end

	-- Update color based on tool/mode
	if activeTool == "Eraser" then
		brushGhost.Color = Color3.fromRGB(255, 80, 80)
	elseif brushMode == "Paint" then
		brushGhost.Color = MATERIAL_COLORS[brushMaterial] or Color3.fromRGB(200, 200, 200)
	else
		brushGhost.Color = MODE_COLORS[brushMode] or Color3.fromRGB(200, 200, 200)
	end

	-- Transparency varies slightly with hardness (softer = more transparent at edges)
	brushGhost.Transparency = 0.4 + (1 - brushHardness) * 0.3

	-- Position at terrain surface
	if brushShape == "Circle" then
		-- Cylinder rotated to lay flat on XZ plane
		brushGhost.CFrame = CFrame.new(position.X, position.Y + ghostHeight / 2, position.Z)
			* CFrame.Angles(0, 0, math.rad(90))
	else
		brushGhost.Position = Vector3.new(position.X, position.Y + ghostHeight / 2, position.Z)
	end
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

-- Raycast to a horizontal plane at a given Y (used for zone overlay interaction)
local function raycastToPlane(planeY: number): Vector3?
	local mouseLocation = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouseLocation.X, mouseLocation.Y)
	if ray.Direction.Y ~= 0 then
		local t = (planeY - ray.Origin.Y) / ray.Direction.Y
		if t > 0 then
			return ray.Origin + ray.Direction * t
		end
	end
	return nil
end

-- Add a sculpt stroke to pending batch
local function addSculptStroke(position: Vector3)
	local stroke = {
		Position = { X = position.X, Y = position.Y, Z = position.Z },
		Radius = brushRadius,
		Strength = brushStrength,
		Hardness = brushHardness,
		Mode = brushMode,
		Shape = brushShape,
		Material = brushMaterial,
	}
	table.insert(pendingStrokes, stroke)
	pendingStrokeType = "Sculpt"
end

-- Add an eraser stroke (lower with max strength)
local function addEraserStroke(position: Vector3)
	local stroke = {
		Position = { X = position.X, Y = position.Y, Z = position.Z },
		Radius = brushRadius,
		Strength = 1.0,
		Hardness = 1.0,
		Mode = "Lower",
		Shape = brushShape,
		Material = "Air",
	}
	table.insert(pendingStrokes, stroke)
	pendingStrokeType = "Sculpt"
end

-- Update resource patch ghost preview
local function updateResourceGhost(position: Vector3?)
	if activeTool ~= "Resources" then
		if resourceGhost then resourceGhost.Parent = nil end
		return
	end

	if not position then
		if resourceGhost then resourceGhost.Parent = nil end
		return
	end

	if not resourceGhost then
		resourceGhost = Instance.new("Part")
		resourceGhost.Name = "ResourceGhost"
		resourceGhost.Anchored = true
		resourceGhost.CanCollide = false
		resourceGhost.Material = Enum.Material.Neon
		resourceGhost.CastShadow = false
		resourceGhost.Shape = Enum.PartType.Cylinder
	end

	local radius = localPlayer:GetAttribute("EditorResourceBrushRadius") or 30
	local resourceType = localPlayer:GetAttribute("EditorResourceType") or "Wood"
	local ghostH = 3
	resourceGhost.Size = Vector3.new(ghostH, radius * 2, radius * 2)
	resourceGhost.CFrame = CFrame.new(position.X, position.Y + ghostH / 2, position.Z)
		* CFrame.Angles(0, 0, math.rad(90))
	resourceGhost.Color = RESOURCE_COLORS[resourceType] or Color3.fromRGB(200, 200, 200)
	resourceGhost.Transparency = 0.4
	resourceGhost.Parent = workspace
end

-- Update zone paint ghost preview
local function updateZonePaintGhost(position: Vector3?)
	if activeTool ~= "ZonePaint" then
		if zonePaintGhost then zonePaintGhost.Parent = nil end
		return
	end

	if not position then
		if zonePaintGhost then zonePaintGhost.Parent = nil end
		return
	end

	if not zonePaintGhost then
		zonePaintGhost = Instance.new("Part")
		zonePaintGhost.Name = "ZonePaintGhost"
		zonePaintGhost.Anchored = true
		zonePaintGhost.CanCollide = false
		zonePaintGhost.Material = Enum.Material.Neon
		zonePaintGhost.CastShadow = false
	end

	local radius = localPlayer:GetAttribute("EditorZoneBrushRadius") or 40
	local shape = localPlayer:GetAttribute("EditorZoneBrushShape") or "Circle"
	local zoneNum = localPlayer:GetAttribute("EditorZoneNumber") or 0
	local ghostH = 3

	if shape == "Square" then
		zonePaintGhost.Shape = Enum.PartType.Block
		zonePaintGhost.Size = Vector3.new(radius * 2, ghostH, radius * 2)
		zonePaintGhost.Position = Vector3.new(position.X, position.Y + ghostH / 2, position.Z)
	else
		zonePaintGhost.Shape = Enum.PartType.Cylinder
		zonePaintGhost.Size = Vector3.new(ghostH, radius * 2, radius * 2)
		zonePaintGhost.CFrame = CFrame.new(position.X, position.Y + ghostH / 2, position.Z)
			* CFrame.Angles(0, 0, math.rad(90))
	end

	zonePaintGhost.Color = ZONE_PAINT_COLORS[zoneNum] or Color3.fromRGB(200, 200, 200)
	zonePaintGhost.Transparency = 0.45
	zonePaintGhost.Parent = workspace
end


-- Update keep spawn ghost preview
local function updateKeepSpawnGhost(position: Vector3?)
	local isSpawnsMode = activeTool == "ZonePaint"
		and (localPlayer:GetAttribute("EditorZoneMode") or "Brush") == "Spawns"
	if not isSpawnsMode then
		if keepSpawnGhost then keepSpawnGhost.Parent = nil end
		return
	end

	if not position then
		if keepSpawnGhost then keepSpawnGhost.Parent = nil end
		return
	end

	if not keepSpawnGhost then
		keepSpawnGhost = Instance.new("Part")
		keepSpawnGhost.Name = "KeepSpawnGhost"
		keepSpawnGhost.Anchored = true
		keepSpawnGhost.CanCollide = false
		keepSpawnGhost.Material = Enum.Material.Neon
		keepSpawnGhost.CastShadow = false
		keepSpawnGhost.Shape = Enum.PartType.Block
	end

	local radius = localPlayer:GetAttribute("EditorKeepSpawnRadius") or 150
	local zoneNum = localPlayer:GetAttribute("EditorKeepSpawnZone") or 1
	local ghostH = 3
	keepSpawnGhost.Size = Vector3.new(radius * 2, ghostH, radius * 2)
	keepSpawnGhost.CFrame = CFrame.new(position.X, position.Y + ghostH / 2, position.Z)
	-- Red tint if any corner/edge of the square is outside the correct zone
	local spawnValid = true
	local sampleOffsets = {
		{ 0, 0 },
		{ radius, radius }, { -radius, radius },
		{ radius, -radius }, { -radius, -radius },
		{ radius, 0 }, { -radius, 0 },
		{ 0, radius }, { 0, -radius },
	}
	for _, off in ipairs(sampleOffsets) do
		if getZoneAt(position.X + off[1], position.Z + off[2]) ~= zoneNum then
			spawnValid = false
			break
		end
	end
	if spawnValid then
		keepSpawnGhost.Color = KEEP_SPAWN_COLORS[zoneNum] or Color3.fromRGB(200, 200, 200)
		keepSpawnGhost.Transparency = 0.4
	else
		keepSpawnGhost.Color = Color3.fromRGB(220, 50, 50) -- red = invalid zone
		keepSpawnGhost.Transparency = 0.5
	end
	keepSpawnGhost.Parent = workspace
end

-- Flush pending strokes to server
local function flushStrokes()
	if #pendingStrokes == 0 then return end

	local event = getMapEditorEvent()
	if event then
		local action
		if pendingStrokeType == "Sculpt" then
			action = "SculptTerrain"
		elseif pendingStrokeType == "Resource" then
			action = "PlaceResourcePatch"
		elseif pendingStrokeType == "ZonePaint" then
			action = "PaintZone"
		else
			action = "PaintTerrain"
		end
		event:FireServer(action, pendingStrokes)
		MapEditorControllerDebug:info("Flushed " .. #pendingStrokes .. " " .. pendingStrokeType .. " strokes to server")
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

	-- Initialize orbit camera
	cameraFocus = Vector3.new(0, 0, 0)
	cameraDistance = 300
	cameraYaw = 0
	cameraPitch = -math.rad(60)
	camera.CFrame = calculateCameraCFrame()

	-- Streaming anchor: a hidden part that sits at ground level under the camera
	-- focus point. When StreamingEnabled is on, Roblox uses the character or
	-- CameraSubject as the streaming origin. With no subject in the map editor,
	-- terrain unloads as you zoom out. Parenting this part to the camera keeps
	-- it within the streaming radius so terrain stays loaded at all zoom levels.
	local streamAnchor = workspace:FindFirstChild("__MapEditorStreamAnchor__")
	if not streamAnchor then
		streamAnchor = Instance.new("Part")
		streamAnchor.Name = "__MapEditorStreamAnchor__"
		streamAnchor.Size = Vector3.new(1, 1, 1)
		streamAnchor.Anchored = true
		streamAnchor.CanCollide = false
		streamAnchor.Transparency = 1
		streamAnchor.CastShadow = false
		streamAnchor.Parent = workspace
	end
	streamAnchor.Position = Vector3.new(cameraFocus.X, 0, cameraFocus.Z)

	-- Move anchor with camera focus so it always sits under what you're looking at
	local streamConnection = game:GetService("RunService").Heartbeat:Connect(function()
		if isEditorActive and streamAnchor and streamAnchor.Parent then
			streamAnchor.Position = Vector3.new(cameraFocus.X, 0, cameraFocus.Z)
		end
	end)
	-- Store connection so we can clean it up on editor exit
	localPlayer:SetAttribute("__EditorStreamConnActive__", true)
	task.spawn(function()
		-- Wait until editor is no longer active then disconnect
		while localPlayer:GetAttribute("__EditorStreamConnActive__") do
			task.wait(0.5)
		end
		streamConnection:Disconnect()
		if streamAnchor and streamAnchor.Parent then
			streamAnchor:Destroy()
		end
	end)

	-- Set default brush attributes
	localPlayer:SetAttribute("EditorActiveTool", "Select")
	localPlayer:SetAttribute("EditorBrushRadius", 20)
	localPlayer:SetAttribute("EditorBrushMode", "Raise")
	localPlayer:SetAttribute("EditorBrushStrength", 0.5)
	localPlayer:SetAttribute("EditorBrushHardness", 0.5)
	localPlayer:SetAttribute("EditorBrushShape", "Circle")
	localPlayer:SetAttribute("EditorBrushMaterial", "Grass")
	localPlayer:SetAttribute("EditorFeatureType", "Mountain")
	localPlayer:SetAttribute("EditorFeatureScale", 1.0)
	localPlayer:SetAttribute("EditorResourceType", "Wood")
	localPlayer:SetAttribute("EditorResourceBrushRadius", 30)
	localPlayer:SetAttribute("EditorResourceDensity", 5)
	localPlayer:SetAttribute("EditorResourceZoneOwner", 0)
	localPlayer:SetAttribute("EditorZoneNumber", 0)
	localPlayer:SetAttribute("EditorZoneBrushRadius", 40)
	localPlayer:SetAttribute("EditorZoneBrushShape", "Circle")
	localPlayer:SetAttribute("EditorKeepSpawnZone", 1)
	localPlayer:SetAttribute("EditorKeepSpawnRadius", 150)

	-- Reset zone areas (0-4 territory + 5 Impassable + 6 No Build)
	zoneAreas = { [0]=0, [1]=0, [2]=0, [3]=0, [4]=0, [5]=0, [6]=0 }
	zonePendingArea = { [0]=0, [1]=0, [2]=0, [3]=0, [4]=0, [5]=0, [6]=0 }

	-- Reset zone overlay state (server handles terrain painting)
	previousTool = "Select"
	zoneOverlayStrokes = {}
end

local function deactivateEditor()
	if not isEditorActive then return end
	isEditorActive = false
	-- Signal the streaming anchor cleanup task to stop
	localPlayer:SetAttribute("__EditorStreamConnActive__", false)
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

	-- Clear placed patch history so a new session starts fresh
	placedResourcePositions = {}

	-- Clean up resource ghost
	if resourceGhost then
		resourceGhost:Destroy()
		resourceGhost = nil
	end

	-- Clean up zone paint ghost
	if zonePaintGhost then
		zonePaintGhost:Destroy()
		zonePaintGhost = nil
	end

	-- Clean up keep spawn ghost
	if keepSpawnGhost then
		keepSpawnGhost:Destroy()
		keepSpawnGhost = nil
	end

	-- Reset zone overlay state
	zoneOverlayStrokes = {}

	-- Clean up polygon painter
	clearPolygon()

	isPainting = false
	lastPaintPosition = nil
end

-- Listen for MapEditorEvent from server (EditorReady / MapLoaded)
do
	local remoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
	local mapEditorEv = remoteEvents:WaitForChild("MapEditorEvent") :: RemoteEvent
	mapEditorEv.OnClientEvent:Connect(function(action: string, data: any)
		if (action == "EditorReady" or action == "MapLoaded") and data then
			local savedStrokes = data.ZonePaintStrokes
			-- Mirror strokes locally so ghost feedback stays in sync
			zoneOverlayStrokes = savedStrokes or {}
			MapEditorControllerDebug:info("Zone strokes mirrored from server: " .. #zoneOverlayStrokes)
			-- If ZonePaint tool is already active, ask server to repaint the overlay
			if activeTool == "ZonePaint" then
				local ev = getMapEditorEvent()
				if ev then
					ev:FireServer("ShowZoneOverlay")
				end
			end
		elseif action == "ZoneStats" and data then
			-- Server is now authoritative — replace both confirmed and pending
			-- Covers all zones: 0-4 territory + 5 Impassable + 6 No Build
			local areas = data.areas or {}
			for zone = 0, 6 do
				zoneAreas[zone] = areas[zone] or 0
				zonePendingArea[zone] = 0  -- server figure already includes these strokes
			end
			pushZoneAreasToUI()
		elseif action == "ResourceStats" and data then
			-- Encode resource areas as "Type=tenths;Type=tenths;..." attribute
			local areas = data.areas or {}
			local parts: { string } = {}
			for rType, pct in pairs(areas) do
				table.insert(parts, rType .. "=" .. tostring(math.floor(pct * 10 + 0.5)))
			end
			localPlayer:SetAttribute("EditorResourceAreas", table.concat(parts, ";"))
		end
	end)
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

-- Polygon commit: UI sets EditorCommitPolygon=true → send to server + clear
localPlayer:GetAttributeChangedSignal("EditorCommitPolygon"):Connect(function()
	if not localPlayer:GetAttribute("EditorCommitPolygon") then return end
	localPlayer:SetAttribute("EditorCommitPolygon", false)
	if polyIsClosed and #polyNodes >= 3 then
		local zoneNum = localPlayer:GetAttribute("EditorZoneNumber") or 0
		local verts = {}
		for _, nd in ipairs(polyNodes) do
			table.insert(verts, { X = nd.x, Z = nd.z })
		end
		local ev = getMapEditorEvent()
		if ev then
			ev:FireServer("PaintZonePolygon", { Zone = zoneNum, Vertices = verts })
		end
		clearPolygon()
	end
end)

-- Polygon cancel: UI sets EditorCancelPolygon=true → clear local polygon
localPlayer:GetAttributeChangedSignal("EditorCancelPolygon"):Connect(function()
	if not localPlayer:GetAttribute("EditorCancelPolygon") then return end
	localPlayer:SetAttribute("EditorCancelPolygon", false)
	clearPolygon()
end)

-- Flush immediately and reset pending area when the player switches zones.
-- This ensures the UI reflects the correct remaining budget for the new zone right away,
-- and the server gets the previous zone's strokes before the new ones start.
localPlayer:GetAttributeChangedSignal("EditorZoneNumber"):Connect(function()
	flushStrokes()
	zonePendingArea = { [0]=0, [1]=0, [2]=0, [3]=0, [4]=0 }
	pushZoneAreasToUI()
end)

-- When entering screenshot mode, auto-fit camera distance to show the full map.
-- D = mapSize / (2 * tan(FOV/2)); with 70° FOV → D = mapSize / 1.4
localPlayer:GetAttributeChangedSignal("EditorScreenshotMode"):Connect(function()
	if localPlayer:GetAttribute("EditorScreenshotMode") == true then
		local mapSize = localPlayer:GetAttribute("EditorScreenshotMapSize") or 1000
		cameraDistance = (mapSize :: number) / 1.4
	end
end)

-- Check on startup in case attribute was already set
if localPlayer:GetAttribute("MapEditorActive") then
	activateEditor()
end

-- Input handling
-- Movement keys that should work even when UI has focus
local CAMERA_MOVE_KEYS = {
	[Enum.KeyCode.W] = true, [Enum.KeyCode.A] = true,
	[Enum.KeyCode.S] = true, [Enum.KeyCode.D] = true,
	[Enum.KeyCode.Up] = true, [Enum.KeyCode.Down] = true,
	[Enum.KeyCode.Left] = true, [Enum.KeyCode.Right] = true,
	[Enum.KeyCode.Q] = true, [Enum.KeyCode.E] = true,
}

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if not isEditorActive then return end
	if localPlayer:GetAttribute("EditorScreenshotMode") == true then return end

	if input.UserInputType == Enum.UserInputType.Keyboard then
		-- Camera movement keys always register, even when UI has focus
		if CAMERA_MOVE_KEYS[input.KeyCode] then
			keysDown[input.KeyCode] = true
			return
		end

		if gameProcessed then return end

		local ctrl = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
			or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)

		-- Ctrl+Z: Undo last sculpt stroke
		if ctrl and input.KeyCode == Enum.KeyCode.Z then
			local event = getMapEditorEvent()
			if event then
				event:FireServer("UndoStroke")
				MapEditorControllerDebug:info("UndoStroke sent")
			end
			return -- Don't set keysDown or process further
		end

		-- Ctrl+Y: Redo last undone stroke
		if ctrl and input.KeyCode == Enum.KeyCode.Y then
			local event = getMapEditorEvent()
			if event then
				event:FireServer("RedoStroke")
				MapEditorControllerDebug:info("RedoStroke sent")
			end
			return
		end

		-- Delete: remove selected resource patch
		if input.KeyCode == Enum.KeyCode.Delete and activeTool == "Select" and selectedPatchId then
			local event = getMapEditorEvent()
			if event then
				event:FireServer("DeleteResourcePatch", selectedPatchId)
				MapEditorControllerDebug:info("DeleteResourcePatch sent:", selectedPatchId)
			end
			clearPatchSelection()
			return
		end

		keysDown[input.KeyCode] = true
	end

	-- Ignore all mouse clicks that land on UI elements
	local overGui = isMouseOverGui()

	-- Right mouse button: orbit rotation, but in polygon mode right-clicking a node deletes it
	if input.UserInputType == Enum.UserInputType.MouseButton2 and not overGui then
		local zoneMode2 = localPlayer:GetAttribute("EditorZoneMode") or "Brush"
		local deletedNode = false
		if activeTool == "ZonePaint" and zoneMode2 == "Polygon" and #polyNodes > 0 then
			local hitPos2 = raycastToTerrain()
			if hitPos2 then
				for i, nd in ipairs(polyNodes) do
					local d = math.sqrt((hitPos2.X - nd.x)^2 + (hitPos2.Z - nd.z)^2)
					if d <= POLY_NODE_HIT then
						table.remove(polyNodes, i)
						if #polyNodes < 3 then polyIsClosed = false end
						polyRebuildVisuals(hitPos2)
						deletedNode = true
						break
					end
				end
			end
		end
		if not deletedNode then
			isRotating = true
			lastMousePosition = UserInputService:GetMouseLocation()
		end
	end

	-- Middle mouse button for panning
	if input.UserInputType == Enum.UserInputType.MouseButton3 and not overGui then
		isPanning = true
		lastMousePosition = UserInputService:GetMouseLocation()
	end

	-- Left mouse button for painting/interaction
	if input.UserInputType == Enum.UserInputType.MouseButton1 and not overGui then
		syncBrushSettings()
		if activeTool == "TerrainBrush" then
			isPainting = true
			local hitPos = raycastToTerrain()
			if hitPos then
				addSculptStroke(hitPos)
				lastPaintPosition = hitPos
			end
		elseif activeTool == "Eraser" then
			isPainting = true
			local hitPos = raycastToTerrain()
			if hitPos then
				addEraserStroke(hitPos)
				lastPaintPosition = hitPos
			end
		elseif activeTool == "FeaturePlace" then
			local hitPos = raycastToTerrain()
			if hitPos then
				local featureType = localPlayer:GetAttribute("EditorFeatureType") or "Mountain"
				local featureScale = localPlayer:GetAttribute("EditorFeatureScale") or 1.0
				local event = getMapEditorEvent()
				if event then
					event:FireServer("PlaceFeature", {
						FeatureType = featureType,
						Position = { X = hitPos.X, Y = 0, Z = hitPos.Z },
						Scale = featureScale,
						Rotation = 0,
					})
					MapEditorControllerDebug:info("Placing feature:", featureType, "at", hitPos.X, hitPos.Z)
				end
			end
		elseif activeTool == "Resources" then
			isPainting = true
			local hitPos = raycastToTerrain()
			if hitPos then
				local resourceType = localPlayer:GetAttribute("EditorResourceType") or "Wood"
				local zoneOwner = localPlayer:GetAttribute("EditorResourceZoneOwner") or 0
				local radius = localPlayer:GetAttribute("EditorResourceBrushRadius") or 30
				local density = localPlayer:GetAttribute("EditorResourceDensity") or 5
				local resRowKey = tostring(zoneOwner) .. "_" .. resourceType
				local resUsed = getResourceAreaPct(resRowKey)
				if canPlaceResourcePatch(hitPos, radius) and not isOverBudget("EditorResource", resRowKey, resUsed) then
					table.insert(pendingStrokes, {
						ResourceType = resourceType,
						ZoneOwner = zoneOwner,
						Position = { X = hitPos.X, Z = hitPos.Z },
						Radius = radius,
						Density = density,
					})
					pendingStrokeType = "Resource"
					lastPaintPosition = hitPos
					recordResourcePatch(hitPos)
				end
			end
		elseif activeTool == "Select" then
			-- Try to pick a resource patch disc near the click
			local hitPos = raycastToTerrain()
			if hitPos then
				clearPatchSelection()
				local patchId, patchPart = findNearestResourcePatch(hitPos, 60)
				if patchId and patchPart then
					selectedPatchId = patchId
					selectedPatchOriginalColor = patchPart.Color
					selectedPatchPart = patchPart
					patchPart.Color = Color3.fromRGB(255, 255, 255)
					MapEditorControllerDebug:info("Selected resource patch:", patchId)
				end
			end
		elseif activeTool == "ZonePaint" then
			local zoneMode = localPlayer:GetAttribute("EditorZoneMode") or "Brush"
			if zoneMode == "Spawns" then
				-- ── Spawns mode: click to place a keep spawn disc ────────────
				local hitPos = raycastToTerrain()
				if hitPos then
					local zoneNum = localPlayer:GetAttribute("EditorKeepSpawnZone") or 1
					local radius = localPlayer:GetAttribute("EditorKeepSpawnRadius") or 150
					local event = getMapEditorEvent()
					if event then
						event:FireServer("UpdateKeepSpawn", {
							Zone = zoneNum,
							Position = { X = hitPos.X, Y = hitPos.Y, Z = hitPos.Z },
							Radius = radius,
						})
						MapEditorControllerDebug:info("Keep spawn placed: zone", zoneNum, "at", hitPos.X, hitPos.Z)
					end
				end
			elseif zoneMode == "Polygon" then
				-- ── Polygon mode: place/drag nodes, insert on edges, close polygon ──
				local hitPos = raycastToTerrain()
				if hitPos then
					-- Helper: find closest node index within POLY_NODE_HIT, or nil
					local function findNearestNode(): number?
						for i, nd in ipairs(polyNodes) do
							local d = math.sqrt((hitPos.X - nd.x)^2 + (hitPos.Z - nd.z)^2)
							if d <= POLY_NODE_HIT then return i end
						end
						return nil
					end

					-- Helper: find closest edge (returns edgeIdx, t) or nil
					local function findNearestEdge(): (number?, number)
						local bestIdx: number? = nil
						local bestT = 0
						local bestDist = POLY_EDGE_HIT
						local nc = #polyNodes
						for i = 1, nc do
							local j = (i % nc) + 1
							if i < nc or polyIsClosed then
								local _, _, t = closestPointOnSegment(
									polyNodes[i].x, polyNodes[i].z,
									polyNodes[j].x, polyNodes[j].z,
									hitPos.X, hitPos.Z)
								local cx = polyNodes[i].x + t * (polyNodes[j].x - polyNodes[i].x)
								local cz = polyNodes[i].z + t * (polyNodes[j].z - polyNodes[i].z)
								local d = math.sqrt((hitPos.X - cx)^2 + (hitPos.Z - cz)^2)
								if d < bestDist then bestDist = d; bestIdx = i; bestT = t end
							end
						end
						return bestIdx, bestT
					end

					local nearNode = findNearestNode()
					if nearNode then
						-- Click on existing node → start drag
						polyDraggingNodeIdx = nearNode
					else
						local edgeIdx, edgeT = findNearestEdge()
						if edgeIdx then
							-- Click near an edge → insert node at that point
							local a = polyNodes[edgeIdx]
							local b = polyNodes[(edgeIdx % #polyNodes) + 1]
							local nx = a.x + edgeT * (b.x - a.x)
							local nz = a.z + edgeT * (b.z - a.z)
							local ny = (a.y + b.y) / 2
							table.insert(polyNodes, edgeIdx + 1, { x = nx, y = ny, z = nz })
							polyRebuildVisuals(hitPos)
						elseif polyIsClosed then
							-- Closed polygon, click on empty space → reopen so user can keep adding nodes
							polyIsClosed = false
							table.insert(polyNodes, { x = hitPos.X, y = hitPos.Y, z = hitPos.Z })
							polyRebuildVisuals(hitPos)
						elseif #polyNodes >= 3 then
							-- Open polygon with ≥3 nodes: check snap-to-first → close, else add node
							local first = polyNodes[1]
							local d = math.sqrt((hitPos.X - first.x)^2 + (hitPos.Z - first.z)^2)
							if d <= POLY_CLOSE_SNAP then
								polyIsClosed = true
								polyRebuildVisuals(nil)
							else
								table.insert(polyNodes, { x = hitPos.X, y = hitPos.Y, z = hitPos.Z })
								polyRebuildVisuals(hitPos)
							end
						else
							-- Fewer than 3 nodes: always add
							table.insert(polyNodes, { x = hitPos.X, y = hitPos.Y, z = hitPos.Z })
							polyRebuildVisuals(hitPos)
						end
					end
				end
			else
				-- ── Brush mode (original behaviour) ──────────────────────────────
				isPainting = true
				local hitPos = raycastToTerrain()
				if hitPos then
					local zoneNum = localPlayer:GetAttribute("EditorZoneNumber") or 0
					local radius = localPlayer:GetAttribute("EditorZoneBrushRadius") or 40
					local shape = localPlayer:GetAttribute("EditorZoneBrushShape") or "Circle"
					local currentPct1 = (zoneAreas[zoneNum] or 0) + (zonePendingArea[zoneNum] or 0)
					local overBudget = isOverBudget("EditorZone", tostring(zoneNum), currentPct1)
					if not overBudget then
						local stroke = {
							Zone = zoneNum,
							Position = { X = hitPos.X, Z = hitPos.Z },
							Radius = radius,
							Shape = shape,
						}
						table.insert(pendingStrokes, stroke)
						pendingStrokeType = "ZonePaint"
						lastPaintPosition = hitPos
						local mapSize1 = localPlayer:GetAttribute("EditorMapSize") or 1000
						local strokePct1 = if shape == "Square"
							then ((radius * 2) * (radius * 2)) / (mapSize1 * mapSize1) * 100
							else (math.pi * radius * radius) / (mapSize1 * mapSize1) * 100
						zonePendingArea[zoneNum] = (zonePendingArea[zoneNum] or 0) + strokePct1
					end
				end
			end
		end
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if not isEditorActive then return end
	if localPlayer:GetAttribute("EditorScreenshotMode") == true then return end

	if input.UserInputType == Enum.UserInputType.Keyboard then
		keysDown[input.KeyCode] = nil
	end

	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		isRotating = false
		lastMousePosition = nil
	end

	if input.UserInputType == Enum.UserInputType.MouseButton3 then
		isPanning = false
		lastMousePosition = nil
	end

	-- Stop painting and flush remaining strokes
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		-- Release polygon node drag
		if polyDraggingNodeIdx then
			polyDraggingNodeIdx = nil
			polyRebuildVisuals(nil) -- final rebuild with fill when drag ends
		end
		if isPainting then
			isPainting = false
			lastPaintPosition = nil
			flushStrokes()
		end
	end
end)

-- Scroll to zoom + mouse drag for rotate/pan
UserInputService.InputChanged:Connect(function(input)
	if not isEditorActive then return end
	if localPlayer:GetAttribute("EditorScreenshotMode") == true then return end

	-- Scroll to zoom (move camera closer/farther from focus)
	if input.UserInputType == Enum.UserInputType.MouseWheel then
		local zoomFactor = 1 - input.Position.Z * 0.1 -- 10% per scroll notch
		cameraDistance = math.clamp(cameraDistance * zoomFactor, minDistance, maxDistance)
	end

	if input.UserInputType == Enum.UserInputType.MouseMovement then
		local currentPos = UserInputService:GetMouseLocation()

		-- Right mouse drag: orbit rotation
		if isRotating and lastMousePosition then
			local delta = currentPos - lastMousePosition
			cameraYaw = cameraYaw - delta.X * cameraRotateSpeed
			cameraPitch = math.clamp(cameraPitch + delta.Y * cameraRotateSpeed, minPitch, maxPitch)
		end

		-- Middle mouse drag: pan focus point
		if isPanning and lastMousePosition then
			local delta = currentPos - lastMousePosition
			local panScale = cameraDistance / 300
			local forward, right = getCameraDirections()
			-- Pan: horizontal mouse = right, vertical mouse = forward
			cameraFocus = cameraFocus - right * delta.X * panScale - forward * delta.Y * panScale
		end

		if isRotating or isPanning then
			lastMousePosition = currentPos
		end
	end
end)

-- Main update loop
RunService.RenderStepped:Connect(function(dt)
	if not isEditorActive then return end

	-- Screenshot mode: lock camera straight down, hide ghosts, skip painting
	local screenshotMode = localPlayer:GetAttribute("EditorScreenshotMode") == true
	if screenshotMode then
		cameraYaw = 0
		cameraPitch = -math.rad(89)
		cameraFocus = Vector3.new(0, 0, 0)
		camera.CFrame = calculateCameraCFrame()
		-- Hide all ghosts
		if brushGhost then brushGhost.Parent = nil end
		return
	end

	-- Sync brush settings from UI attributes
	syncBrushSettings()

	-- WASD camera movement (moves the focus point relative to camera facing)
	local moveDir = Vector3.zero
	local forward, right = getCameraDirections()

	if keysDown[Enum.KeyCode.W] or keysDown[Enum.KeyCode.Up] then
		moveDir = moveDir + forward
	end
	if keysDown[Enum.KeyCode.S] or keysDown[Enum.KeyCode.Down] then
		moveDir = moveDir - forward
	end
	if keysDown[Enum.KeyCode.A] or keysDown[Enum.KeyCode.Left] then
		moveDir = moveDir - right
	end
	if keysDown[Enum.KeyCode.D] or keysDown[Enum.KeyCode.Right] then
		moveDir = moveDir + right
	end
	-- Q/E for vertical movement of focus point
	if keysDown[Enum.KeyCode.Q] then
		moveDir = moveDir + Vector3.new(0, -1, 0)
	end
	if keysDown[Enum.KeyCode.E] then
		moveDir = moveDir + Vector3.new(0, 1, 0)
	end

	if moveDir.Magnitude > 0 then
		local panScale = cameraDistance / 300
		cameraFocus = cameraFocus + moveDir.Unit * cameraPanSpeed * panScale * dt * 60
	end

	-- Update camera from orbit parameters
	camera.CFrame = calculateCameraCFrame()
	maybeRequestStreaming()

	-- Update ghost previews and continuous painting
	local hitPos = raycastToTerrain()
	updateResourceGhost(hitPos)

	-- Zone paint ghost: suppress in polygon mode
	local currentZoneMode = localPlayer:GetAttribute("EditorZoneMode") or "Brush"
	if activeTool == "ZonePaint" and currentZoneMode == "Polygon" then
		if zonePaintGhost then zonePaintGhost.Parent = nil end
	else
		updateZonePaintGhost(hitPos)
	end

	updateKeepSpawnGhost(hitPos)
	if hitPos then
		updateBrushGhost(hitPos)
	end

	-- Polygon mode: handle node drag + preview edge (runs even without hitPos for edge cleanup)
	if activeTool == "ZonePaint" and currentZoneMode == "Polygon" then
		local zoneHit = raycastToTerrain()
		if polyDraggingNodeIdx and zoneHit then
			-- Drag: update node position; only rebuild visuals if moved ≥4 studs
			local dx = zoneHit.X - polyLastDragX
			local dz = zoneHit.Z - polyLastDragZ
			if dx * dx + dz * dz >= 16 then
				polyNodes[polyDraggingNodeIdx] = { x = zoneHit.X, y = zoneHit.Y, z = zoneHit.Z }
				polyLastDragX = zoneHit.X
				polyLastDragZ = zoneHit.Z
				-- Rebuild edges + nodes only (skip fill during drag for performance)
				local folder = polyGetFolder()
				folder:ClearAllChildren()
				local zoneNum2 = localPlayer:GetAttribute("EditorZoneNumber") or 0
				local zoneColor2 = ZONE_PAINT_COLORS[zoneNum2] or Color3.fromRGB(200,200,200)
				local edgeColor2 = if polyIsClosed then zoneColor2 else Color3.fromRGB(255,255,255)
				local LIFT = 6
				for i2, node2 in ipairs(polyNodes) do
					local np = Instance.new("Part")
					np.Shape = Enum.PartType.Ball
					np.Size = Vector3.new(8, 8, 8)
					np.Position = Vector3.new(node2.x, node2.y + LIFT, node2.z)
					np.Anchored = true; np.CanCollide = false
					np.Material = Enum.Material.Neon
					np.Color = if i2 == 1 then Color3.fromRGB(255,255,255) else zoneColor2
					np.Transparency = 0.15; np.CastShadow = false
					np.Parent = folder
				end
				local nc2 = #polyNodes
				for i2 = 1, nc2 do
					local j2 = (i2 % nc2) + 1
					if i2 < nc2 or polyIsClosed then
						local midY2 = (polyNodes[i2].y + polyNodes[j2].y) / 2 + LIFT
						makeCylinder(polyNodes[i2].x, midY2, polyNodes[i2].z,
							polyNodes[j2].x, polyNodes[j2].z, edgeColor2, 0.25, folder)
					end
				end
			end
		elseif not polyIsClosed then
			-- Preview edge from last node to mouse
			polyUpdatePreviewEdge(zoneHit)
		end
	end

	if hitPos and isPainting then
		local distOk = true
		if lastPaintPosition then
			local dist = (hitPos - lastPaintPosition).Magnitude
			local minDist = if activeTool == "Resources"
				then (localPlayer:GetAttribute("EditorResourceBrushRadius") or 30) * 1.4
				else PAINT_MIN_DISTANCE
			distOk = dist >= minDist
		end

		if distOk then
			if activeTool == "Eraser" then
				addEraserStroke(hitPos)
				lastPaintPosition = hitPos
			elseif activeTool == "TerrainBrush" then
				addSculptStroke(hitPos)
				lastPaintPosition = hitPos
			elseif activeTool == "Resources" then
				local resourceType = localPlayer:GetAttribute("EditorResourceType") or "Wood"
				local zoneOwner2 = localPlayer:GetAttribute("EditorResourceZoneOwner") or 0
				local radius = localPlayer:GetAttribute("EditorResourceBrushRadius") or 30
				local density = localPlayer:GetAttribute("EditorResourceDensity") or 5
				local resRowKey2 = tostring(zoneOwner2) .. "_" .. resourceType
				local resUsed2 = getResourceAreaPct(resRowKey2)
				if canPlaceResourcePatch(hitPos, radius) and not isOverBudget("EditorResource", resRowKey2, resUsed2) then
					table.insert(pendingStrokes, {
						ResourceType = resourceType,
						ZoneOwner = zoneOwner2,
						Position = { X = hitPos.X, Z = hitPos.Z },
						Radius = radius,
						Density = density,
					})
					pendingStrokeType = "Resource"
					lastPaintPosition = hitPos
					recordResourcePatch(hitPos)
				end
			elseif activeTool == "ZonePaint" and currentZoneMode == "Brush" then
				local zoneNum = localPlayer:GetAttribute("EditorZoneNumber") or 0
				local radius = localPlayer:GetAttribute("EditorZoneBrushRadius") or 40
				local shape = localPlayer:GetAttribute("EditorZoneBrushShape") or "Circle"
				local currentPct2 = (zoneAreas[zoneNum] or 0) + (zonePendingArea[zoneNum] or 0)
				local overBudget = isOverBudget("EditorZone", tostring(zoneNum), currentPct2)
				if not overBudget then
					table.insert(pendingStrokes, {
						Zone = zoneNum,
						Position = { X = hitPos.X, Z = hitPos.Z },
						Radius = radius,
						Shape = shape,
					})
					pendingStrokeType = "ZonePaint"
					lastPaintPosition = hitPos
					local mapSize2 = localPlayer:GetAttribute("EditorMapSize") or 1000
					local strokePct2 = if shape == "Square"
						then ((radius * 2) * (radius * 2)) / (mapSize2 * mapSize2) * 100
						else (math.pi * radius * radius) / (mapSize2 * mapSize2) * 100
					zonePendingArea[zoneNum] = (zonePendingArea[zoneNum] or 0) + strokePct2
				end
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
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  