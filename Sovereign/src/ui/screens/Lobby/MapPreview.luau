--!strict
-- MapPreview: Renders a generated minimap preview with terrain features and clickable spawn picker
local React = require(game.ReplicatedStorage.Packages.react)
local UIConfig = require(script.Parent.Parent.Parent.UIConfig)
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MapPreview = React.Component:extend("MapPreview")

-- Fallback spawn zone labels and layout positions (used when no KeepSpawnZones data)
local SPAWN_INFO = {
	[1] = { label = "NW", posX = 0, posZ = 0 },
	[2] = { label = "NE", posX = 1, posZ = 0 },
	[3] = { label = "SW", posX = 0, posZ = 1 },
	[4] = { label = "SE", posX = 1, posZ = 1 },
}

local SPAWN_LABELS = { [1] = "P1", [2] = "P2", [3] = "P3", [4] = "P4" }

-- Zone colors (index 0 = neutral, 1-4 = players)
local ZONE_COLORS = {
	[0] = Color3.fromRGB(140, 120, 80),
	[1] = Color3.fromRGB(80, 120, 180),
	[2] = Color3.fromRGB(180, 80, 80),
	[3] = Color3.fromRGB(80, 160, 80),
	[4] = Color3.fromRGB(180, 160, 60),
}

-- Default spawn zone colors (used when no player color is assigned)
local DEFAULT_SPAWN_COLORS = {
	[1] = Color3.fromRGB(80, 120, 180),
	[2] = Color3.fromRGB(180, 80, 80),
	[3] = Color3.fromRGB(80, 160, 80),
	[4] = Color3.fromRGB(180, 160, 60),
}

-- Neutral zone color
local NEUTRAL_COLOR = Color3.fromRGB(140, 120, 80)

-- Grid resolution for zone rasterization
local GRID_SIZE = 48

local function rgbToColor3(rgb: { number }): Color3
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

-- Try to load BuiltinMapData for a given map key. Returns nil if not found.
local builtinDataCache: { [string]: any } = {}
local function loadBuiltinData(mapKey: string): any?
	if builtinDataCache[mapKey] ~= nil then
		return builtinDataCache[mapKey]
	end
	local folder = ReplicatedStorage:FindFirstChild("Shared")
		and (ReplicatedStorage.Shared :: any):FindFirstChild("GameData")
		and ((ReplicatedStorage.Shared :: any).GameData :: any):FindFirstChild("BuiltinMapData")
	if not folder then
		builtinDataCache[mapKey] = false
		return nil
	end
	local mod = (folder :: any):FindFirstChild(mapKey)
	if not mod then
		builtinDataCache[mapKey] = false
		return nil
	end
	local ok, data = pcall(require, mod)
	if ok and type(data) == "table" then
		builtinDataCache[mapKey] = data
		return data
	end
	builtinDataCache[mapKey] = false
	return nil
end

-- Rasterize ZonePaintStrokes into a GRID_SIZE×GRID_SIZE grid.
-- Returns a flat array: -1 = unpainted, 0 = neutral zone, 1-4 = player zone.
local function rasterizeZones(strokes: any, mapSize: number): { number }
	local grid: { number } = table.create(GRID_SIZE * GRID_SIZE, -1)
	local half = mapSize / 2
	local cellSize = mapSize / GRID_SIZE

	for _, stroke in ipairs(strokes) do
		local zone: number = stroke.Zone or 0
		local wx: number = stroke.Position.X
		local wz: number = stroke.Position.Z
		local r: number = stroke.Radius

		-- Find the range of grid cells the stroke circle could touch
		local minCol = math.max(0, math.floor((wx - r + half) / cellSize))
		local maxCol = math.min(GRID_SIZE - 1, math.floor((wx + r + half) / cellSize))
		local minRow = math.max(0, math.floor((wz - r + half) / cellSize))
		local maxRow = math.min(GRID_SIZE - 1, math.floor((wz + r + half) / cellSize))

		for row = minRow, maxRow do
			for col = minCol, maxCol do
				-- Cell center in world space
				local cx = (col + 0.5) * cellSize - half
				local cz = (row + 0.5) * cellSize - half
				local dx = cx - wx
				local dz = cz - wz
				if dx * dx + dz * dz <= r * r then
					grid[row * GRID_SIZE + col + 1] = zone
				end
			end
		end
	end

	return grid
end

function MapPreview:render()
	local mapKey: string? = self.props.mapKey
	local mapConfig = self.props.mapConfig
	local spawnSelections = self.props.spawnSelections or {}
	local mySpawn = self.props.mySpawn
	local onSpawnSelected = self.props.onSpawnSelected
	local players = self.props.players or {}

	-- Build a lookup from userId to selectedColor
	local playerColors: { [number]: Color3 } = {}
	for _, playerInfo in ipairs(players) do
		if playerInfo.selectedColor then
			local sc = playerInfo.selectedColor
			playerColors[playerInfo.userId] = Color3.fromRGB(sc[1], sc[2], sc[3])
		end
	end

	-- Normalize spawnSelections keys to numbers (server may send string keys)
	local normalizedSpawns: { [number]: any } = {}
	for key, value in pairs(spawnSelections) do
		normalizedSpawns[tonumber(key)] = value
	end
	spawnSelections = normalizedSpawns

	-- Normalize mySpawn to number
	if mySpawn then
		mySpawn = tonumber(mySpawn)
	end

	-- Determine base color and features from map config
	local baseColor = Color3.fromRGB(100, 160, 70)
	local waterColor = Color3.fromRGB(50, 120, 200)
	local mountainColor = Color3.fromRGB(140, 130, 120)
	local forestColor = Color3.fromRGB(40, 100, 30)

	local hasLake = false
	local hasMountains = false
	local hasForests = false
	local hasRivers = false
	local mapName = "Unknown Map"
	local mapDescription = ""
	local mapSize = 1000
	local maxPlayers = 4

	if mapConfig then
		mapName = mapConfig.Name or mapName
		mapDescription = mapConfig.Description or ""
		mapSize = mapConfig.Size or mapSize
		maxPlayers = mapConfig.MaxPlayers or maxPlayers

		if mapConfig.PreviewColors then
			if mapConfig.PreviewColors.Base then baseColor = rgbToColor3(mapConfig.PreviewColors.Base) end
			if mapConfig.PreviewColors.Water then waterColor = rgbToColor3(mapConfig.PreviewColors.Water) end
			if mapConfig.PreviewColors.Mountain then mountainColor = rgbToColor3(mapConfig.PreviewColors.Mountain) end
			if mapConfig.PreviewColors.Forest then forestColor = rgbToColor3(mapConfig.PreviewColors.Forest) end
		end

		if mapConfig.Features then
			hasLake = mapConfig.Features.HasCentralLake or false
			hasMountains = mapConfig.Features.HasMountains or false
			hasForests = mapConfig.Features.HasForests or false
			hasRivers = mapConfig.Features.HasRivers or false
		end
	end

	-- Try to load painted zone data from BuiltinMapData
	local builtinData: any? = mapKey and loadBuiltinData(mapKey) or nil
	local zoneGrid: { number }? = nil
	if builtinData and builtinData.ZonePaintStrokes and #builtinData.ZonePaintStrokes > 0 then
		zoneGrid = rasterizeZones(builtinData.ZonePaintStrokes, mapSize)
	end

	local previewImage: string? = mapConfig and (mapConfig :: any).PreviewImage or nil

	-- Build feature indicator elements on the minimap
	local featureElements: any = {}

	if previewImage then
		-- Screenshot mode: full-canvas image, zone color overlays on top
		featureElements["Screenshot"] = React.createElement("ImageLabel", {
			Size = UDim2.fromScale(1, 1),
			Position = UDim2.fromScale(0, 0),
			BackgroundTransparency = 1,
			Image = previewImage,
			ScaleType = Enum.ScaleType.Stretch,
			ZIndex = 2,
		})
		-- Overlay painted zones as semi-transparent color tints
		if zoneGrid then
			local cellScale = 1 / GRID_SIZE
			for row = 0, GRID_SIZE - 1 do
				for col = 0, GRID_SIZE - 1 do
					local zone = zoneGrid[row * GRID_SIZE + col + 1]
					if zone > 0 then
						featureElements["ZC_" .. row .. "_" .. col] = React.createElement("Frame", {
							Size = UDim2.fromScale(cellScale + 0.002, cellScale + 0.002),
							Position = UDim2.fromScale(col * cellScale, row * cellScale),
							BackgroundColor3 = ZONE_COLORS[zone] or NEUTRAL_COLOR,
							BackgroundTransparency = 0.5,
							BorderSizePixel = 0,
							ZIndex = 3,
						})
					end
				end
			end
		end
	elseif zoneGrid then
		-- Zone-grid mode: water background + land cells + zone color overlays
		local hasWater = mapConfig ~= nil and mapConfig.PreviewColors ~= nil and mapConfig.PreviewColors.Water ~= nil
		local cellScale = 1 / GRID_SIZE
		for row = 0, GRID_SIZE - 1 do
			for col = 0, GRID_SIZE - 1 do
				local zone = zoneGrid[row * GRID_SIZE + col + 1]
				if zone == -1 then continue end
				local key = row .. "_" .. col
				featureElements["ZT_" .. key] = React.createElement("Frame", {
					Size = UDim2.fromScale(cellScale + 0.002, cellScale + 0.002),
					Position = UDim2.fromScale(col * cellScale, row * cellScale),
					BackgroundColor3 = baseColor,
					BackgroundTransparency = 0,
					BorderSizePixel = 0,
					ZIndex = 2,
				})
				if zone > 0 then
					featureElements["ZC_" .. key] = React.createElement("Frame", {
						Size = UDim2.fromScale(cellScale + 0.002, cellScale + 0.002),
						Position = UDim2.fromScale(col * cellScale, row * cellScale),
						BackgroundColor3 = ZONE_COLORS[zone] or NEUTRAL_COLOR,
						BackgroundTransparency = 0.3,
						BorderSizePixel = 0,
						ZIndex = 3,
					})
				end
			end
		end
		if hasWater then
			-- Swap background to water — land cells drawn above it define the terrain shape
			-- (handled below via previewBgColor)
		end
	else
		-- Procedural fallback for maps without image or painted data
		if hasLake then
			featureElements["Lake"] = React.createElement("Frame", {
				Size = UDim2.fromScale(0.15, 0.15),
				Position = UDim2.fromScale(0.5, 0.5),
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = waterColor,
				BackgroundTransparency = 0.3,
				BorderSizePixel = 0,
				ZIndex = 3,
			}, {
				UICorner = React.createElement("UICorner", { CornerRadius = UDim.new(1, 0) }),
			})
		end
		if hasRivers then
			featureElements["River"] = React.createElement("Frame", {
				Size = UDim2.new(0.9, 0, 0, 3),
				Position = UDim2.fromScale(0.5, 0.5),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Rotation = 20,
				BackgroundColor3 = waterColor,
				BackgroundTransparency = 0.4,
				BorderSizePixel = 0,
				ZIndex = 3,
			})
		end
		if hasMountains then
			for i, pos in ipairs({ { 0.25, 0.25 }, { 0.75, 0.75 }, { 0.7, 0.2 }, { 0.3, 0.8 } }) do
				featureElements["Mountain" .. i] = React.createElement("Frame", {
					Size = UDim2.fromScale(0.08, 0.08),
					Position = UDim2.fromScale(pos[1], pos[2]),
					AnchorPoint = Vector2.new(0.5, 0.5),
					BackgroundColor3 = mountainColor,
					BackgroundTransparency = 0.3,
					BorderSizePixel = 0,
					ZIndex = 3,
				}, {
					UICorner = React.createElement("UICorner", { CornerRadius = UDim.new(0.3, 0) }),
				})
			end
		end
		if hasForests then
			for i, pos in ipairs({ { 0.15, 0.35 }, { 0.85, 0.35 }, { 0.15, 0.65 }, { 0.85, 0.65 }, { 0.35, 0.15 }, { 0.65, 0.85 } }) do
				featureElements["Forest" .. i] = React.createElement("Frame", {
					Size = UDim2.fromScale(0.06, 0.06),
					Position = UDim2.fromScale(pos[1], pos[2]),
					AnchorPoint = Vector2.new(0.5, 0.5),
					BackgroundColor3 = forestColor,
					BackgroundTransparency = 0.3,
					BorderSizePixel = 0,
					ZIndex = 3,
				}, {
					UICorner = React.createElement("UICorner", { CornerRadius = UDim.new(1, 0) }),
				})
			end
		end
	end

	local hasWater = mapConfig ~= nil and mapConfig.PreviewColors ~= nil and mapConfig.PreviewColors.Water ~= nil
	local previewBgColor = (zoneGrid ~= nil and not previewImage and hasWater) and waterColor or baseColor

	-- Neutral zone cross — only shown for quadrant-based maps without image or painted zone data
	local neutralProportion = 0.1
	if mapConfig and mapConfig.NeutralZoneWidth and mapConfig.Size then
		neutralProportion = mapConfig.NeutralZoneWidth / mapConfig.Size
	end

	local hasCustomSpawns = mapConfig ~= nil and mapConfig.KeepSpawnZones ~= nil and #(mapConfig.KeepSpawnZones :: any) > 0
	if not hasCustomSpawns and not zoneGrid and not previewImage then
		featureElements["NeutralHorizontal"] = React.createElement("Frame", {
			Size = UDim2.new(1, 0, neutralProportion, 0),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = NEUTRAL_COLOR,
			BackgroundTransparency = 0.3,
			BorderSizePixel = 0,
			ZIndex = 4,
		})

		featureElements["NeutralVertical"] = React.createElement("Frame", {
			Size = UDim2.new(neutralProportion, 0, 1, 0),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = NEUTRAL_COLOR,
			BackgroundTransparency = 0.3,
			BorderSizePixel = 0,
			ZIndex = 4,
		})

		featureElements["NeutralLabel"] = React.createElement("TextLabel", {
			Size = UDim2.fromScale(neutralProportion * 2, neutralProportion * 2),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			Text = "Neutral",
			TextColor3 = Color3.fromRGB(220, 200, 160),
			TextSize = 9,
			FontFace = UIConfig.Font.Default,
			ZIndex = 6,
		})
	end

	-- Spawn zone buttons: clickable buttons overlaid on top of zone regions
	local keepSpawnZones: { { Zone: number, X: number, Z: number } }? = if mapConfig then mapConfig.KeepSpawnZones else nil
	local spawnHalf = (1 - neutralProportion) / 2

	-- Build the list of zones to render: either from KeepSpawnZones or fallback SPAWN_INFO
	local zonesForRender: { { zoneNum: number, posX: number, posZ: number, label: string } } = {}
	if keepSpawnZones and #keepSpawnZones > 0 then
		local halfSize = mapSize / 2
		for _, zone in ipairs(keepSpawnZones) do
			if zone.Zone <= maxPlayers then
				-- Convert world X/Z (-halfSize..+halfSize) to preview 0..1
				local px = (zone.X + halfSize) / mapSize
				local pz = (zone.Z + halfSize) / mapSize
				table.insert(zonesForRender, {
					zoneNum = zone.Zone,
					posX = math.clamp(px, 0.05, 0.95),
					posZ = math.clamp(pz, 0.05, 0.95),
					label = SPAWN_LABELS[zone.Zone] or tostring(zone.Zone),
				})
			end
		end
	else
		for spawnNum, info in pairs(SPAWN_INFO) do
			if spawnNum <= maxPlayers then
				table.insert(zonesForRender, {
					zoneNum = spawnNum,
					posX = info.posX == 0 and (spawnHalf / 2) or (1 - spawnHalf / 2),
					posZ = info.posZ == 0 and (spawnHalf / 2) or (1 - spawnHalf / 2),
					label = info.label,
				})
			end
		end
	end

	-- Spawn button size: compact pin for placed spawns, quadrant-sized for fallback
	local spawnButtonScale = (keepSpawnZones and #keepSpawnZones > 0) and 0.1 or spawnHalf

	for _, zoneInfo in ipairs(zonesForRender) do
		local spawnNum = zoneInfo.zoneNum
		local selection = spawnSelections[spawnNum]
		local isMine = mySpawn == spawnNum
		local isClaimed = selection ~= nil
		local claimedByName = selection and selection.name or nil

		local bgColor = DEFAULT_SPAWN_COLORS[spawnNum] or NEUTRAL_COLOR
		if selection and playerColors[selection.userId] then
			bgColor = playerColors[selection.userId]
		end

		local bgTransparency = 0.55
		if isMine then
			bgTransparency = 0.1
		elseif isClaimed then
			bgTransparency = 0.35
		end

		local labelText = zoneInfo.label
		if claimedByName then
			labelText = zoneInfo.label .. "\n" .. claimedByName
		end

		local spawnChildren: any = {}
		spawnChildren["UICorner"] = React.createElement("UICorner", {
			CornerRadius = UDim.new(0.15, 0),
		})
		if isMine then
			spawnChildren["UIStroke"] = React.createElement("UIStroke", {
				Color = Color3.fromRGB(255, 215, 0),
				Thickness = 2,
			})
		end

		featureElements["Spawn" .. spawnNum] = React.createElement("TextButton", {
			Name = "Spawn" .. spawnNum,
			Size = UDim2.fromScale(spawnButtonScale, spawnButtonScale),
			Position = UDim2.fromScale(zoneInfo.posX, zoneInfo.posZ),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = bgColor,
			BackgroundTransparency = bgTransparency,
			BorderSizePixel = 0,
			Text = labelText,
			TextColor3 = Color3.fromRGB(255, 255, 255),
			TextSize = 10,
			FontFace = UIConfig.Font.Default,
			TextWrapped = true,
			ZIndex = 8,
			[React.Event.MouseButton1Click] = function()
				if onSpawnSelected then
					onSpawnSelected(spawnNum)
				end
			end,
		}, spawnChildren)
	end

	-- Container with centered map
	return React.createElement("Frame", {
		Name = "MapPreviewContainer",
		Size = self.props.Size or UDim2.new(1, 0, 0.5, 0),
		BackgroundTransparency = 1,
		LayoutOrder = self.props.LayoutOrder,
	}, {
		-- Map title
		Title = React.createElement("TextLabel", {
			Text = mapName,
			Size = UDim2.new(1, 0, 0, 22),
			Position = UDim2.new(0.5, 0, 0, 0),
			AnchorPoint = Vector2.new(0.5, 0),
			FontFace = UIConfig.Font.Title,
			TextColor3 = Color3.fromRGB(220, 200, 160),
			TextSize = 18,
			BackgroundTransparency = 1,
			TextXAlignment = Enum.TextXAlignment.Center,
		}),

		-- Centered map area
		PreviewWrapper = React.createElement("Frame", {
			Name = "PreviewWrapper",
			Size = UDim2.new(1, 0, 1, -56),
			Position = UDim2.new(0.5, 0, 0, 24),
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundTransparency = 1,
		}, {
			PreviewFrame = React.createElement("Frame", {
				Name = "PreviewFrame",
				Size = UDim2.fromScale(1, 1),
				Position = UDim2.fromScale(0.5, 0.5),
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = previewImage and Color3.fromRGB(0, 0, 0) or previewBgColor,
				BackgroundTransparency = previewImage and 1 or 0,
				BorderSizePixel = 0,
				ClipsDescendants = true,
			}, {
				UIAspectRatioConstraint = React.createElement("UIAspectRatioConstraint", {
					AspectRatio = 1,
					AspectType = Enum.AspectType.FitWithinMaxSize,
					DominantAxis = Enum.DominantAxis.Width,
				}),
				UICorner = React.createElement("UICorner", {
					CornerRadius = UDim.new(0, 4),
				}),
				UIStroke = React.createElement("UIStroke", {
					Color = Color3.fromRGB(100, 80, 50),
					Thickness = 2,
				}),
			}, featureElements),
		}),

		-- Info bar
		InfoBar = React.createElement("TextLabel", {
			Text = string.format("%dx%d  |  %d players  |  Click zone to spawn", mapSize, mapSize, maxPlayers),
			Size = UDim2.new(1, 0, 0, 14),
			Position = UDim2.new(0.5, 0, 1, -28),
			AnchorPoint = Vector2.new(0.5, 0),
			FontFace = UIConfig.Font.Default,
			TextColor3 = Color3.fromRGB(160, 150, 130),
			TextSize = 10,
			BackgroundTransparency = 1,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Center,
		}),

		-- Description
		Description = (mapDescription ~= "") and React.createElement("TextLabel", {
			Text = mapDescription,
			Size = UDim2.new(1, 0, 0, 14),
			Position = UDim2.new(0.5, 0, 1, -14),
			AnchorPoint = Vector2.new(0.5, 0),
			FontFace = UIConfig.Font.Default,
			TextColor3 = Color3.fromRGB(130, 125, 110),
			TextSize = 9,
			BackgroundTransparency = 1,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Center,
		}) or nil,
	})
end

return MapPreview
