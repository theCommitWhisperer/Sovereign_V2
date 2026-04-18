--!strict
-- MapEditorManager: Server-side manager for the in-game map editor
-- Handles terrain operations, feature placement, and save/load

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")

local DebugManager = require(ReplicatedStorage.Shared.DebugManager)
local MapEditorDebug = DebugManager.createChannel("MapEditorManager", false)

local MapEditorManager = {}

-- Active editor sessions: { [userId]: CustomMapData }
local activeSessions: { [number]: any } = {}

-- Per-user unified action stacks for undo/redo
-- Each action: { type: "SculptStroke"|"ZonePaint"|"ResourcePatch", count: number, data: {any}? }
local undoStacks: { [number]: { any } } = {}  -- kept for legacy compat (SculptStroke redo data)
local redoStacks: { [number]: { any } } = {}
-- Unified action stacks (replaces the above for new code)
local undoActionStacks: { [number]: { { type: string, count: number, data: { any }? } } } = {}
local redoActionStacks: { [number]: { { type: string, count: number, data: { any }? } } } = {}

-- Track which users currently have the zone overlay visible
local zoneOverlayActive: { [number]: boolean } = {}
-- Track which users currently have the resource overlay visible
local resourceOverlayActive: { [number]: boolean } = {}

-- Forward declarations for resource overlay helpers (defined later, used in placeResourcePatch)
local paintResourceRegion: (terrain: Terrain, patches: { any }, minPt: Vector3, maxPt: Vector3) -> ()
local getResourceModelsFolder: () -> Folder
local scatterModelsForPatch: (folder: Folder, patch: any) -> ()
local foodPatchesOnly: (patches: { any }) -> { any }

-- DataStore for custom maps
local mapDataStore = DataStoreService:GetDataStore("SovereignMapEditor")

-- Helper to fire MapEditorEvent to client
local function fireEditorEvent(player: Player, action: string, data: any)
	local RemoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")
	if RemoteEvents then
		local MapEditorEvent = RemoteEvents:FindFirstChild("MapEditorEvent")
		if MapEditorEvent then
			MapEditorEvent:FireClient(player, action, data)
		end
	end
end

-- Returns true if Studio-built terrain should be preserved (not cleared/regenerated).
-- Controlled by a BoolValue named "UseStudioTerrain" in Workspace.
local function isStudioTerrainMode(): boolean
	local flag = workspace:FindFirstChild("UseStudioTerrain")
	return flag ~= nil and flag:IsA("BoolValue") and flag.Value == true
end

-- Compute the approximate percentage of map area claimed by each zone.
-- Uses a coarse grid sample (SAMPLE_CELL studs per cell) so it's fast enough
-- Returns the zone number (0–4, or -1 if unpainted) at a given XZ position
-- by replaying strokes in order (last writer wins).
local function getZoneAt(mapData: any, x: number, z: number): number
	local strokes = mapData.ZonePaintStrokes or {}
	local zone = -1
	for _, stroke in ipairs(strokes) do
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
	-- Also check polygon strokes (ZonePolygons baked in as strokes, so covered above)
	return zone
end

-- Forward declaration: defined later in file but called from placeResourcePatch
local placeFoodDiscParts: ((folder: Instance, patches: { any }) -> ())?

-- Zone overlay constants (declared here so computeZoneAreas fast path can use them)
-- Single unified grid: every cell has exactly one Part whose colour reflects its zone.
-- 32-stud cells keep part count low (≤2304 for max 1500-stud map) while still giving
-- readable zone boundaries at RTS camera distances.
local OVERLAY_CELL   = 32  -- studs per grid cell
local OVERLAY_PART_H = 3   -- slab height (studs)
local OVERLAY_LIFT   = 1   -- studs above terrain surface

-- Cached grid state for zone visualization: key "ix,iz" → zone number.
-- Declared here so computeZoneAreas (below) can read it for the fast path.
local zoneGridCache: { [string]: number } = {}

-- to call after every paint batch.  Returns a table keyed by zone number (0–6)
-- where each value is a percentage (0–100) of total map cells.
-- Zones 0-4 = territory; 5 = Impassable; 6 = No Build.
-- Uses zoneGridCache (kept in sync by updateZoneVisualization) when available
-- to avoid an O(cells×strokes) scan on every paint.
local ZONE_SAMPLE_CELL = 24 -- stud resolution for sampling (used for full-scan fallback)
local function computeZoneAreas(mapData: any): { [number]: number }
	-- Fast path: if the grid cache is populated, derive areas directly from it.
	-- The cache uses OVERLAY_CELL resolution; we sum counts per zone.
	if next(zoneGridCache) ~= nil then
		local counts: { [number]: number } = { [0]=0,[1]=0,[2]=0,[3]=0,[4]=0,[5]=0,[6]=0 }
		local total = 0
		for _, zone in pairs(zoneGridCache) do
			counts[zone] = (counts[zone] or 0) + 1
			total += 1
		end
		-- Total possible cells = map area / cell area (cells outside any stroke aren't in cache)
		-- We want % of MAP area, so compute total map cells at OVERLAY_CELL resolution.
		local mapSize = mapData.Size or 1000
		local mapCells = math.floor(mapSize / OVERLAY_CELL) * math.floor(mapSize / OVERLAY_CELL)
		if mapCells <= 0 then mapCells = total end
		local result: { [number]: number } = {}
		for zone = 0, 6 do
			result[zone] = math.floor((counts[zone] or 0) / mapCells * 1000 + 0.5) / 10
		end
		return result
	end

	-- Slow path: no cache yet (called before first overlay build). Full scan.
	local strokes = mapData.ZonePaintStrokes or {}
	local mapSize = mapData.Size or 1000
	local half = mapSize / 2

	local counts: { [number]: number } = { [0]=0,[1]=0,[2]=0,[3]=0,[4]=0,[5]=0,[6]=0 }
	local totalCells = 0

	local x = -half
	while x < half do
		local z = -half
		while z < half do
			local assignedZone = -1
			for _, stroke in ipairs(strokes) do
				local dx = x - stroke.Position.X
				local dz = z - stroke.Position.Z
				local r = stroke.Radius or 40
				local inside = if stroke.Shape == "Square"
					then math.abs(dx) <= r and math.abs(dz) <= r
					else dx * dx + dz * dz <= r * r
				if inside then
					assignedZone = stroke.Zone or 0
				end
			end
			if assignedZone >= 0 then
				counts[assignedZone] = (counts[assignedZone] or 0) + 1
			end
			totalCells += 1
			z += ZONE_SAMPLE_CELL
		end
		x += ZONE_SAMPLE_CELL
	end

	local result: { [number]: number } = {}
	for zone = 0, 6 do
		result[zone] = if totalCells > 0 then math.floor((counts[zone] or 0) / totalCells * 1000 + 0.5) / 10 else 0
	end
	return result
end

-- Fire zone area stats to a player's client.
local function fireZoneStats(player: Player, mapData: any)
	local areas = computeZoneAreas(mapData)
	fireEditorEvent(player, "ZoneStats", { areas = areas })
end

-- Compute the % of the map's total area occupied by each zone×resource combination.
-- Key format: "zoneOwner_resourceType" e.g. "1_Wood", "0_Stone".
-- Uses the circle areas of patches (pi*r^2) summed per key vs total map area.
local function computeResourceAreas(mapData: any): { [string]: number }
	local patches = mapData.ResourcePatches or {}
	local mapSize = mapData.Size or 1000
	local totalArea = mapSize * mapSize
	local sums: { [string]: number } = {}
	for _, patch in ipairs(patches) do
		local rType = patch.ResourceType or "Wood"
		local zoneOwner = patch.ZoneOwner or 0
		local key = tostring(zoneOwner) .. "_" .. rType
		local r = math.clamp(patch.Radius or 30, 1, 300)
		local patchArea = math.pi * r * r
		sums[key] = (sums[key] or 0) + patchArea
	end
	local result: { [string]: number } = {}
	for key, area in pairs(sums) do
		result[key] = math.floor(area / totalArea * 1000 + 0.5) / 10  -- % with 1dp
	end
	return result
end

-- Fire resource area stats to a player's client.
local function fireResourceStats(player: Player, mapData: any)
	local areas = computeResourceAreas(mapData)
	fireEditorEvent(player, "ResourceStats", { areas = areas })
end

-- Enter the editor: clear terrain, generate base, set up session
function MapEditorManager.enterEditor(player: Player, mapId: string?)
	local userId = player.UserId
	MapEditorDebug:info(player.Name .. " entering map editor")

	-- Create a default map or load existing
	local MapEditorTypes = require(ReplicatedStorage.Shared.MapEditorTypes)
	local mapData: any

	if mapId then
		-- Load existing map
		local success, result = pcall(function()
			return mapDataStore:GetAsync("CustomMap_" .. userId .. "_" .. mapId)
		end)
		if success and result then
			mapData = HttpService:JSONDecode(result)
			MapEditorDebug:info("Loaded existing map:", mapData.Name)
		else
			MapEditorDebug:warn("Failed to load map, creating new:", mapId)
			mapData = MapEditorTypes.createDefaultMap(userId, player.Name)
		end
	else
		mapData = MapEditorTypes.createDefaultMap(userId, player.Name)
	end

	activeSessions[userId] = mapData
	undoStacks[userId] = {}
	redoStacks[userId] = {}
	undoActionStacks[userId] = {}
	redoActionStacks[userId] = {}

	-- Only clear and regenerate procedural terrain when not using Studio-built terrain
	if not isStudioTerrainMode() then
		local terrain = workspace:WaitForChild("Terrain")
		terrain:Clear()
		MapEditorManager.generateBaseTerrain(terrain, mapData)
	else
		MapEditorDebug:info("Studio terrain mode — skipping terrain clear/generate")
	end

	-- Ensure new fields exist on loaded maps
	if not mapData.ResourcePatches then mapData.ResourcePatches = {} end
	if not mapData.ZonePaintStrokes then mapData.ZonePaintStrokes = {} end

	MapEditorManager.updateResourceVisualization(mapData)
	-- Build zone part overlay folder (parts are hidden until ZonePaint tool is active)
	MapEditorManager.updateZoneVisualization(mapData)

	-- Set player attribute so client controller activates
	player:SetAttribute("MapEditorActive", true)

	-- Notify client that editor is ready
	fireEditorEvent(player, "EditorReady", {
		Name = mapData.Name,
		Size = mapData.Size,
		MaxPlayers = mapData.MaxPlayers,
		ZonePaintStrokes = mapData.ZonePaintStrokes or {},
	})

	-- Send initial zone and resource area stats
	fireZoneStats(player, mapData)
	fireResourceStats(player, mapData)

	MapEditorDebug:info("Editor ready for " .. player.Name)
	return mapData
end

-- Leave the editor: clean up
function MapEditorManager.leaveEditor(player: Player)
	local userId = player.UserId
	MapEditorDebug:info(player.Name .. " leaving map editor")

	activeSessions[userId] = nil
	undoStacks[userId] = nil
	redoStacks[userId] = nil
	undoActionStacks[userId] = nil
	redoActionStacks[userId] = nil
	zoneOverlayActive[userId] = false
	resourceOverlayActive[userId] = false

	-- Only clear terrain when not using Studio-built terrain
	if not isStudioTerrainMode() then
		local terrain = workspace:WaitForChild("Terrain")
		terrain:Clear()
	end

	-- Clean up feature markers
	local featureFolder = workspace:FindFirstChild("MapEditorFeatures")
	if featureFolder then
		featureFolder:Destroy()
	end

	-- Clean up resource patches visualization
	local resourceFolder = workspace:FindFirstChild("MapEditorResources")
	if resourceFolder then
		resourceFolder:Destroy()
	end

	-- Clean up resource model overlay
	local resourceModels = workspace:FindFirstChild("MapEditorResourceModels")
	if resourceModels then
		resourceModels:Destroy()
	end

	-- Clean up zone paint visualization
	local zoneFolder = workspace:FindFirstChild("MapEditorZones")
	if zoneFolder then zoneFolder:Destroy() end
	local zoneBgFolder = workspace:FindFirstChild("MapEditorZonesBg")
	if zoneBgFolder then zoneBgFolder:Destroy() end
	zoneGridCache = {}

	-- Clean up spawn zone discs
	local spawnFolder = workspace:FindFirstChild("MapEditorSpawnZones")
	if spawnFolder then
		spawnFolder:Destroy()
	end

	-- Clear editor attribute
	player:SetAttribute("MapEditorActive", false)
end

-- Generate the base terrain fill
function MapEditorManager.generateBaseTerrain(terrain: any, mapData: any)
	local size = mapData.Size
	local material = Enum.Material[mapData.BaseMaterial] or Enum.Material.Grass
	terrain:FillBlock(CFrame.new(0, -25, 0), Vector3.new(size, 50, size), material)
	MapEditorDebug:info("Base terrain generated:", mapData.BaseMaterial, size)
end

-- Set base terrain material
function MapEditorManager.setBaseTerrain(player: Player, material: string, size: number)
	local userId = player.UserId
	local mapData = activeSessions[userId]
	if not mapData then return end

	mapData.BaseMaterial = material
	mapData.Size = math.clamp(size, 600, 1500)

	-- Studio terrain mode: config values update but terrain is not touched
	if isStudioTerrainMode() then return end

	local terrain = workspace:WaitForChild("Terrain")
	terrain:Clear()
	MapEditorManager.generateBaseTerrain(terrain, mapData)

	-- Replay all brush strokes
	MapEditorManager.replayStrokes(terrain, mapData)

	-- Replay sculpt strokes
	MapEditorManager.replaySculptStrokes(terrain, mapData)

	-- Replay all features
	MapEditorManager.replayFeatures(terrain, mapData)
end

-- Apply brush strokes to terrain
function MapEditorManager.paintTerrain(player: Player, strokes: { any })
	local userId = player.UserId
	local mapData = activeSessions[userId]
	if not mapData then return end

	local terrain = workspace:WaitForChild("Terrain")

	for _, stroke in ipairs(strokes) do
		local pos = Vector3.new(stroke.Position.X, stroke.SizeY / 2, stroke.Position.Z)

		if stroke.Material == "Air" then
			-- Eraser: clear the region
			local region = Region3.new(
				pos - Vector3.new(stroke.Radius, stroke.SizeY / 2, stroke.Radius),
				pos + Vector3.new(stroke.Radius, stroke.SizeY / 2, stroke.Radius)
			)
			-- Align region to terrain grid (4-stud resolution)
			region = region:ExpandToGrid(4)
			local materials, occupancy = terrain:ReadVoxels(region, 4)
			-- Set all occupancy to 0 (air)
			for x = 1, #occupancy do
				for y = 1, #occupancy[x] do
					for z = 1, #occupancy[x][y] do
						occupancy[x][y][z] = 0
					end
				end
			end
			terrain:WriteVoxels(region, 4, materials, occupancy)
		else
			local materialEnum = Enum.Material[stroke.Material]
			if not materialEnum then continue end

			if stroke.Shape == "Ball" then
				terrain:FillBall(pos, stroke.Radius, materialEnum)
			else
				terrain:FillBlock(CFrame.new(pos), Vector3.new(stroke.Radius * 2, stroke.SizeY, stroke.Radius * 2), materialEnum)
			end
		end

		-- Store the stroke
		table.insert(mapData.BrushStrokes, stroke)
	end

	MapEditorDebug:info("Applied " .. #strokes .. " brush strokes for " .. player.Name)
end

-- Brush falloff function: returns 0-1 influence based on distance from center
local function brushFalloff(distance: number, radius: number, hardness: number, shape: string): number
	local normalized = distance / radius
	if normalized > 1 then return 0 end
	-- Soft = Gaussian-like falloff, Hard = flat full influence
	local soft = math.exp(-(normalized * normalized) * 3)
	local hard = 1.0
	return hard * hardness + soft * (1 - hardness)
end

-- Calculate distance from voxel center to stroke center in XZ plane, accounting for brush shape
local function getShapeDistance(voxelX: number, voxelZ: number, centerX: number, centerZ: number, shape: string): number
	local dx = math.abs(voxelX - centerX)
	local dz = math.abs(voxelZ - centerZ)
	if shape == "Square" then
		return math.max(dx, dz) -- Chebyshev distance for square brush
	else
		return math.sqrt(dx * dx + dz * dz) -- Euclidean distance for circle brush
	end
end

-- Find the surface Y index (topmost voxel with occupancy > 0.1) for a given XZ column
local function findSurfaceY(occupancy: any, x: number, z: number): number
	local column = occupancy[x]
	if not column then return 1 end
	local surfaceY = 1
	for y = #column, 1, -1 do
		if column[y] and column[y][z] and column[y][z] > 0.1 then
			surfaceY = y
			break
		end
	end
	return surfaceY
end

-- Apply sculpt strokes to terrain (raise/lower/flatten/paint with occupancy editing)
function MapEditorManager.sculptTerrain(player: Player, strokes: { any })
	local userId = player.UserId
	local mapData = activeSessions[userId]
	if not mapData then return end

	local terrain = workspace:WaitForChild("Terrain") :: Terrain

	for _, stroke in ipairs(strokes) do
		local centerX = stroke.Position.X
		local centerY = stroke.Position.Y
		local centerZ = stroke.Position.Z
		local radius = stroke.Radius or 20
		local strength = math.clamp(stroke.Strength or 0.5, 0.05, 1.0)
		local hardness = math.clamp(stroke.Hardness or 0.5, 0.0, 1.0)
		local mode = stroke.Mode or "Raise"
		local shape = stroke.Shape or "Circle"
		local materialName = stroke.Material or "Grass"
		local materialEnum = Enum.Material[materialName] or Enum.Material.Grass

		-- Build region around stroke: expand in XZ by radius, Y range for sculpting
		local yExpand = radius -- enough vertical room for sculpting
		local regionMin = Vector3.new(centerX - radius, centerY - yExpand, centerZ - radius)
		local regionMax = Vector3.new(centerX + radius, centerY + yExpand, centerZ + radius)
		local region = Region3.new(regionMin, regionMax):ExpandToGrid(4)

		local materials, occupancy = terrain:ReadVoxels(region, 4)

		local sizeX = #materials
		if sizeX == 0 then continue end
		local sizeY = #materials[1]
		if sizeY == 0 then continue end
		local sizeZ = #materials[1][1]
		if sizeZ == 0 then continue end

		-- Region min corner (after grid expansion)
		local regionMinCorner = region.CFrame.Position - region.Size / 2

		if mode == "Raise" then
			-- For each XZ column, find surface and add occupancy above it
			for xi = 1, sizeX do
				for zi = 1, sizeZ do
					local voxelX = regionMinCorner.X + (xi - 0.5) * 4
					local voxelZ = regionMinCorner.Z + (zi - 0.5) * 4
					local dist = getShapeDistance(voxelX, voxelZ, centerX, centerZ, shape)
					local falloff = brushFalloff(dist, radius, hardness, shape)
					if falloff <= 0 then continue end

					local surfaceY = findSurfaceY(occupancy, xi, zi)
					local addAmount = falloff * strength

					-- Fill upward from surface
					local voxelsToAdd = math.ceil(addAmount * 2) -- up to 2 voxels worth at max strength
					for yi = surfaceY, math.min(surfaceY + voxelsToAdd, sizeY) do
						local currentOcc = occupancy[xi][yi][zi]
						local newOcc = math.clamp(currentOcc + addAmount * 0.5, 0, 1)
						occupancy[xi][yi][zi] = newOcc
						if materials[xi][yi][zi] == Enum.Material.Air then
							materials[xi][yi][zi] = materialEnum
						end
					end
				end
			end

		elseif mode == "Lower" then
			-- For each XZ column, find surface and reduce occupancy from top down
			for xi = 1, sizeX do
				for zi = 1, sizeZ do
					local voxelX = regionMinCorner.X + (xi - 0.5) * 4
					local voxelZ = regionMinCorner.Z + (zi - 0.5) * 4
					local dist = getShapeDistance(voxelX, voxelZ, centerX, centerZ, shape)
					local falloff = brushFalloff(dist, radius, hardness, shape)
					if falloff <= 0 then continue end

					local surfaceY = findSurfaceY(occupancy, xi, zi)
					local removeAmount = falloff * strength

					-- Remove from surface downward
					local voxelsToRemove = math.ceil(removeAmount * 2)
					for yi = surfaceY, math.max(surfaceY - voxelsToRemove, 1), -1 do
						local currentOcc = occupancy[xi][yi][zi]
						local newOcc = math.clamp(currentOcc - removeAmount * 0.5, 0, 1)
						occupancy[xi][yi][zi] = newOcc
						if newOcc <= 0 then
							materials[xi][yi][zi] = Enum.Material.Air
						end
					end
				end
			end

		elseif mode == "Flatten" then
			-- First pass: find average surface height in brush area
			local totalHeight = 0
			local count = 0
			for xi = 1, sizeX do
				for zi = 1, sizeZ do
					local voxelX = regionMinCorner.X + (xi - 0.5) * 4
					local voxelZ = regionMinCorner.Z + (zi - 0.5) * 4
					local dist = getShapeDistance(voxelX, voxelZ, centerX, centerZ, shape)
					if dist <= radius then
						local surfaceY = findSurfaceY(occupancy, xi, zi)
						totalHeight = totalHeight + surfaceY
						count = count + 1
					end
				end
			end
			local targetY = count > 0 and math.floor(totalHeight / count + 0.5) or 1

			-- Second pass: move terrain toward target height
			for xi = 1, sizeX do
				for zi = 1, sizeZ do
					local voxelX = regionMinCorner.X + (xi - 0.5) * 4
					local voxelZ = regionMinCorner.Z + (zi - 0.5) * 4
					local dist = getShapeDistance(voxelX, voxelZ, centerX, centerZ, shape)
					local falloff = brushFalloff(dist, radius, hardness, shape)
					if falloff <= 0 then continue end

					local surfaceY = findSurfaceY(occupancy, xi, zi)
					local moveStrength = falloff * strength * 0.5

					if surfaceY < targetY then
						-- Need to raise: add occupancy above current surface up to target
						for yi = surfaceY, math.min(targetY, sizeY) do
							local currentOcc = occupancy[xi][yi][zi]
							occupancy[xi][yi][zi] = math.clamp(currentOcc + moveStrength, 0, 1)
							if materials[xi][yi][zi] == Enum.Material.Air then
								materials[xi][yi][zi] = materialEnum
							end
						end
					elseif surfaceY > targetY then
						-- Need to lower: remove occupancy above target
						for yi = surfaceY, math.max(targetY + 1, 1), -1 do
							local currentOcc = occupancy[xi][yi][zi]
							occupancy[xi][yi][zi] = math.clamp(currentOcc - moveStrength, 0, 1)
							if occupancy[xi][yi][zi] <= 0 then
								materials[xi][yi][zi] = Enum.Material.Air
							end
						end
					end
				end
			end

		elseif mode == "Paint" then
			-- Only change material of existing occupied voxels
			for xi = 1, sizeX do
				for zi = 1, sizeZ do
					local voxelX = regionMinCorner.X + (xi - 0.5) * 4
					local voxelZ = regionMinCorner.Z + (zi - 0.5) * 4
					local dist = getShapeDistance(voxelX, voxelZ, centerX, centerZ, shape)
					if dist > radius then continue end

					for yi = 1, sizeY do
						if occupancy[xi][yi][zi] > 0.1 then
							materials[xi][yi][zi] = materialEnum
						end
					end
				end
			end
		end

		terrain:WriteVoxels(region, 4, materials, occupancy)

		-- Store the stroke in map data
		if not mapData.SculptStrokes then
			mapData.SculptStrokes = {}
		end
		table.insert(mapData.SculptStrokes, stroke)
		-- Push to unified action stack; new action invalidates redo history
		if not undoActionStacks[userId] then undoActionStacks[userId] = {} end
		table.insert(undoActionStacks[userId], { type = "SculptStroke", count = 1 })
		redoStacks[userId] = {}
		redoActionStacks[userId] = {}
	end

	MapEditorDebug:info("Applied " .. #strokes .. " sculpt strokes for " .. player.Name)
end

-- Replay all sculpt strokes from map data (used during regenerateAll)
function MapEditorManager.replaySculptStrokes(terrain: any, mapData: any)
	if not mapData.SculptStrokes then return end

	local tempPlayer = { UserId = mapData.AuthorId } :: any
	-- Temporarily set the session so sculptTerrain can find it
	local previousSession = activeSessions[mapData.AuthorId]
	activeSessions[mapData.AuthorId] = mapData

	-- Replay in batches to avoid overwhelming
	for _, stroke in ipairs(mapData.SculptStrokes) do
		-- Directly apply each stroke without re-storing
		local centerX = stroke.Position.X
		local centerY = stroke.Position.Y
		local centerZ = stroke.Position.Z
		local radius = stroke.Radius or 20
		local strength = math.clamp(stroke.Strength or 0.5, 0.05, 1.0)
		local hardness = math.clamp(stroke.Hardness or 0.5, 0.0, 1.0)
		local mode = stroke.Mode or "Raise"
		local shape = stroke.Shape or "Circle"
		local materialName = stroke.Material or "Grass"
		local materialEnum = Enum.Material[materialName] or Enum.Material.Grass

		local yExpand = radius
		local regionMin = Vector3.new(centerX - radius, centerY - yExpand, centerZ - radius)
		local regionMax = Vector3.new(centerX + radius, centerY + yExpand, centerZ + radius)
		local region = Region3.new(regionMin, regionMax):ExpandToGrid(4)

		local materials, occupancy = terrain:ReadVoxels(region, 4)

		local sizeX = #materials
		if sizeX == 0 then continue end
		local sizeY = #materials[1]
		if sizeY == 0 then continue end
		local sizeZ = #materials[1][1]
		if sizeZ == 0 then continue end

		local regionMinCorner = region.CFrame.Position - region.Size / 2

		if mode == "Raise" then
			for xi = 1, sizeX do
				for zi = 1, sizeZ do
					local voxelX = regionMinCorner.X + (xi - 0.5) * 4
					local voxelZ = regionMinCorner.Z + (zi - 0.5) * 4
					local dist = getShapeDistance(voxelX, voxelZ, centerX, centerZ, shape)
					local falloff = brushFalloff(dist, radius, hardness, shape)
					if falloff <= 0 then continue end
					local surfaceY = findSurfaceY(occupancy, xi, zi)
					local addAmount = falloff * strength
					local voxelsToAdd = math.ceil(addAmount * 2)
					for yi = surfaceY, math.min(surfaceY + voxelsToAdd, sizeY) do
						occupancy[xi][yi][zi] = math.clamp(occupancy[xi][yi][zi] + addAmount * 0.5, 0, 1)
						if materials[xi][yi][zi] == Enum.Material.Air then
							materials[xi][yi][zi] = materialEnum
						end
					end
				end
			end
		elseif mode == "Lower" then
			for xi = 1, sizeX do
				for zi = 1, sizeZ do
					local voxelX = regionMinCorner.X + (xi - 0.5) * 4
					local voxelZ = regionMinCorner.Z + (zi - 0.5) * 4
					local dist = getShapeDistance(voxelX, voxelZ, centerX, centerZ, shape)
					local falloff = brushFalloff(dist, radius, hardness, shape)
					if falloff <= 0 then continue end
					local surfaceY = findSurfaceY(occupancy, xi, zi)
					local removeAmount = falloff * strength
					local voxelsToRemove = math.ceil(removeAmount * 2)
					for yi = surfaceY, math.max(surfaceY - voxelsToRemove, 1), -1 do
						occupancy[xi][yi][zi] = math.clamp(occupancy[xi][yi][zi] - removeAmount * 0.5, 0, 1)
						if occupancy[xi][yi][zi] <= 0 then
							materials[xi][yi][zi] = Enum.Material.Air
						end
					end
				end
			end
		elseif mode == "Flatten" then
			local totalHeight, count = 0, 0
			for xi = 1, sizeX do
				for zi = 1, sizeZ do
					local voxelX = regionMinCorner.X + (xi - 0.5) * 4
					local voxelZ = regionMinCorner.Z + (zi - 0.5) * 4
					if getShapeDistance(voxelX, voxelZ, centerX, centerZ, shape) <= radius then
						totalHeight = totalHeight + findSurfaceY(occupancy, xi, zi)
						count = count + 1
					end
				end
			end
			local targetY = count > 0 and math.floor(totalHeight / count + 0.5) or 1
			for xi = 1, sizeX do
				for zi = 1, sizeZ do
					local voxelX = regionMinCorner.X + (xi - 0.5) * 4
					local voxelZ = regionMinCorner.Z + (zi - 0.5) * 4
					local dist = getShapeDistance(voxelX, voxelZ, centerX, centerZ, shape)
					local falloff = brushFalloff(dist, radius, hardness, shape)
					if falloff <= 0 then continue end
					local surfaceY = findSurfaceY(occupancy, xi, zi)
					local moveStrength = falloff * strength * 0.5
					if surfaceY < targetY then
						for yi = surfaceY, math.min(targetY, sizeY) do
							occupancy[xi][yi][zi] = math.clamp(occupancy[xi][yi][zi] + moveStrength, 0, 1)
							if materials[xi][yi][zi] == Enum.Material.Air then
								materials[xi][yi][zi] = materialEnum
							end
						end
					elseif surfaceY > targetY then
						for yi = surfaceY, math.max(targetY + 1, 1), -1 do
							occupancy[xi][yi][zi] = math.clamp(occupancy[xi][yi][zi] - moveStrength, 0, 1)
							if occupancy[xi][yi][zi] <= 0 then
								materials[xi][yi][zi] = Enum.Material.Air
							end
						end
					end
				end
			end
		elseif mode == "Paint" then
			for xi = 1, sizeX do
				for zi = 1, sizeZ do
					local voxelX = regionMinCorner.X + (xi - 0.5) * 4
					local voxelZ = regionMinCorner.Z + (zi - 0.5) * 4
					if getShapeDistance(voxelX, voxelZ, centerX, centerZ, shape) > radius then continue end
					for yi = 1, sizeY do
						if occupancy[xi][yi][zi] > 0.1 then
							materials[xi][yi][zi] = materialEnum
						end
					end
				end
			end
		end

		terrain:WriteVoxels(region, 4, materials, occupancy)
	end

	-- Restore previous session state
	activeSessions[mapData.AuthorId] = previousSession
end

-- Replay all brush strokes from map data
function MapEditorManager.replayStrokes(terrain: any, mapData: any)
	for _, stroke in ipairs(mapData.BrushStrokes) do
		local pos = Vector3.new(stroke.Position.X, stroke.SizeY / 2, stroke.Position.Z)

		if stroke.Material == "Air" then
			local region = Region3.new(
				pos - Vector3.new(stroke.Radius, stroke.SizeY / 2, stroke.Radius),
				pos + Vector3.new(stroke.Radius, stroke.SizeY / 2, stroke.Radius)
			)
			region = region:ExpandToGrid(4)
			local materials, occupancy = terrain:ReadVoxels(region, 4)
			for x = 1, #occupancy do
				for y = 1, #occupancy[x] do
					for z = 1, #occupancy[x][y] do
						occupancy[x][y][z] = 0
					end
				end
			end
			terrain:WriteVoxels(region, 4, materials, occupancy)
		else
			local materialEnum = Enum.Material[stroke.Material]
			if not materialEnum then continue end

			if stroke.Shape == "Ball" then
				terrain:FillBall(pos, stroke.Radius, materialEnum)
			else
				terrain:FillBlock(CFrame.new(pos), Vector3.new(stroke.Radius * 2, stroke.SizeY, stroke.Radius * 2), materialEnum)
			end
		end
	end
end

-- Place a terrain feature
function MapEditorManager.placeFeature(player: Player, feature: any)
	local userId = player.UserId
	local mapData = activeSessions[userId]
	if not mapData then return end

	-- Generate unique ID if not provided
	if not feature.Id or feature.Id == "" then
		feature.Id = HttpService:GenerateGUID(false)
	end

	table.insert(mapData.Features, feature)

	-- Generate the feature terrain
	local terrain = workspace:WaitForChild("Terrain")
	MapEditorManager.generateFeature(terrain, feature)

	-- Add a marker billboard
	MapEditorManager.createFeatureMarker(feature)

	MapEditorDebug:info("Placed feature:", feature.FeatureType, "at", feature.Position.X, feature.Position.Z)
	return feature.Id
end

-- Generate terrain for a single feature
function MapEditorManager.generateFeature(terrain: any, feature: any)
	local pos = Vector3.new(feature.Position.X, feature.Position.Y or 0, feature.Position.Z)
	local scale = feature.Scale or 1

	if feature.FeatureType == "Mountain" then
		local radius = 120 * scale
		local height = 100 * scale
		terrain:FillBall(pos + Vector3.new(0, height / 2, 0), radius, Enum.Material.Rock)
		terrain:FillBall(pos + Vector3.new(0, height / 2 + 20 * scale, 0), radius * 0.8, Enum.Material.Grass)
		terrain:FillBall(pos + Vector3.new(0, height / 2 + 40 * scale, 0), radius * 0.4, Enum.Material.Snow)
	elseif feature.FeatureType == "Lake" then
		local radius = 80 * scale
		terrain:FillBall(pos + Vector3.new(0, 2, 0), radius * 1.3, Enum.Material.Sand)
		terrain:FillBall(pos, radius, Enum.Material.Water)
	elseif feature.FeatureType == "River" then
		local length = 200 * scale
		local width = 40 * scale
		local rotation = feature.Rotation or 0
		local riverCFrame = CFrame.new(pos + Vector3.new(0, 3, 0)) * CFrame.Angles(0, math.rad(rotation), 0)
		terrain:FillBlock(riverCFrame, Vector3.new(length, 12, width), Enum.Material.Water)
	elseif feature.FeatureType == "Forest" then
		local radius = 50 * scale
		terrain:FillBall(pos + Vector3.new(0, 3, 0), radius, Enum.Material.LeafyGrass)
	elseif feature.FeatureType == "Hill" then
		local radius = 60 * scale
		local height = 30 * scale
		terrain:FillBall(pos + Vector3.new(0, height / 2, 0), radius, Enum.Material.Grass)
	elseif feature.FeatureType == "Rock" then
		local radius = 30 * scale
		terrain:FillBall(pos + Vector3.new(0, radius / 2, 0), radius, Enum.Material.Rock)
	end
end

-- Create a billboard marker for a feature in the 3D world
function MapEditorManager.createFeatureMarker(feature: any)
	local folder = workspace:FindFirstChild("MapEditorFeatures")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "MapEditorFeatures"
		folder.Parent = workspace
	end

	local marker = Instance.new("Part")
	marker.Name = "Feature_" .. feature.Id
	marker.Size = Vector3.new(2, 2, 2)
	marker.Position = Vector3.new(feature.Position.X, (feature.Position.Y or 0) + 30, feature.Position.Z)
	marker.Anchored = true
	marker.CanCollide = false
	marker.Transparency = 0.5
	marker.Color = Color3.fromRGB(255, 200, 50)
	marker.Shape = Enum.PartType.Ball
	marker.Parent = folder

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(0, 60, 0, 30)
	billboard.StudsOffset = Vector3.new(0, 3, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = marker

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(30, 25, 20)
	label.BackgroundTransparency = 0.3
	label.Text = feature.FeatureType
	label.TextColor3 = Color3.fromRGB(255, 220, 100)
	label.TextSize = 12
	label.Font = Enum.Font.GothamBold
	label.Parent = billboard

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = label
end

-- Delete a feature
function MapEditorManager.deleteFeature(player: Player, featureId: string)
	local userId = player.UserId
	local mapData = activeSessions[userId]
	if not mapData then return end

	-- Remove from data
	for i, feature in ipairs(mapData.Features) do
		if feature.Id == featureId then
			table.remove(mapData.Features, i)
			break
		end
	end

	-- Remove marker
	local folder = workspace:FindFirstChild("MapEditorFeatures")
	if folder then
		local marker = folder:FindFirstChild("Feature_" .. featureId)
		if marker then
			marker:Destroy()
		end
	end

	-- Regenerate entire terrain from history
	MapEditorManager.regenerateAll(player)

	MapEditorDebug:info("Deleted feature:", featureId)
end

-- Move a feature
function MapEditorManager.moveFeature(player: Player, featureId: string, newPosition: any)
	local userId = player.UserId
	local mapData = activeSessions[userId]
	if not mapData then return end

	for _, feature in ipairs(mapData.Features) do
		if feature.Id == featureId then
			feature.Position = newPosition
			break
		end
	end

	-- Regenerate terrain
	MapEditorManager.regenerateAll(player)
end

-- Regenerate all terrain from stored data
function MapEditorManager.regenerateAll(player: Player)
	local userId = player.UserId
	local mapData = activeSessions[userId]
	if not mapData then return end

	-- In Studio terrain mode, skip all terrain clear/regeneration — the Studio-built
	-- terrain is the source of truth and must not be overwritten.
	if not isStudioTerrainMode() then
		local terrain = workspace:WaitForChild("Terrain")
		terrain:Clear()

		-- Base terrain
		MapEditorManager.generateBaseTerrain(terrain, mapData)

		-- Replay strokes
		MapEditorManager.replayStrokes(terrain, mapData)

		-- Replay sculpt strokes
		MapEditorManager.replaySculptStrokes(terrain, mapData)

		-- Replay features
		MapEditorManager.replayFeatures(terrain, mapData)
	end

	-- If resource overlay is NOT active, show the flat disc visualization.
	-- If it IS active, the overlay will be re-shown by the caller (e.g. hideResourceOverlay
	-- destroys models first, then calls us; showResourceOverlay is responsible for re-showing).
	if not resourceOverlayActive[userId] then
		MapEditorManager.updateResourceVisualization(mapData)
	end

	MapEditorDebug:info("Regenerated all terrain for " .. player.Name)
end

-- Replay all features
function MapEditorManager.replayFeatures(terrain: any, mapData: any)
	-- Clear old markers
	local folder = workspace:FindFirstChild("MapEditorFeatures")
	if folder then
		folder:ClearAllChildren()
	end

	for _, feature in ipairs(mapData.Features) do
		MapEditorManager.generateFeature(terrain, feature)
		MapEditorManager.createFeatureMarker(feature)
	end
end

-- Update map settings (name, description, size, etc.)
function MapEditorManager.updateMapSettings(player: Player, settings: any)
	local userId = player.UserId
	local mapData = activeSessions[userId]
	if not mapData then return end

	if settings.name then mapData.Name = settings.name end
	if settings.description then mapData.Description = settings.description end
	if settings.maxPlayers then mapData.MaxPlayers = settings.maxPlayers end
	if settings.neutralZoneWidth then mapData.NeutralZoneWidth = settings.neutralZoneWidth end
	if settings.resourceDensity then mapData.ResourceDensity = settings.resourceDensity end

	if settings.size then
		local newSize = math.clamp(settings.size, 600, 1500)
		if newSize ~= mapData.Size then
			mapData.Size = newSize
			MapEditorManager.regenerateAll(player)
		end
	end

	mapData.UpdatedAt = os.time()
end

-- Save map to DataStore
function MapEditorManager.saveMap(player: Player)
	local userId = player.UserId
	local mapData = activeSessions[userId]
	if not mapData then
		fireEditorEvent(player, "MapSaved", { success = false, error = "No active editor session" })
		return
	end

	mapData.UpdatedAt = os.time()

	local key = "CustomMap_" .. userId .. "_" .. mapData.MapId
	local success, err = pcall(function()
		mapDataStore:SetAsync(key, HttpService:JSONEncode(mapData))
	end)

	if not success then
		MapEditorDebug:warn("Failed to save map:", err)
		fireEditorEvent(player, "MapSaved", { success = false, error = tostring(err) })
		return
	end

	-- Update player's map index
	local indexKey = "MapIndex_" .. userId
	pcall(function()
		local index = mapDataStore:GetAsync(indexKey)
		local mapIndex = index and HttpService:JSONDecode(index) or {}

		-- Update or add entry
		local found = false
		for i, entry in ipairs(mapIndex) do
			if entry.MapId == mapData.MapId then
				mapIndex[i] = { MapId = mapData.MapId, Name = mapData.Name, UpdatedAt = mapData.UpdatedAt }
				found = true
				break
			end
		end
		if not found then
			table.insert(mapIndex, { MapId = mapData.MapId, Name = mapData.Name, UpdatedAt = mapData.UpdatedAt })
		end

		mapDataStore:SetAsync(indexKey, HttpService:JSONEncode(mapIndex))
	end)

	MapEditorDebug:info("Map saved:", mapData.Name, key)
	fireEditorEvent(player, "MapSaved", { success = true, mapId = mapData.MapId })
end

-- List player's saved maps
function MapEditorManager.listMaps(player: Player)
	local userId = player.UserId
	local indexKey = "MapIndex_" .. userId

	local success, result = pcall(function()
		return mapDataStore:GetAsync(indexKey)
	end)

	local maps = {}
	if success and result then
		maps = HttpService:JSONDecode(result)
	end

	fireEditorEvent(player, "MapList", { maps = maps })
end

-- Return player's saved map index as a plain table (used by lobby, not the editor).
function MapEditorManager.getUserMaps(player: Player): { any }
	local userId = player.UserId
	local indexKey = "MapIndex_" .. userId
	local success, result = pcall(function()
		return mapDataStore:GetAsync(indexKey)
	end)
	if success and result then
		return HttpService:JSONDecode(result)
	end
	return {}
end

-- Rename a saved map in DataStore (updates both the full map entry and the index)
function MapEditorManager.renameMap(player: Player, data: any)
	local userId = player.UserId
	local mapId: string = data.mapId or ""
	local newName: string = data.name or ""
	if mapId == "" or newName == "" then return end

	local key = "CustomMap_" .. userId .. "_" .. mapId
	local indexKey = "MapIndex_" .. userId

	-- Update full map entry
	local ok1, result = pcall(function()
		return mapDataStore:GetAsync(key)
	end)
	if ok1 and result then
		local mapData = HttpService:JSONDecode(result)
		mapData.Name = newName
		mapData.UpdatedAt = os.time()
		pcall(function()
			mapDataStore:SetAsync(key, HttpService:JSONEncode(mapData))
		end)
	end

	-- Update the index entry
	local ok2, indexResult = pcall(function()
		return mapDataStore:GetAsync(indexKey)
	end)
	if ok2 and indexResult then
		local index = HttpService:JSONDecode(indexResult)
		for _, entry in ipairs(index) do
			if entry.MapId == mapId then
				entry.Name = newName
				entry.UpdatedAt = os.time()
				break
			end
		end
		pcall(function()
			mapDataStore:SetAsync(indexKey, HttpService:JSONEncode(index))
		end)
	end
end

-- Delete a saved map from DataStore
function MapEditorManager.deleteMap(player: Player, mapId: string)
	if mapId == "" then return end
	local userId = player.UserId
	local key = "CustomMap_" .. userId .. "_" .. mapId
	local indexKey = "MapIndex_" .. userId

	-- Remove the full map entry
	pcall(function()
		mapDataStore:RemoveAsync(key)
	end)

	-- Remove from index
	local ok, indexResult = pcall(function()
		return mapDataStore:GetAsync(indexKey)
	end)
	if ok and indexResult then
		local index = HttpService:JSONDecode(indexResult)
		local newIndex = {}
		for _, entry in ipairs(index) do
			if entry.MapId ~= mapId then
				table.insert(newIndex, entry)
			end
		end
		pcall(function()
			mapDataStore:SetAsync(indexKey, HttpService:JSONEncode(newIndex))
		end)
	end
end

-- Load a map from DataStore
function MapEditorManager.loadMap(player: Player, mapId: string)
	local userId = player.UserId
	local key = "CustomMap_" .. userId .. "_" .. mapId

	local success, result = pcall(function()
		return mapDataStore:GetAsync(key)
	end)

	if success and result then
		local loadedData = HttpService:JSONDecode(result)
		activeSessions[userId] = loadedData

		-- Ensure new fields exist on legacy saves
		if not loadedData.ResourcePatches then loadedData.ResourcePatches = {} end
		if not loadedData.ZonePaintStrokes then loadedData.ZonePaintStrokes = {} end

		-- Regenerate terrain from loaded data (skip in Studio terrain mode)
		if not isStudioTerrainMode() then
			local terrain = workspace:WaitForChild("Terrain")
			terrain:Clear()
			MapEditorManager.generateBaseTerrain(terrain, loadedData)
			MapEditorManager.replayStrokes(terrain, loadedData)
			MapEditorManager.replaySculptStrokes(terrain, loadedData)
			MapEditorManager.replayFeatures(terrain, loadedData)
		end
		MapEditorManager.updateResourceVisualization(loadedData)
		-- Rebuild zone part folder so the overlay is ready when ZonePaint tool activates
		MapEditorManager.updateZoneVisualization(loadedData)

		fireEditorEvent(player, "MapLoaded", {
			Name = loadedData.Name,
			Size = loadedData.Size,
			MaxPlayers = loadedData.MaxPlayers,
			ZonePaintStrokes = loadedData.ZonePaintStrokes or {},
		})
		-- Send zone and resource area stats for the loaded map
		fireZoneStats(player, loadedData)
		fireResourceStats(player, loadedData)
		MapEditorDebug:info("Loaded map:", loadedData.Name)
		return
	end

	MapEditorDebug:warn("Failed to load map:", mapId)
end

-- Export map as two Lua code strings for shipping as a built-in map.
-- Fires ExportResult with:
--   mapConfigCode  → paste this block into MapData.luau inside MapData.Maps = { ... }
--   dataModuleCode → save as src/shared/GameData/BuiltinMapData/<YourKey>.luau
function MapEditorManager.exportMap(player: Player)
	local userId = player.UserId
	local mapData = activeSessions[userId]
	if not mapData then return end

	local keepSpawnZones = mapData.KeepSpawnZones or {}
	local base = mapData.PreviewColors and mapData.PreviewColors.Base or { 100, 160, 100 }
	local quadrantSize = mapData.SpawnZones and mapData.SpawnZones[1] and mapData.SpawnZones[1].HalfSize * 2 or 400

	-- ── 1. MapConfig block (paste into MapData.luau) ────────────────────────
	local cfg = {}
	table.insert(cfg, '-- Paste this block inside MapData.Maps = { ... } in MapData.luau')
	table.insert(cfg, '-- Replace "YourMapKey" with a short identifier (no spaces)')
	table.insert(cfg, '["YourMapKey"] = {')
	table.insert(cfg, '\tName = "' .. (mapData.Name or "Untitled") .. '",')
	table.insert(cfg, '\tDescription = "' .. (mapData.Description or "") .. '",')
	table.insert(cfg, '\tSize = ' .. mapData.Size .. ',')
	table.insert(cfg, '\tTerrainType = "Custom",')
	table.insert(cfg, '\tMaxPlayers = ' .. mapData.MaxPlayers .. ',')
	table.insert(cfg, '\tQuadrantSize = ' .. quadrantSize .. ',')
	table.insert(cfg, '\tNeutralZoneWidth = ' .. mapData.NeutralZoneWidth .. ',')
	table.insert(cfg, '\tSpawnHeight = ' .. mapData.SpawnHeight .. ',')
	table.insert(cfg, '\tResourceDensity = {')
	table.insert(cfg, '\t\tWood = ' .. mapData.ResourceDensity.Wood .. ',')
	table.insert(cfg, '\t\tStone = ' .. mapData.ResourceDensity.Stone .. ',')
	table.insert(cfg, '\t\tFood = ' .. mapData.ResourceDensity.Food .. ',')
	table.insert(cfg, '\t\tIron_Ore = ' .. mapData.ResourceDensity.Iron_Ore .. ',')
	table.insert(cfg, '\t},')
	table.insert(cfg, '\tFeatures = {')
	table.insert(cfg, '\t\tHasCentralLake = false,')
	table.insert(cfg, '\t\tHasMountains = false,')
	table.insert(cfg, '\t\tHasForests = false,')
	table.insert(cfg, '\t\tHasRivers = false,')
	table.insert(cfg, '\t},')
	table.insert(cfg, '\tPreviewColors = {')
	table.insert(cfg, '\t\tBase = { ' .. base[1] .. ', ' .. base[2] .. ', ' .. base[3] .. ' },')
	table.insert(cfg, '\t},')
	if #keepSpawnZones > 0 then
		table.insert(cfg, '\tKeepSpawnZones = {')
		for _, zone in ipairs(keepSpawnZones) do
			table.insert(cfg, string.format(
				'\t\t{ Zone = %d, X = %.1f, Y = %.1f, Z = %.1f, Radius = %.1f },',
				zone.Zone or 1, zone.X or 0, zone.Y or 0, zone.Z or 0, zone.Radius or 150
			))
		end
		table.insert(cfg, '\t},')
	end
	table.insert(cfg, '} :: MapConfig,')

	-- ── 2. Data module (save as BuiltinMapData/YourMapKey.luau) ─────────────
	local dat = {}
	table.insert(dat, '-- Save as src/shared/GameData/BuiltinMapData/YourMapKey.luau')
	table.insert(dat, '-- (use the same key you chose in MapData.luau)')
	table.insert(dat, 'return {')

	-- KeepSpawnZones
	table.insert(dat, '\tKeepSpawnZones = {')
	for _, zone in ipairs(keepSpawnZones) do
		table.insert(dat, string.format(
			'\t\t{ Zone = %d, X = %.1f, Y = %.1f, Z = %.1f, Radius = %.1f },',
			zone.Zone or 1, zone.X or 0, zone.Y or 0, zone.Z or 0, zone.Radius or 150
		))
	end
	table.insert(dat, '\t},')

	-- ResourcePatches
	local patches = mapData.ResourcePatches or {}
	table.insert(dat, '\tResourcePatches = {')
	for _, patch in ipairs(patches) do
		local pos = patch.Position or {}
		table.insert(dat, string.format(
			'\t\t{ Id = "%s", ResourceType = "%s", ZoneOwner = %d, Position = { X = %.1f, Z = %.1f }, Radius = %.1f, Density = %d },',
			patch.Id or "", patch.ResourceType or "Wood", patch.ZoneOwner or 0,
			pos.X or 0, pos.Z or 0, patch.Radius or 30, patch.Density or 5
		))
	end
	table.insert(dat, '\t},')

	-- ZonePaintStrokes
	local strokes = mapData.ZonePaintStrokes or {}
	table.insert(dat, '\tZonePaintStrokes = {')
	for _, stroke in ipairs(strokes) do
		local spos = stroke.Position or {}
		table.insert(dat, string.format(
			'\t\t{ Zone = %d, Position = { X = %.1f, Z = %.1f }, Radius = %.1f, Shape = "%s" },',
			stroke.Zone or 0, spos.X or 0, spos.Z or 0,
			stroke.Radius or 40, stroke.Shape or "Circle"
		))
	end
	table.insert(dat, '\t},')

	table.insert(dat, '}')

	local mapConfigCode = table.concat(cfg, "\n")
	local dataModuleCode = table.concat(dat, "\n")

	-- Print to server output (Studio) — no truncation, easy to copy
	print("\n=== STEP 1: Paste into MapData.luau inside MapData.Maps = { ... } ===")
	print(mapConfigCode)
	print("=== END STEP 1 ===\n")
	print("=== STEP 2: Save as src/shared/GameData/BuiltinMapData/YourMapKey.luau ===")
	print(dataModuleCode)
	print("=== END STEP 2 ===\n")

	-- Fire to client so the UI shows a confirmation (no large payload needed)
	fireEditorEvent(player, "ExportResult", {
		mapConfigCode = mapConfigCode,
		dataModuleCode = dataModuleCode,
	})
end

-- Unified undo: pops the last action (SculptStroke, ZonePaint, or ResourcePatch).
function MapEditorManager.undoStroke(player: Player)
	local userId = player.UserId
	local mapData = activeSessions[userId]
	if not mapData then return end

	local actionStack = undoActionStacks[userId]
	if not actionStack or #actionStack == 0 then
		MapEditorDebug:info("Nothing to undo for " .. player.Name)
		return
	end

	local action = table.remove(actionStack) -- pop last
	if not redoActionStacks[userId] then redoActionStacks[userId] = {} end

	if action.type == "SculptStroke" then
		-- Pop the last N sculpt strokes and store for redo
		local removed: { any } = {}
		for _ = 1, action.count do
			local s = table.remove(mapData.SculptStrokes)
			if s then table.insert(removed, 1, s) end
		end
		table.insert(redoActionStacks[userId], { type = "SculptStroke", count = #removed, data = removed })
		MapEditorManager.regenerateAll(player)

	elseif action.type == "ZonePaint" then
		-- Pop the last N zone strokes and store for redo
		local strokes = mapData.ZonePaintStrokes or {}
		local removed: { any } = {}
		for _ = 1, action.count do
			local s = table.remove(strokes)
			if s then table.insert(removed, 1, s) end
		end
		mapData.ZonePaintStrokes = strokes
		table.insert(redoActionStacks[userId], { type = "ZonePaint", count = #removed, data = removed })
		MapEditorManager.updateZoneVisualization(mapData)
		if zoneOverlayActive[userId] then
			MapEditorManager.setZoneOverlayVisible(player, true)
		end
		fireZoneStats(player, mapData)

	elseif action.type == "ResourcePatch" then
		-- Pop the last N resource patches and store for redo
		local patches = mapData.ResourcePatches or {}
		local removed: { any } = {}
		for _ = 1, action.count do
			local p = table.remove(patches)
			if p then table.insert(removed, 1, p) end
		end
		mapData.ResourcePatches = patches
		table.insert(redoActionStacks[userId], { type = "ResourcePatch", count = #removed, data = removed })
		MapEditorManager.updateResourceVisualization(mapData)
		fireResourceStats(player, mapData)
	end

	MapEditorDebug:info("Undo (" .. action.type .. ") for " .. player.Name)
end

-- Unified redo: re-applies the last undone action.
function MapEditorManager.redoStroke(player: Player)
	local userId = player.UserId
	local mapData = activeSessions[userId]
	if not mapData then return end

	local redoStack = redoActionStacks[userId]
	if not redoStack or #redoStack == 0 then
		MapEditorDebug:info("Nothing to redo for " .. player.Name)
		return
	end

	local action = table.remove(redoStack) -- pop last
	if not undoActionStacks[userId] then undoActionStacks[userId] = {} end

	if action.type == "SculptStroke" then
		local strokes = action.data or {}
		if not mapData.SculptStrokes then mapData.SculptStrokes = {} end
		for _, s in ipairs(strokes) do
			table.insert(mapData.SculptStrokes, s)
		end
		table.insert(undoActionStacks[userId], { type = "SculptStroke", count = #strokes })
		MapEditorManager.regenerateAll(player)

	elseif action.type == "ZonePaint" then
		local strokes = action.data or {}
		if not mapData.ZonePaintStrokes then mapData.ZonePaintStrokes = {} end
		for _, s in ipairs(strokes) do
			table.insert(mapData.ZonePaintStrokes, s)
		end
		table.insert(undoActionStacks[userId], { type = "ZonePaint", count = #strokes })
		MapEditorManager.updateZoneVisualization(mapData)
		if zoneOverlayActive[userId] then
			MapEditorManager.setZoneOverlayVisible(player, true)
		end
		fireZoneStats(player, mapData)

	elseif action.type == "ResourcePatch" then
		local patches = action.data or {}
		if not mapData.ResourcePatches then mapData.ResourcePatches = {} end
		for _, p in ipairs(patches) do
			table.insert(mapData.ResourcePatches, p)
		end
		table.insert(undoActionStacks[userId], { type = "ResourcePatch", count = #patches })
		MapEditorManager.updateResourceVisualization(mapData)
		fireResourceStats(player, mapData)
	end

	MapEditorDebug:info("Redo (" .. action.type .. ") for " .. player.Name)
end

-- Resource patch colors for visualization
local RESOURCE_VIZ_COLORS: { [string]: Color3 } = {
	Wood     = Color3.fromRGB(60, 140, 40),
	Stone    = Color3.fromRGB(160, 155, 150),
	Food     = Color3.fromRGB(200, 180, 50),
	Iron_Ore = Color3.fromRGB(110, 80, 70),
}

-- Zone paint colors for visualization
local ZONE_VIZ_COLORS: { [number]: Color3 } = {
	[0] = Color3.fromRGB(140, 120, 80),  -- Neutral
	[1] = Color3.fromRGB(80, 120, 200),  -- Player 1
	[2] = Color3.fromRGB(200, 80, 80),   -- Player 2
	[3] = Color3.fromRGB(80, 180, 80),   -- Player 3
	[4] = Color3.fromRGB(200, 160, 40),  -- Player 4
	[5] = Color3.fromRGB(60, 55, 65),    -- Impassable (dark slate)
	[6] = Color3.fromRGB(190, 110, 40),  -- No Build (amber)
}

-- Create/refresh resource patch visualization folder
function MapEditorManager.updateResourceVisualization(mapData: any)
	local folder = workspace:FindFirstChild("MapEditorResources")
	if folder then
		folder:ClearAllChildren()
	else
		folder = Instance.new("Folder")
		folder.Name = "MapEditorResources"
		folder.Parent = workspace
	end

	if not mapData.ResourcePatches then return end

	local resTerrain = workspace:FindFirstChildOfClass("Terrain")
	local resRayParams = RaycastParams.new()
	resRayParams.FilterType = Enum.RaycastFilterType.Include
	if resTerrain then
		resRayParams.FilterDescendantsInstances = { resTerrain }
	end

	for _, patch in ipairs(mapData.ResourcePatches) do
		-- Find actual terrain surface height at this patch
		local surfaceY = 30
		if resTerrain then
			local result = workspace:Raycast(
				Vector3.new(patch.Position.X, 2000, patch.Position.Z),
				Vector3.new(0, -2500, 0),
				resRayParams
			)
			if result then
				surfaceY = result.Position.Y + 2
			end
		end

		local part = Instance.new("Part")
		part.Name = "Resource_" .. patch.Id
		part.Shape = Enum.PartType.Cylinder
		local h = 4
		part.Size = Vector3.new(h, patch.Radius * 2, patch.Radius * 2)
		part.CFrame = CFrame.new(patch.Position.X, surfaceY, patch.Position.Z)
			* CFrame.Angles(0, 0, math.rad(90))
		part.Anchored = true
		part.CanCollide = false
		part.Transparency = 0.45
		part.Material = Enum.Material.Neon
		part.Color = RESOURCE_VIZ_COLORS[patch.ResourceType] or Color3.fromRGB(200, 200, 200)
		part.Parent = folder

		-- Label
		local billboard = Instance.new("BillboardGui")
		billboard.Size = UDim2.new(0, 70, 0, 22)
		billboard.StudsOffset = Vector3.new(0, 4, 0)
		billboard.AlwaysOnTop = true
		billboard.Parent = part

		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 0.4
		label.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
		local ZONE_SHORT = { [0]="N", [1]="P1", [2]="P2", [3]="P3", [4]="P4" }
		local zonePrefix = ZONE_SHORT[patch.ZoneOwner or 0] or "N"
		local rLabel = (patch.ResourceType == "Iron_Ore") and "Iron Ore" or patch.ResourceType
		label.Text = zonePrefix .. " " .. rLabel
		label.TextColor3 = Color3.fromRGB(255, 240, 180)
		label.TextSize = 11
		label.Font = Enum.Font.GothamBold
		label.Parent = billboard

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 3)
		corner.Parent = label
	end
end

-- Place resource patches (handles batch from client)
function MapEditorManager.placeResourcePatch(player: Player, patches: { any })
	local userId = player.UserId
	local mapData = activeSessions[userId]
	if not mapData then return end
	if not mapData.ResourcePatches then mapData.ResourcePatches = {} end

	local HttpService = game:GetService("HttpService")

	for _, patch in ipairs(patches) do
		-- Assign a unique ID
		local newPatch = {
			Id = HttpService:GenerateGUID(false),
			ResourceType = patch.ResourceType or "Wood",
			ZoneOwner = patch.ZoneOwner or 0,
			Position = { X = patch.Position.X, Z = patch.Position.Z },
			Radius = math.clamp(patch.Radius or 30, 5, 200),
			Density = math.clamp(patch.Density or 5, 1, 10),
		}
		table.insert(mapData.ResourcePatches, newPatch)
	end

	-- If resource overlay is active, place models / recolor terrain for new patches immediately
	if resourceOverlayActive[userId] and #patches > 0 then
		local folder = getResourceModelsFolder()

		local newFoodPatches: { any } = {}
		for _, patch in ipairs(patches) do
			if patch.ResourceType ~= "Food" then
				scatterModelsForPatch(folder, patch)
			else
				table.insert(newFoodPatches, patch)
			end
		end

		if #newFoodPatches > 0 then
			if isStudioTerrainMode() then
				-- Studio terrain: disc Parts for Food patches
				if placeFoodDiscParts then placeFoodDiscParts(folder, newFoodPatches) end
			else
				-- Procedural terrain: voxel recolor over the dirty region
				local terrain = workspace:WaitForChild("Terrain") :: Terrain
				local minX, minZ =  math.huge,  math.huge
				local maxX, maxZ = -math.huge, -math.huge
				for _, patch in ipairs(newFoodPatches) do
					local r = patch.Radius or 30
					minX = math.min(minX, patch.Position.X - r)
					minZ = math.min(minZ, patch.Position.Z - r)
					maxX = math.max(maxX, patch.Position.X + r)
					maxZ = math.max(maxZ, patch.Position.Z + r)
				end
				local foodPatches = foodPatchesOnly(mapData.ResourcePatches)
				paintResourceRegion(terrain, foodPatches,
					Vector3.new(minX, -50, minZ), Vector3.new(maxX, 150, maxZ))
			end
		end
	else
		MapEditorManager.updateResourceVisualization(mapData)
	end
	-- Push to unified action stack (batch counts as one undo step)
	if #patches > 0 then
		if not undoActionStacks[userId] then undoActionStacks[userId] = {} end
		table.insert(undoActionStacks[userId], { type = "ResourcePatch", count = #patches })
		redoActionStacks[userId] = {}
	end
	fireResourceStats(player, mapData)
	MapEditorDebug:info("Placed " .. #patches .. " resource patches for " .. player.Name)
end

-- Delete a single resource patch by Id (called by Select tool Delete key on client)
function MapEditorManager.deleteResourcePatch(player: Player, patchId: string)
	local userId = player.UserId
	local mapData = activeSessions[userId]
	if not mapData or not mapData.ResourcePatches then return end

	local found: any? = nil
	for i, patch in ipairs(mapData.ResourcePatches) do
		if patch.Id == patchId then
			found = patch
			table.remove(mapData.ResourcePatches, i)
			break
		end
	end

	if not found then
		MapEditorDebug:warn("deleteResourcePatch: patch not found: " .. patchId)
		return
	end

	-- No undo entry for single-delete (Select tool is intentional; user sees the disc disappear)
	MapEditorManager.updateResourceVisualization(mapData)
	fireResourceStats(player, mapData)
	MapEditorDebug:info("Deleted resource patch " .. patchId .. " for " .. player.Name)
end

-- Zone paint overlay visualization
-- (constants and zoneGridCache declared near top of file)
-- (zoneGridCache declared near top of file so computeZoneAreas can use it)

function MapEditorManager.updateZoneVisualization(mapData: any, dirtyStrokes: { any }?, forceVisible: boolean?)
	local folder = workspace:FindFirstChild("MapEditorZones")
	local isVisible = if forceVisible ~= nil then forceVisible
		else (folder ~= nil and folder:GetAttribute("Visible") == true)

	local strokes = mapData.ZonePaintStrokes or {}
	local mapSize: number = mapData.Size or 1000

	local terrain = workspace:FindFirstChildWhichIsA("Terrain")
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Include
	if terrain then rayParams.FilterDescendantsInstances = { terrain } end

	-- Determine grid bounds from the larger of mapData.Size and actual terrain extents,
	-- capped at 1500 so we never create an excessive number of parts.
	local gridHalf: number = mapSize / 2
	if terrain then
		local ext = terrain.MaxExtents
		local terrainHalf = math.max(
			math.abs(ext.Min.X), math.abs(ext.Max.X),
			math.abs(ext.Min.Z), math.abs(ext.Max.Z)
		)
		if terrainHalf > gridHalf then gridHalf = terrainHalf end
	end
	gridHalf = math.min(gridHalf, 1500)

	local halfCells = math.ceil(gridHalf / OVERLAY_CELL)

	local function surfaceAt(wx: number, wz: number): number
		if not terrain then return 0 end
		local result = workspace:Raycast(Vector3.new(wx, 2000, wz), Vector3.new(0, -4000, 0), rayParams)
		return if result then result.Position.Y else 0
	end

	local overlayTransparency = isVisible and 0.45 or 1

	-- Clean up any legacy separate bg folder from old code
	local oldBg = workspace:FindFirstChild("MapEditorZonesBg")
	if oldBg then oldBg:Destroy() end

	-- ── Full rebuild ──────────────────────────────────────────────────────────
	-- Triggered on first open, after undo/redo, or when no folder exists.
	-- Strategy: single unified grid — every cell gets exactly ONE part whose
	-- colour reflects its zone (neutral/zone-0 for unpainted cells).
	-- No separate background layer means no transparency-blending artefacts.
	local fullRebuild = (dirtyStrokes == nil or not folder or next(zoneGridCache) == nil)

	if fullRebuild then
		-- Step 1: rasterise all strokes into the cache (last stroke painted wins).
		zoneGridCache = {}
		for _, stroke in ipairs(strokes) do
			local cx, cz = stroke.Position.X, stroke.Position.Z
			local r      = stroke.Radius or 40
			local zone   = stroke.Zone or 0
			local isSq   = stroke.Shape == "Square"
			local r2     = r * r
			for ix = math.floor((cx - r) / OVERLAY_CELL), math.floor((cx + r) / OVERLAY_CELL) do
				for iz = math.floor((cz - r) / OVERLAY_CELL), math.floor((cz + r) / OVERLAY_CELL) do
					local dx = (ix + 0.5) * OVERLAY_CELL - cx
					local dz = (iz + 0.5) * OVERLAY_CELL - cz
					local inside = if isSq then math.abs(dx) <= r and math.abs(dz) <= r
					              else dx * dx + dz * dz <= r2
					if inside then zoneGridCache[ix .. "," .. iz] = zone end
				end
			end
		end

		-- Step 2: build one Part per cell across the whole map.
		-- Cells not in the cache are neutral (zone 0).
		-- Run async in a coroutine so the server thread never hangs — we yield
		-- after every row of cells (each yield is one frame ≈ 1/60 s).
		if folder then folder:Destroy() end
		local newFolder = Instance.new("Folder")
		newFolder.Name  = "MapEditorZones"
		newFolder:SetAttribute("Visible", isVisible)
		newFolder.Parent = workspace  -- parent early so parts stream in visibly

		task.spawn(function()
			for ix = -halfCells, halfCells - 1 do
				-- Abort if another rebuild replaced our folder
				if workspace:FindFirstChild("MapEditorZones") ~= newFolder then return end
				for iz = -halfCells, halfCells - 1 do
					local key    = ix .. "," .. iz
					local zone   = zoneGridCache[key] or 0
					local cellCX = (ix + 0.5) * OVERLAY_CELL
					local cellCZ = (iz + 0.5) * OVERLAY_CELL
					local part   = Instance.new("Part")
					part.Name         = key
					part.Anchored     = true
					part.CanCollide   = false
					part.CastShadow   = false
					part.Transparency = overlayTransparency
					part.Material     = Enum.Material.Neon
					part.Color        = ZONE_VIZ_COLORS[zone] or ZONE_VIZ_COLORS[0]
					part.Shape        = Enum.PartType.Block
					part.Size         = Vector3.new(OVERLAY_CELL, OVERLAY_PART_H, OVERLAY_CELL)
					part.Position     = Vector3.new(cellCX, surfaceAt(cellCX, cellCZ) + OVERLAY_LIFT + OVERLAY_PART_H / 2, cellCZ)
					part.Parent       = newFolder
				end
				task.wait() -- yield once per row — keeps server responsive
			end
		end)

	else
		-- ── Incremental update ────────────────────────────────────────────────
		-- New strokes are always the most recent, so their zone wins for every
		-- cell they cover. Just update the cache and flip the colour on the
		-- existing Part — no need to replay all prior strokes.
		for _, stroke in ipairs(dirtyStrokes :: { any }) do
			local cx, cz = stroke.Position.X, stroke.Position.Z
			local r      = stroke.Radius or 40
			local zone   = stroke.Zone or 0
			local isSq   = stroke.Shape == "Square"
			local r2     = r * r
			for ix = math.floor((cx - r) / OVERLAY_CELL), math.floor((cx + r) / OVERLAY_CELL) do
				for iz = math.floor((cz - r) / OVERLAY_CELL), math.floor((cz + r) / OVERLAY_CELL) do
					local dx = (ix + 0.5) * OVERLAY_CELL - cx
					local dz = (iz + 0.5) * OVERLAY_CELL - cz
					local inside = if isSq then math.abs(dx) <= r and math.abs(dz) <= r
					              else dx * dx + dz * dz <= r2
					if inside then
						local key      = ix .. "," .. iz
						zoneGridCache[key] = zone
						local part = folder:FindFirstChild(key)
						if part and part:IsA("BasePart") then
							part.Color = ZONE_VIZ_COLORS[zone] or ZONE_VIZ_COLORS[0]
						else
							-- Part missing (e.g. stroke went outside original grid bounds).
							-- Trigger a full rebuild on next call.
							zoneGridCache = {}
							MapEditorManager.updateZoneVisualization(mapData, nil, forceVisible)
							return
						end
					end
				end
			end
		end
	end
end

-- Show or hide zone overlay (called when player switches tools)
function MapEditorManager.setZoneOverlayVisible(_player: Player, visible: boolean)
	local folder = workspace:FindFirstChild("MapEditorZones")
	if not folder then return end
	if folder:GetAttribute("Visible") == visible then return end
	folder:SetAttribute("Visible", visible)
	local transparency = visible and 0.45 or 1
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("BasePart") then
			child.Transparency = transparency
		end
	end
	-- Clean up any legacy bg folder from old sessions
	local oldBg = workspace:FindFirstChild("MapEditorZonesBg")
	if oldBg then oldBg:Destroy() end
end

-- Zone materials for terrain painting overlay (one per zone number).
-- These are chosen to give visually distinct colors without water/lava.
local ZONE_TERRAIN_MATERIALS: { [number]: Enum.Material } = {
	[0] = Enum.Material.Grass,       -- Neutral  (medium green)
	[1] = Enum.Material.Ice,         -- Player 1 (pale blue)
	[2] = Enum.Material.CrackedLava, -- Player 2 (dark orange-red)
	[3] = Enum.Material.Sand,        -- Player 3 (tan/yellow)
	[4] = Enum.Material.Snow,        -- Player 4 (white)
}

local ZONE_VOXEL_SIZE = 4

-- Build a flat zone lookup: for each voxel column (ix, iz) within the region,
-- pre-compute which zone wins. Returns a flat array indexed by (ix-1)*sizeZ + iz.
-- Cost: O(strokes × voxel_columns_in_region) — paid once, then lookups are O(1).
local function buildZoneLookup(strokes: { any }, corner: Vector3, sizeX: number, sizeZ: number): { number }
	local lookup: { number } = table.create(sizeX * sizeZ, 0)
	for _, stroke in ipairs(strokes) do
		local cx = stroke.Position.X
		local cz = stroke.Position.Z
		local r = stroke.Radius or 40
		local zone = stroke.Zone or 0
		local isSquare = stroke.Shape == "Square"
		local r2 = r * r

		-- Clamp to the columns that could possibly be inside this stroke
		local xiMin = math.max(1, math.floor((cx - r - corner.X) / ZONE_VOXEL_SIZE) + 1)
		local xiMax = math.min(sizeX, math.ceil((cx + r - corner.X) / ZONE_VOXEL_SIZE))
		local ziMin = math.max(1, math.floor((cz - r - corner.Z) / ZONE_VOXEL_SIZE) + 1)
		local ziMax = math.min(sizeZ, math.ceil((cz + r - corner.Z) / ZONE_VOXEL_SIZE))

		for xi = xiMin, xiMax do
			local wx = corner.X + (xi - 0.5) * ZONE_VOXEL_SIZE
			local dx = wx - cx
			for zi = ziMin, ziMax do
				local wz = corner.Z + (zi - 0.5) * ZONE_VOXEL_SIZE
				local dz = wz - cz
				local inside: boolean
				if isSquare then
					inside = math.abs(dx) <= r and math.abs(dz) <= r
				else
					inside = dx * dx + dz * dz <= r2
				end
				if inside then
					lookup[(xi - 1) * sizeZ + zi] = zone
				end
			end
		end
	end
	return lookup
end

-- Recolor a specific terrain region using zone stroke data.
-- Only reads/writes the given region, preserving occupancy exactly.
-- Only the topmost occupied voxel per column is recolored (visible surface only).
local function paintZoneRegion(terrain: Terrain, strokes: { any }, minPt: Vector3, maxPt: Vector3)
	local region = Region3.new(minPt, maxPt):ExpandToGrid(ZONE_VOXEL_SIZE)
	local ok, materials, occupancy = pcall(function()
		return terrain:ReadVoxels(region, ZONE_VOXEL_SIZE)
	end)
	if not ok then return end

	local sizeX = #materials
	if sizeX == 0 then return end
	local sizeY = #materials[1]
	local sizeZ = #materials[1][1]
	local corner = region.CFrame.Position - region.Size / 2

	-- Pre-bake zone per column: O(strokes × columns), paid once
	local lookup = buildZoneLookup(strokes, corner, sizeX, sizeZ)

	for xi = 1, sizeX do
		for zi = 1, sizeZ do
			local zoneMat = ZONE_TERRAIN_MATERIALS[lookup[(xi - 1) * sizeZ + zi]] or Enum.Material.Grass
			-- Only recolor occupied voxels (preserve underground material too for consistency)
			for yi = 1, sizeY do
				if occupancy[xi][yi][zi] > 0.1 then
					materials[xi][yi][zi] = zoneMat
				end
			end
		end
	end

	terrain:WriteVoxels(region, ZONE_VOXEL_SIZE, materials, occupancy)
end

-- Show zone overlay: reveal part-based overlay that sits on terrain surface.
function MapEditorManager.showZoneOverlay(player: Player)
	local userId = player.UserId
	local mapData = activeSessions[userId]
	if not mapData then return end

	zoneOverlayActive[userId] = true
	MapEditorManager.updateZoneVisualization(mapData)
	MapEditorManager.setZoneOverlayVisible(player, true)
	MapEditorDebug:info("Zone overlay shown for " .. player.Name)
end

-- (kept for non-Studio path — unused when Studio terrain mode is on)
local function _showZoneOverlayVoxels(player: Player)
	local userId = player.UserId
	local mapData = activeSessions[userId]
	if not mapData then return end

	local terrain = workspace:WaitForChild("Terrain") :: Terrain
	local strokes = mapData.ZonePaintStrokes or {}
	local mapSize = mapData.Size or 1000
	local halfSize = mapSize / 2

	-- Process in chunks so the server doesn't stall for one long operation.
	-- Each chunk is a row of Z-strips across the full X extent.
	local CHUNK_Z = 200 -- studs per chunk row
	local zStart = -halfSize
	while zStart < halfSize do
		local zEnd = math.min(zStart + CHUNK_Z, halfSize)
		paintZoneRegion(
			terrain, strokes,
			Vector3.new(-halfSize, -50, zStart),
			Vector3.new(halfSize, 150, zEnd)
		)
		zStart = zEnd
		task.wait() -- yield between chunks so other work can run
	end

	zoneOverlayActive[userId] = true
	MapEditorDebug:info("Zone overlay painted for " .. player.Name .. " (" .. #strokes .. " strokes)")
end

-- Hide zone overlay parts when player switches away from ZonePaint tool.
function MapEditorManager.hideZoneOverlay(player: Player)
	zoneOverlayActive[player.UserId] = false
	MapEditorManager.setZoneOverlayVisible(player, false)
	MapEditorDebug:info("Zone overlay hidden for " .. player.Name)
end

-- Apply zone paint strokes (handles batch from client).
-- While the overlay is active, only repaints the small region covered by the new strokes.
function MapEditorManager.paintZone(player: Player, strokes: { any })
	local userId = player.UserId
	local mapData = activeSessions[userId]
	if not mapData then return end
	if not mapData.ZonePaintStrokes then mapData.ZonePaintStrokes = {} end

	local saved: { any } = {}
	for _, stroke in ipairs(strokes) do
		local newStroke = {
			Zone = stroke.Zone or 0,
			Position = { X = stroke.Position.X, Z = stroke.Position.Z },
			Radius = math.clamp(stroke.Radius or 40, 10, 400),
			Shape = stroke.Shape or "Circle",
		}
		table.insert(mapData.ZonePaintStrokes, newStroke)
		table.insert(saved, newStroke)
	end

	-- If overlay is active, incrementally update only the painted region.
	-- Pass forceVisible=true so parts are always created at the right transparency,
	-- even on the first stroke (when no folder exists yet to read state from).
	if zoneOverlayActive[userId] and #saved > 0 then
		MapEditorManager.updateZoneVisualization(mapData, saved, true)
	end

	-- Push to unified action stack (batch counts as one undo step)
	if #saved > 0 then
		if not undoActionStacks[userId] then undoActionStacks[userId] = {} end
		table.insert(undoActionStacks[userId], { type = "ZonePaint", count = #saved })
		redoActionStacks[userId] = {}
	end

	-- Fire updated zone area stats to the client
	fireZoneStats(player, mapData)

	MapEditorDebug:info("Painted " .. #strokes .. " zone strokes for " .. player.Name)
end

-- ─── Zone polygon painter ─────────────────────────────────────────────────────

-- Ray-cast point-in-polygon test (XZ plane).  vertices is an array of {X, Z}.
local function pointInPolygonServer(px: number, pz: number, vertices: { any }): boolean
	local inside = false
	local j = #vertices
	for i = 1, #vertices do
		local xi, zi = vertices[i].X, vertices[i].Z
		local xj, zj = vertices[j].X, vertices[j].Z
		if (zi > pz) ~= (zj > pz) then
			if px < (xj - xi) * (pz - zi) / (zj - zi) + xi then
				inside = not inside
			end
		end
		j = i
	end
	return inside
end

-- Stud resolution used when rasterizing a polygon into ZonePaintStrokes
local POLYGON_RASTER_CELL = 40

-- Commit a polygon zone region: store the polygon vertices AND rasterize it into
-- ZonePaintStrokes so the game's existing zone-sampling logic can use it.
function MapEditorManager.paintZonePolygon(player: Player, data: any)
	local userId = player.UserId
	local mapData = activeSessions[userId]
	if not mapData then return end

	local zone = math.clamp(data.Zone or 0, 0, 4)
	local vertices = data.Vertices
	if not vertices or #vertices < 3 then
		MapEditorDebug:warn("paintZonePolygon: need ≥3 vertices, got " .. tostring(vertices and #vertices or 0))
		return
	end

	-- Store raw polygon for future re-editing
	if not mapData.ZonePolygons then mapData.ZonePolygons = {} end
	table.insert(mapData.ZonePolygons, { Zone = zone, Vertices = vertices })

	-- Rasterize into ZonePaintStrokes on a POLYGON_RASTER_CELL grid
	if not mapData.ZonePaintStrokes then mapData.ZonePaintStrokes = {} end

	local minX, minZ, maxX, maxZ = math.huge, math.huge, -math.huge, -math.huge
	for _, v in ipairs(vertices) do
		minX = math.min(minX, v.X); maxX = math.max(maxX, v.X)
		minZ = math.min(minZ, v.Z); maxZ = math.max(maxZ, v.Z)
	end

	local cell = POLYGON_RASTER_CELL
	local halfCell = cell / 2
	local strokesAdded = 0
	local x = minX + halfCell
	while x <= maxX do
		local z = minZ + halfCell
		while z <= maxZ do
			if pointInPolygonServer(x, z, vertices) then
				table.insert(mapData.ZonePaintStrokes, {
					Zone = zone,
					Position = { X = x, Z = z },
					Radius = halfCell,
					Shape = "Square",
				})
				strokesAdded += 1
			end
			z += cell
		end
		x += cell
	end

	-- Rebuild overlay and notify client
	MapEditorManager.updateZoneVisualization(mapData)
	if zoneOverlayActive[userId] then
		MapEditorManager.setZoneOverlayVisible(player, true)
	end
	fireZoneStats(player, mapData)
	fireEditorEvent(player, "PolygonCommitted", {})

	MapEditorDebug:info(string.format("Zone polygon committed: zone %d, %d vertices, %d raster strokes",
		zone, #vertices, strokesAdded))
end

-- ─── Resource overlay (terrain-painting, same approach as zone overlay) ───────

-- Terrain material per resource type (distinct, readable colors)
local RESOURCE_TERRAIN_MATERIALS: { [string]: Enum.Material } = {
	Wood     = Enum.Material.LeafyGrass, -- bright green
	Stone    = Enum.Material.Slate,      -- dark grey-blue
	Food     = Enum.Material.LeafyGrass, -- bright green grass
	Iron_Ore = Enum.Material.Sandstone,  -- rust orange-brown
}

-- Build a flat resource-material lookup for a region.
-- Each column gets the material of the last patch that covers it, or nil if none.
local function buildResourceLookup(
	patches: { any },
	corner: Vector3,
	sizeX: number,
	sizeZ: number
): { Enum.Material? }
	local lookup: { Enum.Material? } = table.create(sizeX * sizeZ, nil)
	for _, patch in ipairs(patches) do
		local cx = patch.Position.X
		local cz = patch.Position.Z
		local r = patch.Radius or 30
		local mat = RESOURCE_TERRAIN_MATERIALS[patch.ResourceType]
		if not mat then continue end
		local r2 = r * r

		local xiMin = math.max(1, math.floor((cx - r - corner.X) / ZONE_VOXEL_SIZE) + 1)
		local xiMax = math.min(sizeX, math.ceil((cx + r - corner.X) / ZONE_VOXEL_SIZE))
		local ziMin = math.max(1, math.floor((cz - r - corner.Z) / ZONE_VOXEL_SIZE) + 1)
		local ziMax = math.min(sizeZ, math.ceil((cz + r - corner.Z) / ZONE_VOXEL_SIZE))

		for xi = xiMin, xiMax do
			local wx = corner.X + (xi - 0.5) * ZONE_VOXEL_SIZE
			local dx = wx - cx
			for zi = ziMin, ziMax do
				local wz = corner.Z + (zi - 0.5) * ZONE_VOXEL_SIZE
				local dz = wz - cz
				if dx * dx + dz * dz <= r2 then
					lookup[(xi - 1) * sizeZ + zi] = mat
				end
			end
		end
	end
	return lookup
end

-- Recolor a terrain region with resource patch colors.
-- Columns not covered by any patch keep their existing material (zone or real terrain).
paintResourceRegion = function(terrain: Terrain, patches: { any }, minPt: Vector3, maxPt: Vector3)
	local region = Region3.new(minPt, maxPt):ExpandToGrid(ZONE_VOXEL_SIZE)
	local ok, materials, occupancy = pcall(function()
		return terrain:ReadVoxels(region, ZONE_VOXEL_SIZE)
	end)
	if not ok then return end

	local sizeX = #materials
	if sizeX == 0 then return end
	local sizeY = #materials[1]
	local sizeZ = #materials[1][1]
	local corner = region.CFrame.Position - region.Size / 2

	local lookup = buildResourceLookup(patches, corner, sizeX, sizeZ)

	for xi = 1, sizeX do
		for zi = 1, sizeZ do
			local mat = lookup[(xi - 1) * sizeZ + zi]
			if mat then
				for yi = 1, sizeY do
					if occupancy[xi][yi][zi] > 0.1 then
						materials[xi][yi][zi] = mat
					end
				end
			end
		end
	end

	terrain:WriteVoxels(region, ZONE_VOXEL_SIZE, materials, occupancy)
end

-- ─── Resource model overlay helpers ─────────────────────────────────────────

-- Get (or create) the folder that holds resource model overlay instances.
getResourceModelsFolder = function(): Folder
	local folder = workspace:FindFirstChild("MapEditorResourceModels")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "MapEditorResourceModels"
		folder.Parent = workspace
	end
	return folder :: Folder
end

-- Raycast straight down to find the terrain surface Y at (x, z).
local function getTerrainSurfaceY(x: number, z: number): number
	local terrain = workspace:FindFirstChildOfClass("Terrain")
	if not terrain then return 5 end
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Include
	rp.FilterDescendantsInstances = { terrain }
	local result = workspace:Raycast(Vector3.new(x, 2000, z), Vector3.new(0, -2500, 0), rp)
	return result and result.Position.Y or 5
end

-- Cache of rock templates from ReplicatedStorage.Assets.DetailProps.Rocks
-- rockBridgeTemplates  → used as quarry floor (RockBridge pieces)
-- rockScatterTemplates → everything else, scattered around the bridge
local rockBridgeTemplates: { any }? = nil
local rockScatterTemplates: { any }? = nil

-- Names that are unnamed placeholders — skip these
local ROCK_SKIP_NAMES: { [string]: boolean } = { ["MeshPart"] = true }
-- The base platform placed at the patch center
local ROCK_BRIDGE_NAME = "RockBridge"

local function getRockTemplates()
	if rockBridgeTemplates then
		return rockBridgeTemplates :: { any }, rockScatterTemplates :: { any }
	end
	local ok, rocksFolder = pcall(function()
		return ReplicatedStorage:WaitForChild("Assets", 1)
			:WaitForChild("DetailProps", 1)
			:WaitForChild("Rocks", 1)
	end)
	rockBridgeTemplates = {}
	rockScatterTemplates = {}
	if ok and rocksFolder then
		for _, child in ipairs(rocksFolder:GetChildren()) do
			if ROCK_SKIP_NAMES[child.Name] then continue end
			if child.Name == ROCK_BRIDGE_NAME then
				table.insert(rockBridgeTemplates :: { any }, child)
			else
				table.insert(rockScatterTemplates :: { any }, child)
			end
		end
		MapEditorDebug:info(
			"Rock templates — bridge: " .. #(rockBridgeTemplates :: { any }) ..
			", scatter: " .. #(rockScatterTemplates :: { any })
		)
	else
		MapEditorDebug:warn("No rocks folder found at ReplicatedStorage.Assets.DetailProps.Rocks")
	end
	return rockBridgeTemplates :: { any }, rockScatterTemplates :: { any }
end

-- Place a single MeshPart rock at (x, z), sitting on the terrain surface.
-- Scales the mesh so its Y height matches targetHeight (with optional ±jitter fraction),
-- then applies a random Y rotation and positions it on terrain.
local function placeRockMesh(folder: Folder, template: BasePart, x: number, z: number, targetHeight: number, jitter: number?)
	local baseY = getTerrainSurfaceY(x, z)
	local clone = template:Clone()
	clone.Name = template.Name
	clone.Anchored = true
	clone.CanCollide = false
	clone.CastShadow = false
	-- Scale uniformly so the mesh is targetHeight studs tall, then apply jitter
	local baseScale = targetHeight / template.Size.Y
	local jitterAmount = jitter or 0
	local finalScale = baseScale * (1 + (math.random() * 2 - 1) * jitterAmount)
	clone.Size = template.Size * finalScale
	-- Random Y rotation for visual variety
	local rot = CFrame.Angles(0, math.random() * math.pi * 2, 0)
	-- Sit the part so its bottom face is at baseY
	local halfH = clone.Size.Y / 2
	clone.CFrame = CFrame.new(x, baseY + halfH, z) * rot
	clone.Parent = folder
end

-- Cache of tree templates picked from ReplicatedStorage.Assets.DetailProps.Trees
local treeTemplates: { any }? = nil
local function getTreeTemplates(): { any }
	if treeTemplates then return treeTemplates end
	local ok, treesFolder = pcall(function()
		return ReplicatedStorage:WaitForChild("Assets", 1)
			:WaitForChild("DetailProps", 1)
			:WaitForChild("Trees", 1)
	end)
	if ok and treesFolder then
		treeTemplates = treesFolder:GetChildren()
		local t = treeTemplates :: { any }
		MapEditorDebug:info("Tree templates found: " .. #t .. (if #t > 0 then " — first: " .. t[1].Name else ""))
	else
		treeTemplates = {}
		MapEditorDebug:warn("No tree templates found at ReplicatedStorage.Assets.DetailProps.Trees")
	end
	return treeTemplates :: { any }
end

-- Place a single tree at the given world position.
-- Clones a random model from ReplicatedStorage.Assets.DetailProps.Trees if available,
-- otherwise falls back to a simple procedural trunk+leaves.
local function placeTree(folder: Folder, x: number, z: number)
	local baseY = getTerrainSurfaceY(x, z)
	local templates = getTreeTemplates()

	if #templates > 0 then
		local template = templates[math.random(1, #templates)]
		local clone = template:Clone()
		clone.Name = "Tree"

		-- Remove any scripts inside the tree model that might hide/animate it
		for _, child in ipairs(clone:GetDescendants()) do
			if child:IsA("Script") or child:IsA("LocalScript") or child:IsA("ModuleScript") then
				child:Destroy()
			end
		end

		-- Anchor all parts and make them visible before parenting
		for _, part in ipairs(clone:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Anchored = true
				part.CanCollide = false
				part.CastShadow = false
				part.Transparency = math.min(part.Transparency, 0.0) -- ensure visible
			end
		end
		if clone:IsA("BasePart") then
			local bp = clone :: BasePart
			bp.Anchored = true
			bp.CanCollide = false
			bp.CastShadow = false
			bp.Transparency = 0
		end

		-- Parent, pivot to XZ at Y=0, read bounding box bottom, then shift up to baseY
		clone.Parent = folder
		clone:PivotTo(CFrame.new(x, 0, z))
		local bbCf, bbSize = clone:GetBoundingBox()
		local bottomY = bbCf.Position.Y - bbSize.Y / 2
		clone:PivotTo(CFrame.new(x, -bottomY + baseY, z))
	else
		-- Fallback: procedural trunk + leaves
		local trunkH = math.random(8, 14)
		local trunk = Instance.new("Part")
		trunk.Name = "TreeTrunk"
		trunk.Size = Vector3.new(2, trunkH, 2)
		trunk.Position = Vector3.new(x, baseY + trunkH / 2, z)
		trunk.Anchored = true
		trunk.CanCollide = false
		trunk.CastShadow = false
		trunk.Color = Color3.fromRGB(101, 67, 33)
		trunk.Material = Enum.Material.Wood
		trunk.Parent = folder

		local leavesR = math.random(5, 9)
		local leaves = Instance.new("Part")
		leaves.Name = "TreeLeaves"
		leaves.Shape = Enum.PartType.Ball
		leaves.Size = Vector3.new(leavesR * 2, leavesR * 2, leavesR * 2)
		leaves.Position = Vector3.new(x, baseY + trunkH + leavesR * 0.6, z)
		leaves.Anchored = true
		leaves.CanCollide = false
		leaves.CastShadow = false
		leaves.Color = Color3.fromRGB(math.random(40, 80), math.random(110, 160), math.random(30, 70))
		leaves.Material = Enum.Material.LeafyGrass
		leaves.Parent = folder
	end
end

-- Place a single rock model at the given world position.
-- Place a stone patch: one RockBridge platform at the center, scatter rocks around it.
-- brushRadius: when isCenterBridge=true, scales the bridge XZ to fill the brush diameter.
local function placeRock(folder: Folder, x: number, z: number, isCenterBridge: boolean?, brushRadius: number?)
	local bridges, scatters = getRockTemplates()

	if isCenterBridge then
		-- Scale RockBridge XZ so it fills the brush circle diameter; keep Y at native thickness.
		if #bridges > 0 then
			local template = bridges[math.random(1, #bridges)] :: BasePart
			local baseY = getTerrainSurfaceY(x, z)
			local clone = template:Clone()
			clone.Name = template.Name
			clone.Anchored = true
			clone.CanCollide = false
			clone.CastShadow = false
			-- Scale XZ to slightly exceed the brush diameter so rotated tiles overlap and
			-- close the gaps left by the rectangular mesh not covering a full circle.
			local diameter = (brushRadius or 30) * 2.8
			local scaleX = diameter / template.Size.X
			local scaleZ = diameter / template.Size.Z
			clone.Size = Vector3.new(
				template.Size.X * scaleX,
				template.Size.Y,
				template.Size.Z * scaleZ
			)
			local halfH = clone.Size.Y / 2
			local rot = CFrame.Angles(0, math.random() * math.pi * 2, 0)
			clone.CFrame = CFrame.new(x, baseY + halfH, z) * rot
			clone.Parent = folder
		end
	else
		-- Place a decorative scatter rock scaled to ~6 studs tall (±30% jitter for variety)
		if #scatters > 0 then
			local template = scatters[math.random(1, #scatters)] :: BasePart
			placeRockMesh(folder, template, x, z, 6, 0.3)
		else
			-- Fallback: procedural sphere rock
			local baseY = getTerrainSurfaceY(x, z)
			local r = math.random(4, 9)
			local rock = Instance.new("Part")
			rock.Name = "Rock"
			rock.Shape = Enum.PartType.Ball
			rock.Size = Vector3.new(r * 2, r * 1.2, r * 2)
			rock.Position = Vector3.new(x, baseY + r * 0.4, z)
			rock.Anchored = true
			rock.CanCollide = false
			rock.CastShadow = false
			rock.Color = Color3.fromRGB(math.random(120, 160), math.random(115, 155), math.random(110, 150))
			rock.Material = Enum.Material.Slate
			rock.Parent = folder
		end
	end
end

-- Place an iron ore boulder at the given world position.
local function placeIronOre(folder: Folder, x: number, z: number)
	local baseY = getTerrainSurfaceY(x, z)
	local r = math.random(3, 6)
	local ore = Instance.new("Part")
	ore.Name = "IronOre"
	ore.Shape = Enum.PartType.Ball
	ore.Size = Vector3.new(r * 2, r * 1.4, r * 2)
	ore.Position = Vector3.new(x, baseY + r * 0.5, z)
	ore.Anchored = true
	ore.CanCollide = false
	ore.CastShadow = false
	ore.Color = Color3.fromRGB(math.random(100, 130), math.random(70, 95), math.random(55, 80))
	ore.Material = Enum.Material.Sandstone
	ore.Parent = folder
end

-- Scatter models for a single resource patch into the given folder.
scatterModelsForPatch = function(folder: Folder, patch: any)
	local px = patch.Position.X
	local pz = patch.Position.Z
	local r = patch.Radius or 30
	local rType = patch.ResourceType or "Wood"
	local r2 = r * r
	-- Density is 1–10 (default 5). Scale counts so density=5 is the original baseline.
	local density = math.clamp(patch.Density or 5, 1, 10)
	local densityScale = density / 5

	if rType == "Wood" then
		-- Dense tree placement: roughly 1 tree per ~100 sq studs within the patch circle.
		local area = math.pi * r * r
		local count = math.clamp(math.floor(area / 100 * densityScale), 2, 160)
		local placed = 0
		local attempts = 0
		while placed < count and attempts < count * 6 do
			attempts += 1
			local angle = math.random() * math.pi * 2
			local dist = math.random() * r
			local tx = px + math.cos(angle) * dist
			local tz = pz + math.sin(angle) * dist
			local dx, dz = tx - px, tz - pz
			if dx * dx + dz * dz <= r2 then
				placeTree(folder, tx, tz)
				placed += 1
			end
		end

	elseif rType == "Stone" then
		-- One RockBridge platform at the patch center, scaled to fill the brush area.
		placeRock(folder, px, pz, true, r)
		-- Scatter a small cluster of decorative rocks around it.
		-- Base count targets ~5 rocks at density=5 regardless of radius size.
		local count = math.clamp(math.floor(5 * densityScale), 1, 20)
		for _ = 1, count do
			local angle = math.random() * math.pi * 2
			local dist = math.random() * r * 0.85
			placeRock(folder, px + math.cos(angle) * dist, pz + math.sin(angle) * dist, false)
		end

	elseif rType == "Iron_Ore" then
		-- Small ore cluster near the patch center.
		local count = math.clamp(math.floor(math.pi * r * r / 300 * densityScale), 1, 30)
		for _ = 1, count do
			local angle = math.random() * math.pi * 2
			local dist = math.random() * r * 0.7
			placeIronOre(folder, px + math.cos(angle) * dist, pz + math.sin(angle) * dist)
		end
	end
	-- Food patches are handled via terrain voxel recoloring (LeafyGrass), no models needed.
end

-- Collect only Food patches from a list (for terrain voxel recoloring).
foodPatchesOnly = function(patches: { any }): { any }
	local result: { any } = {}
	for _, p in ipairs(patches) do
		if p.ResourceType == "Food" then
			table.insert(result, p)
		end
	end
	return result
end

-- Place colored disc Parts for Food patches (used in Studio terrain mode instead of WriteVoxels).
placeFoodDiscParts = function(folder: Folder, patches: { any })
	local terrain = workspace:FindFirstChildOfClass("Terrain")
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Include
	if terrain then
		rayParams.FilterDescendantsInstances = { terrain }
	end

	for _, patch in ipairs(patches) do
		local surfaceY = 30
		if terrain then
			local result = workspace:Raycast(
				Vector3.new(patch.Position.X, 2000, patch.Position.Z),
				Vector3.new(0, -2500, 0),
				rayParams
			)
			if result then surfaceY = result.Position.Y + 2 end
		end

		local part = Instance.new("Part")
		part.Name = "FoodDisc_" .. patch.Id
		part.Shape = Enum.PartType.Cylinder
		local h = 4
		part.Size = Vector3.new(h, patch.Radius * 2, patch.Radius * 2)
		part.CFrame = CFrame.new(patch.Position.X, surfaceY, patch.Position.Z)
			* CFrame.Angles(0, 0, math.rad(90))
		part.Anchored = true
		part.CanCollide = false
		part.Transparency = 0.45
		part.Material = Enum.Material.Neon
		part.Color = RESOURCE_VIZ_COLORS["Food"]
		part.CastShadow = false
		part.Parent = folder
	end
end

-- Show resource overlay:
--   • Wood / Stone / Iron_Ore → place 3D model instances in MapEditorResourceModels folder.
--   • Food (non-Studio) → recolor terrain voxels with LeafyGrass.
--   • Food (Studio terrain) → place colored disc Parts (same as other resource types).
function MapEditorManager.showResourceOverlay(player: Player)
	local userId = player.UserId
	local mapData = activeSessions[userId]
	if not mapData then return end

	local patches = mapData.ResourcePatches or {}

	-- Clear any existing model overlay first
	local existingModels = workspace:FindFirstChild("MapEditorResourceModels")
	if existingModels then existingModels:Destroy() end

	local folder = getResourceModelsFolder()

	-- Place models for Wood / Stone / Iron_Ore patches
	for _, patch in ipairs(patches) do
		if patch.ResourceType ~= "Food" then
			scatterModelsForPatch(folder, patch)
		end
	end

	-- Food patches: disc parts in Studio terrain mode, voxel recoloring otherwise
	local foodPatches = foodPatchesOnly(patches)
	if #foodPatches > 0 then
		if isStudioTerrainMode() then
			placeFoodDiscParts(folder, foodPatches)
		else
			local terrain = workspace:WaitForChild("Terrain") :: Terrain
			local mapSize = mapData.Size or 1000
			local halfSize = mapSize / 2
			local CHUNK_Z = 200
			local zStart = -halfSize
			while zStart < halfSize do
				local zEnd = math.min(zStart + CHUNK_Z, halfSize)
				paintResourceRegion(
					terrain, foodPatches,
					Vector3.new(-halfSize, -50, zStart),
					Vector3.new(halfSize, 150, zEnd)
				)
				zStart = zEnd
				task.wait()
			end
		end
	end

	resourceOverlayActive[userId] = true
	MapEditorDebug:info("Resource overlay shown for " .. player.Name .. " (" .. #patches .. " patches)")
end

-- Hide resource overlay: destroy model folder and restore real terrain.
function MapEditorManager.hideResourceOverlay(player: Player)
	resourceOverlayActive[player.UserId] = false

	local folder = workspace:FindFirstChild("MapEditorResourceModels")
	if folder then folder:Destroy() end

	-- In Studio terrain mode there's no terrain recoloring to undo
	if not isStudioTerrainMode() then
		MapEditorManager.regenerateAll(player)
	end
	MapEditorDebug:info("Resource overlay hidden for " .. player.Name)
end

-- Place or update a Keep spawn zone (click-to-place in Spawns sub-mode)
function MapEditorManager.updateKeepSpawn(player: Player, data: any)
	local userId = player.UserId
	local mapData = activeSessions[userId]
	if not mapData then return end

	if not mapData.KeepSpawnZones then mapData.KeepSpawnZones = {} end

	local zoneNum = math.clamp(data.Zone or 1, 1, 4)
	local pos = data.Position or { X = 0, Y = 0, Z = 0 }
	local radius = math.clamp(data.Radius or 150, 50, 400)

	-- Validate: all 9 sample points (center + 4 corners + 4 mid-edges) must be
	-- within the correct player's zone. Uses the full radius so the entire square is checked.
	local checkOffsets = {
		{ 0, 0 },
		-- corners
		{ radius, radius }, { -radius, radius },
		{ radius, -radius }, { -radius, -radius },
		-- mid-edges
		{ radius, 0 }, { -radius, 0 },
		{ 0, radius }, { 0, -radius },
	}
	local matchCount = 0
	for _, off in ipairs(checkOffsets) do
		if getZoneAt(mapData, pos.X + off[1], pos.Z + off[2]) == zoneNum then
			matchCount += 1
		end
	end
	if matchCount < #checkOffsets then
		MapEditorDebug:warn(string.format(
			"updateKeepSpawn: P%d spawn rejected — not fully in P%d zone (matched %d/%d samples) for %s",
			zoneNum, zoneNum, matchCount, #checkOffsets, player.Name))
		fireEditorEvent(player, "SpawnPlacementRejected", {
			Zone = zoneNum,
			Reason = "Must place P" .. zoneNum .. " spawn within P" .. zoneNum .. " territory.",
		})
		return
	end

	-- Replace existing entry for this zone number, or add new
	local found = false
	for i, entry in ipairs(mapData.KeepSpawnZones) do
		if entry.Zone == zoneNum then
			mapData.KeepSpawnZones[i] = { Zone = zoneNum, X = pos.X, Y = pos.Y, Z = pos.Z, Radius = radius }
			found = true
			break
		end
	end
	if not found then
		table.insert(mapData.KeepSpawnZones, { Zone = zoneNum, X = pos.X, Y = pos.Y, Z = pos.Z, Radius = radius })
	end

	MapEditorDebug:info(string.format("Keep spawn zone %d set to (%.0f, %.0f, %.0f) r=%.0f for %s",
		zoneNum, pos.X, pos.Y, pos.Z, radius, player.Name))

	-- Update workspace visualization: one disc per zone in MapEditorSpawnZones folder
	local spawnFolder = workspace:FindFirstChild("MapEditorSpawnZones")
	if not spawnFolder then
		spawnFolder = Instance.new("Folder")
		spawnFolder.Name = "MapEditorSpawnZones"
		spawnFolder.Parent = workspace
	end
	-- Remove old disc for this zone
	local existing = spawnFolder:FindFirstChild("Spawn_" .. zoneNum)
	if existing then existing:Destroy() end
	-- Create new square marker
	local disc = Instance.new("Part")
	disc.Name = "Spawn_" .. zoneNum
	disc.Shape = Enum.PartType.Block
	disc.Size = Vector3.new(radius * 2, 6, radius * 2)
	disc.CFrame = CFrame.new(pos.X, pos.Y + 3, pos.Z)
	disc.Anchored = true
	disc.CanCollide = false
	disc.Material = Enum.Material.Neon
	disc.Color = ZONE_VIZ_COLORS[zoneNum] or Color3.fromRGB(200, 200, 200)
	disc.Transparency = 0.35
	disc.CastShadow = false
	disc.Parent = spawnFolder
	-- Add a label billboard
	local bg = Instance.new("BillboardGui")
	bg.Name = "SpawnLabel"
	bg.Size = UDim2.new(0, 80, 0, 30)
	bg.StudsOffset = Vector3.new(0, 8, 0)
	bg.AlwaysOnTop = true
	bg.Parent = disc
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, 0, 1, 0)
	lbl.BackgroundTransparency = 1
	lbl.Text = "P" .. zoneNum .. " Spawn"
	lbl.TextColor3 = Color3.fromRGB(255, 255, 255)
	lbl.TextScaled = true
	lbl.Font = Enum.Font.GothamBold
	lbl.Parent = bg

	-- Fire updated list back to client for confirmation
	fireEditorEvent(player, "KeepSpawnUpdated", { Zone = zoneNum, KeepSpawnZones = mapData.KeepSpawnZones })
end

-- Get active session data
function MapEditorManager.getSession(player: Player): any?
	return activeSessions[player.UserId]
end

-- Load a saved custom map by userId + mapId and return its data (no session required).
-- Used at game start (in Studio terrain mode) to retrieve painted KeepSpawnZones and
-- ResourcePatches without entering the editor.
function MapEditorManager.loadCustomMapData(userId: number, mapId: string): any?
	local key = "CustomMap_" .. userId .. "_" .. mapId
	local success, result = pcall(function()
		return mapDataStore:GetAsync(key)
	end)
	if success and result then
		local data = HttpService:JSONDecode(result)
		if not data.ResourcePatches then data.ResourcePatches = {} end
		if not data.ZonePaintStrokes then data.ZonePaintStrokes = {} end
		if not data.KeepSpawnZones then data.KeepSpawnZones = {} end
		MapEditorDebug:info(string.format(
			"loadCustomMapData: loaded '%s' (%d resource patches, %d keep spawns)",
			data.Name or mapId, #data.ResourcePatches, #data.KeepSpawnZones
		))
		return data
	end
	MapEditorDebug:warn("loadCustomMapData: failed to load " .. key)
	return nil
end

return MapEditorManager
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                