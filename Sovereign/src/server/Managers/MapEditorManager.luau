--!strict
-- MapEditorManager: Server-side manager for the in-game map editor
-- Handles terrain operations, feature placement, and save/load

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")

local DebugManager = require(ReplicatedStorage.Shared.DebugManager)
local MapEditorDebug = DebugManager.createChannel("MapEditorManager", true)

local MapEditorManager = {}

-- Active editor sessions: { [userId]: CustomMapData }
local activeSessions: { [number]: any } = {}

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

	-- Clear terrain and generate base
	local terrain = workspace:WaitForChild("Terrain")
	terrain:Clear()

	-- Generate base terrain
	MapEditorManager.generateBaseTerrain(terrain, mapData)

	-- Generate spawn zone visualization
	MapEditorManager.updateSpawnVisualization(mapData)

	-- Set player attribute so client controller activates
	player:SetAttribute("MapEditorActive", true)

	-- Notify client that editor is ready
	fireEditorEvent(player, "EditorReady", {
		Name = mapData.Name,
		Size = mapData.Size,
		MaxPlayers = mapData.MaxPlayers,
	})

	MapEditorDebug:info("Editor ready for " .. player.Name)
	return mapData
end

-- Leave the editor: clean up
function MapEditorManager.leaveEditor(player: Player)
	local userId = player.UserId
	MapEditorDebug:info(player.Name .. " leaving map editor")

	activeSessions[userId] = nil

	-- Clear terrain
	local terrain = workspace:WaitForChild("Terrain")
	terrain:Clear()

	-- Clean up spawn visualization
	local spawnFolder = workspace:FindFirstChild("MapEditorSpawnZones")
	if spawnFolder then
		spawnFolder:Destroy()
	end

	-- Clean up feature markers
	local featureFolder = workspace:FindFirstChild("MapEditorFeatures")
	if featureFolder then
		featureFolder:Destroy()
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

	local terrain = workspace:WaitForChild("Terrain")
	terrain:Clear()
	MapEditorManager.generateBaseTerrain(terrain, mapData)

	-- Replay all brush strokes
	MapEditorManager.replayStrokes(terrain, mapData)

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

	local terrain = workspace:WaitForChild("Terrain")
	terrain:Clear()

	-- Base terrain
	MapEditorManager.generateBaseTerrain(terrain, mapData)

	-- Replay strokes
	MapEditorManager.replayStrokes(terrain, mapData)

	-- Replay features
	MapEditorManager.replayFeatures(terrain, mapData)

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

-- Update spawn zone visualization
function MapEditorManager.updateSpawnVisualization(mapData: any)
	local folder = workspace:FindFirstChild("MapEditorSpawnZones")
	if folder then
		folder:ClearAllChildren()
	else
		folder = Instance.new("Folder")
		folder.Name = "MapEditorSpawnZones"
		folder.Parent = workspace
	end

	local spawnColors = {
		Color3.fromRGB(100, 130, 160),
		Color3.fromRGB(160, 100, 100),
		Color3.fromRGB(100, 150, 100),
		Color3.fromRGB(150, 140, 80),
	}

	for _, zone in ipairs(mapData.SpawnZones) do
		local part = Instance.new("Part")
		part.Name = "SpawnZone_" .. zone.SpawnNumber
		part.Size = Vector3.new(zone.HalfSize * 2, 1, zone.HalfSize * 2)
		part.Position = Vector3.new(zone.Center.X, 0.5, zone.Center.Z)
		part.Anchored = true
		part.CanCollide = false
		part.Transparency = 0.7
		part.Color = spawnColors[zone.SpawnNumber] or Color3.fromRGB(150, 150, 150)
		part.Material = Enum.Material.Neon
		part.Parent = folder

		-- Label
		local billboard = Instance.new("BillboardGui")
		billboard.Size = UDim2.new(0, 80, 0, 30)
		billboard.StudsOffset = Vector3.new(0, 5, 0)
		billboard.AlwaysOnTop = true
		billboard.Parent = part

		local labels = { "NW", "NE", "SW", "SE" }
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 0.5
		label.BackgroundColor3 = Color3.fromRGB(30, 25, 20)
		label.Text = "Spawn " .. zone.SpawnNumber .. " (" .. (labels[zone.SpawnNumber] or "?") .. ")"
		label.TextColor3 = Color3.fromRGB(255, 220, 100)
		label.TextSize = 12
		label.Font = Enum.Font.GothamBold
		label.Parent = billboard

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 4)
		corner.Parent = label
	end

	-- Neutral zone cross
	local neutralWidth = mapData.NeutralZoneWidth
	local mapSize = mapData.Size

	local hPart = Instance.new("Part")
	hPart.Name = "NeutralHorizontal"
	hPart.Size = Vector3.new(mapSize, 1, neutralWidth)
	hPart.Position = Vector3.new(0, 0.6, 0)
	hPart.Anchored = true
	hPart.CanCollide = false
	hPart.Transparency = 0.75
	hPart.Color = Color3.fromRGB(140, 120, 80)
	hPart.Material = Enum.Material.Neon
	hPart.Parent = folder

	local vPart = Instance.new("Part")
	vPart.Name = "NeutralVertical"
	vPart.Size = Vector3.new(neutralWidth, 1, mapSize)
	vPart.Position = Vector3.new(0, 0.6, 0)
	vPart.Anchored = true
	vPart.CanCollide = false
	vPart.Transparency = 0.75
	vPart.Color = Color3.fromRGB(140, 120, 80)
	vPart.Material = Enum.Material.Neon
	vPart.Parent = folder
end

-- Update spawn zone config
function MapEditorManager.updateSpawnZone(player: Player, zoneConfig: any)
	local userId = player.UserId
	local mapData = activeSessions[userId]
	if not mapData then return end

	for i, zone in ipairs(mapData.SpawnZones) do
		if zone.SpawnNumber == zoneConfig.SpawnNumber then
			mapData.SpawnZones[i] = zoneConfig
			break
		end
	end

	MapEditorManager.updateSpawnVisualization(mapData)
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
			MapEditorManager.updateSpawnVisualization(mapData)
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

		-- Regenerate terrain from loaded data
		local terrain = workspace:WaitForChild("Terrain")
		terrain:Clear()
		MapEditorManager.generateBaseTerrain(terrain, loadedData)
		MapEditorManager.replayStrokes(terrain, loadedData)
		MapEditorManager.replayFeatures(terrain, loadedData)
		MapEditorManager.updateSpawnVisualization(loadedData)

		fireEditorEvent(player, "MapLoaded", {
			Name = loadedData.Name,
			Size = loadedData.Size,
			MaxPlayers = loadedData.MaxPlayers,
		})
		MapEditorDebug:info("Loaded map:", loadedData.Name)
		return
	end

	MapEditorDebug:warn("Failed to load map:", mapId)
end

-- Export map as Lua code string
function MapEditorManager.exportMap(player: Player)
	local userId = player.UserId
	local mapData = activeSessions[userId]
	if not mapData then return end

	-- Generate a MapConfig-compatible Lua table string
	local lines = {}
	table.insert(lines, '[\"Custom_' .. mapData.MapId .. '\"] = {')
	table.insert(lines, '\tName = "' .. mapData.Name .. '",')
	table.insert(lines, '\tDescription = "' .. mapData.Description .. '",')
	table.insert(lines, '\tSize = ' .. mapData.Size .. ',')
	table.insert(lines, '\tTerrainType = "Custom",')
	table.insert(lines, '\tMaxPlayers = ' .. mapData.MaxPlayers .. ',')
	table.insert(lines, '\tQuadrantSize = ' .. (mapData.SpawnZones[1] and mapData.SpawnZones[1].HalfSize * 2 or 400) .. ',')
	table.insert(lines, '\tNeutralZoneWidth = ' .. mapData.NeutralZoneWidth .. ',')
	table.insert(lines, '\tSpawnHeight = ' .. mapData.SpawnHeight .. ',')
	table.insert(lines, '\tResourceDensity = {')
	table.insert(lines, '\t\tWood = ' .. mapData.ResourceDensity.Wood .. ',')
	table.insert(lines, '\t\tStone = ' .. mapData.ResourceDensity.Stone .. ',')
	table.insert(lines, '\t\tFood = ' .. mapData.ResourceDensity.Food .. ',')
	table.insert(lines, '\t\tIron_Ore = ' .. mapData.ResourceDensity.Iron_Ore .. ',')
	table.insert(lines, '\t},')
	table.insert(lines, '\tFeatures = {')
	table.insert(lines, '\t\tHasCentralLake = false,')
	table.insert(lines, '\t\tHasMountains = false,')
	table.insert(lines, '\t\tHasForests = false,')
	table.insert(lines, '\t\tHasRivers = false,')
	table.insert(lines, '\t},')
	table.insert(lines, '\tPreviewColors = {')
	local base = mapData.PreviewColors.Base
	table.insert(lines, '\t\tBase = { ' .. base[1] .. ', ' .. base[2] .. ', ' .. base[3] .. ' },')
	table.insert(lines, '\t},')
	table.insert(lines, '} :: MapConfig,')

	local luaCode = table.concat(lines, "\n")
	fireEditorEvent(player, "ExportResult", { luaCode = luaCode })
end

-- Get active session data
function MapEditorManager.getSession(player: Player): any?
	return activeSessions[player.UserId]
end

return MapEditorManager
