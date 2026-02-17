--!strict
-- MapPreview: Renders a generated minimap preview with terrain features and clickable spawn picker
local React = require(game.ReplicatedStorage.Packages.react)
local UIConfig = require(script.Parent.Parent.Parent.UIConfig)

local MapPreview = React.Component:extend("MapPreview")

-- Spawn zone labels and layout positions
local SPAWN_INFO = {
	[1] = { label = "NW", posX = 0, posZ = 0 },
	[2] = { label = "NE", posX = 1, posZ = 0 },
	[3] = { label = "SW", posX = 0, posZ = 1 },
	[4] = { label = "SE", posX = 1, posZ = 1 },
}

-- Default spawn zone colors (used when no player color is assigned)
local DEFAULT_SPAWN_COLORS = {
	[1] = Color3.fromRGB(100, 130, 160),
	[2] = Color3.fromRGB(160, 100, 100),
	[3] = Color3.fromRGB(100, 150, 100),
	[4] = Color3.fromRGB(150, 140, 80),
}

-- Neutral zone color
local NEUTRAL_COLOR = Color3.fromRGB(140, 120, 80)

local function rgbToColor3(rgb: { number }): Color3
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

function MapPreview:render()
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

	-- Build feature indicator elements on the minimap
	local featureElements: any = {}

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

	-- Neutral zone cross with distinct color
	local neutralProportion = 0.1
	if mapConfig and mapConfig.NeutralZoneWidth and mapConfig.Size then
		neutralProportion = mapConfig.NeutralZoneWidth / mapConfig.Size
	end

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

	-- "Neutral" label in the center
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

	-- Spawn zone buttons with player-chosen colors
	local spawnHalf = (1 - neutralProportion) / 2
	for spawnNum, info in pairs(SPAWN_INFO) do
		if spawnNum <= maxPlayers then
			local selection = spawnSelections[spawnNum]
			local isMine = mySpawn == spawnNum
			local isClaimed = selection ~= nil
			local claimedByName = selection and selection.name or nil

			local posX = info.posX == 0 and (spawnHalf / 2) or (1 - spawnHalf / 2)
			local posZ = info.posZ == 0 and (spawnHalf / 2) or (1 - spawnHalf / 2)

			-- Use the player's chosen color if they have one, otherwise use default
			local bgColor = DEFAULT_SPAWN_COLORS[spawnNum]
			if selection and playerColors[selection.userId] then
				bgColor = playerColors[selection.userId]
			end

			local bgTransparency = 0.75
			if isMine then
				bgTransparency = 0.35
			elseif isClaimed then
				bgTransparency = 0.55
			end

			-- Build label: direction + player name
			local labelText = info.label
			if claimedByName then
				labelText = info.label .. "\n" .. claimedByName
			end

			local spawnChildren: any = {}
			spawnChildren["UICorner"] = React.createElement("UICorner", {
				CornerRadius = UDim.new(0.05, 0),
			})

			-- Color indicator dot in the corner
			spawnChildren["ColorDot"] = React.createElement("Frame", {
				Size = UDim2.fromOffset(10, 10),
				Position = UDim2.new(0, 4, 0, 4),
				BackgroundColor3 = bgColor,
				BorderSizePixel = 0,
				ZIndex = 7,
			}, {
				UICorner = React.createElement("UICorner", { CornerRadius = UDim.new(1, 0) }),
			})

			-- Selection border when it's mine
			if isMine then
				spawnChildren["UIStroke"] = React.createElement("UIStroke", {
					Color = Color3.fromRGB(255, 215, 0),
					Thickness = 2,
				})
			end

			featureElements["Spawn" .. spawnNum] = React.createElement("TextButton", {
				Name = "Spawn" .. spawnNum,
				Size = UDim2.fromScale(spawnHalf, spawnHalf),
				Position = UDim2.fromScale(posX, posZ),
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = bgColor,
				BackgroundTransparency = bgTransparency,
				BorderSizePixel = 0,
				Text = labelText,
				TextColor3 = Color3.fromRGB(255, 255, 255),
				TextSize = 10,
				FontFace = UIConfig.Font.Default,
				TextWrapped = true,
				ZIndex = 5,
				[React.Event.MouseButton1Click] = function()
					if onSpawnSelected then
						onSpawnSelected(spawnNum)
					end
				end,
			}, spawnChildren)
		end
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
				BackgroundColor3 = baseColor,
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
