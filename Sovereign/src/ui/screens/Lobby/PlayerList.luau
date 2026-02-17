-- PlayerList: Displays lobby players with dropdown color picker, faction selector, and ready status
local React = require(game.ReplicatedStorage.Packages.react)
local UIConfig = require(script.Parent.Parent.Parent.UIConfig)
local Toggle = require(script.Parent.Parent.Parent.components.Toggle)

local PlayerList = React.Component:extend("PlayerList")

local FACTIONS = { "Kingdom", "Empire", "Tribes", "IronLegion" }

-- Expanded color palette for player selection
local COLOR_OPTIONS = {
	{ r = 70, g = 130, b = 200, name = "Blue" },
	{ r = 200, g = 70, b = 70, name = "Red" },
	{ r = 70, g = 180, b = 70, name = "Green" },
	{ r = 200, g = 180, b = 50, name = "Yellow" },
	{ r = 180, g = 80, b = 200, name = "Purple" },
	{ r = 220, g = 130, b = 50, name = "Orange" },
	{ r = 80, g = 200, b = 200, name = "Cyan" },
	{ r = 200, g = 100, b = 150, name = "Pink" },
	{ r = 255, g = 255, b = 255, name = "White" },
	{ r = 120, g = 120, b = 120, name = "Gray" },
	{ r = 160, g = 100, b = 60, name = "Brown" },
	{ r = 50, g = 200, b = 130, name = "Teal" },
}

-- Grid layout: 4 columns
local COLOR_COLUMNS = 4
local COLOR_SQUARE_SIZE = 22
local COLOR_SQUARE_GAP = 3

function PlayerList:init()
	self.state = {
		colorDropdownOpen = false, -- is the local player's dropdown open
	}
end

function PlayerList:render()
	local players = self.props.players or {}
	local onAddAI = self.props.onAddAI
	local onRemovePlayer = self.props.onRemovePlayer
	local onSelectFaction = self.props.onSelectFaction
	local onSelectColor = self.props.onSelectColor
	local localPlayerId = self.props.localPlayerId
	local Button = self.props.Button
	local lobbyConfig = UIConfig.LobbyPage
	local paddingConfig = lobbyConfig.Padding

	-- Helper to check if a color is taken by another player
	local function isColorTaken(colorOption, currentUserId)
		for _, player in ipairs(players) do
			if player.userId ~= currentUserId and player.selectedColor then
				local sc = player.selectedColor
				if sc[1] == colorOption.r and sc[2] == colorOption.g and sc[3] == colorOption.b then
					return true
				end
			end
		end
		return false
	end

	-- Helper to check if this color matches the player's selected color
	local function isPlayerColor(colorOption, playerInfo)
		if not playerInfo.selectedColor then return false end
		local sc = playerInfo.selectedColor
		return sc[1] == colorOption.r and sc[2] == colorOption.g and sc[3] == colorOption.b
	end

	-- Helper to check if a faction is taken by another player
	local function isFactionTaken(faction, currentPlayerId)
		for _, player in ipairs(players) do
			if player.faction == faction and player.userId ~= currentPlayerId then
				return true
			end
		end
		return false
	end

	local playerFrameChildren = {
		Layout = React.createElement("UIListLayout", {
			Padding = paddingConfig.PlayerListSpacing,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}

	-- Sort players to put local player first
	local sortedPlayers = {}
	for _, player in ipairs(players) do
		table.insert(sortedPlayers, player)
	end
	table.sort(sortedPlayers, function(a, b)
		if a.userId == localPlayerId then
			return true
		elseif b.userId == localPlayerId then
			return false
		else
			return a.name < b.name
		end
	end)

	for i, playerInfo in ipairs(sortedPlayers) do
		local isLocalPlayer = playerInfo.userId == localPlayerId

		-- Filter available factions
		local availableFactions = {}
		for _, faction in ipairs(FACTIONS) do
			local isTaken = isFactionTaken(faction, playerInfo.userId)
			if not isTaken or playerInfo.faction == faction then
				table.insert(availableFactions, faction)
			end
		end
		if #availableFactions == 0 then
			availableFactions = FACTIONS
		end

		-- Get player's color for the indicator
		local playerColorDisplay = Color3.fromRGB(180, 180, 180)
		local playerColorName = "None"
		if playerInfo.selectedColor then
			local sc = playerInfo.selectedColor
			playerColorDisplay = Color3.fromRGB(sc[1], sc[2], sc[3])
			-- Find the name
			for _, co in ipairs(COLOR_OPTIONS) do
				if co.r == sc[1] and co.g == sc[2] and co.b == sc[3] then
					playerColorName = co.name
					break
				end
			end
		end

		-- Build the color dropdown button (clickable square that opens/closes dropdown)
		local colorButtonChildren: any = {
			UICorner = React.createElement("UICorner", {
				CornerRadius = UDim.new(0, 3),
			}),
			UIStroke = React.createElement("UIStroke", {
				Color = Color3.fromRGB(80, 65, 45),
				Thickness = 1,
			}),
		}

		-- If this is the local player and dropdown is open, show the grid
		if isLocalPlayer and self.state.colorDropdownOpen then
			local rows = math.ceil(#COLOR_OPTIONS / COLOR_COLUMNS)
			local dropdownHeight = rows * (COLOR_SQUARE_SIZE + COLOR_SQUARE_GAP) + COLOR_SQUARE_GAP + 6
			local dropdownWidth = COLOR_COLUMNS * (COLOR_SQUARE_SIZE + COLOR_SQUARE_GAP) + COLOR_SQUARE_GAP + 6

			local gridChildren: any = {}
			for idx, colorOpt in ipairs(COLOR_OPTIONS) do
				local isSelected = isPlayerColor(colorOpt, playerInfo)
				local taken = isColorTaken(colorOpt, playerInfo.userId)
				local col = (idx - 1) % COLOR_COLUMNS
				local row = math.floor((idx - 1) / COLOR_COLUMNS)

				gridChildren["Color" .. idx] = React.createElement("TextButton", {
					Size = UDim2.new(0, COLOR_SQUARE_SIZE, 0, COLOR_SQUARE_SIZE),
					Position = UDim2.new(
						0, COLOR_SQUARE_GAP + col * (COLOR_SQUARE_SIZE + COLOR_SQUARE_GAP),
						0, COLOR_SQUARE_GAP + row * (COLOR_SQUARE_SIZE + COLOR_SQUARE_GAP)
					),
					BackgroundColor3 = Color3.fromRGB(colorOpt.r, colorOpt.g, colorOpt.b),
					BackgroundTransparency = taken and 0.6 or 0,
					BorderSizePixel = 0,
					Text = "",
					AutoButtonColor = not taken,
					ZIndex = 12,
					[React.Event.MouseButton1Click] = function()
						if not taken and onSelectColor then
							onSelectColor({ colorOpt.r, colorOpt.g, colorOpt.b })
							self:setState({ colorDropdownOpen = false })
						end
					end,
				}, {
					UICorner = React.createElement("UICorner", {
						CornerRadius = UDim.new(0, 2),
					}),
					UIStroke = React.createElement("UIStroke", {
						Color = if isSelected
							then Color3.fromRGB(255, 255, 255)
							else Color3.fromRGB(30, 25, 20),
						Thickness = if isSelected then 2 else 0.5,
					}),
					-- Show X on taken colors
					TakenLabel = taken and React.createElement("TextLabel", {
						Size = UDim2.fromScale(1, 1),
						BackgroundTransparency = 1,
						Text = "X",
						TextColor3 = Color3.fromRGB(255, 80, 80),
						TextSize = 12,
						FontFace = UIConfig.Font.Default,
						ZIndex = 13,
					}) or nil,
				})
			end

			colorButtonChildren["Dropdown"] = React.createElement("Frame", {
				Name = "ColorDropdown",
				Size = UDim2.new(0, dropdownWidth, 0, dropdownHeight),
				Position = UDim2.new(0, 0, 1, 4),
				BackgroundColor3 = Color3.fromRGB(35, 30, 25),
				BorderSizePixel = 0,
				ZIndex = 10,
				ClipsDescendants = false,
			}, {
				UICorner = React.createElement("UICorner", {
					CornerRadius = UDim.new(0, 4),
				}),
				UIStroke = React.createElement("UIStroke", {
					Color = Color3.fromRGB(100, 80, 50),
					Thickness = 1.5,
				}),
				Grid = React.createElement("Frame", {
					Size = UDim2.fromScale(1, 1),
					BackgroundTransparency = 1,
					ZIndex = 11,
				}, gridChildren),
			})
		end

		table.insert(
			playerFrameChildren,
			React.createElement("Frame", {
				key = playerInfo.name .. i,
				LayoutOrder = i,
				Size = UDim2.new(1, 0, 0, 36),
				BackgroundColor3 = Color3.fromRGB(40, 40, 40),
				BackgroundTransparency = 0.3,
				BorderSizePixel = 0,
				ClipsDescendants = false,
			}, {
				UIPadding = React.createElement("UIPadding", {
					PaddingTop = UDim.new(0, 4),
					PaddingBottom = UDim.new(0, 4),
					PaddingLeft = UDim.new(0, 8),
					PaddingRight = UDim.new(0, 8),
				}),
				Layout = React.createElement("UIListLayout", {
					FillDirection = Enum.FillDirection.Horizontal,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 6),
				}),
				-- Color button (clickable square showing current color, opens dropdown)
				ColorButton = React.createElement("TextButton", {
					LayoutOrder = 1,
					Size = UDim2.new(0, 24, 0, 24),
					BackgroundColor3 = playerColorDisplay,
					BorderSizePixel = 0,
					Text = "",
					AutoButtonColor = isLocalPlayer,
					ClipsDescendants = false,
					[React.Event.MouseButton1Click] = if isLocalPlayer then function()
						self:setState({ colorDropdownOpen = not self.state.colorDropdownOpen })
					end else nil,
				}, colorButtonChildren),
				-- Player name
				PlayerName = React.createElement("TextLabel", {
					LayoutOrder = 2,
					Text = playerInfo.name .. (playerInfo.isAI and " (AI)" or ""),
					Size = UDim2.new(0, 110, 1, 0),
					FontFace = UIConfig.Font.Default,
					TextColor3 = if isLocalPlayer then Color3.fromRGB(255, 220, 100)
						else lobbyConfig.PlayerListNameColor,
					TextSize = 14,
					BackgroundTransparency = 1,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextTruncate = Enum.TextTruncate.AtEnd,
				}),
				-- Faction selector
				FactionToggle = React.createElement(Toggle, {
					LayoutOrder = 3,
					Size = UDim2.new(1, -270, 1, 0),
					value = playerInfo.faction or "Kingdom",
					options = availableFactions,
					onValueChanged = if onSelectFaction then function(newFaction)
						onSelectFaction(newFaction, playerInfo.userId)
					end else nil,
				}),
				-- Ready status
				ReadyStatus = React.createElement("TextLabel", {
					LayoutOrder = 4,
					Text = if playerInfo.isReady then "Ready" else "Not Ready",
					Size = UDim2.new(0, 65, 1, 0),
					FontFace = UIConfig.Font.Default,
					TextColor3 = if playerInfo.isReady
						then Color3.fromRGB(100, 255, 100)
						else Color3.fromRGB(255, 100, 100),
					TextSize = 12,
					BackgroundTransparency = 1,
					TextXAlignment = Enum.TextXAlignment.Right,
				}),
				-- Remove button (AI only)
				RemoveButton = playerInfo.isAI and Button and React.createElement(Button, {
					LayoutOrder = 5,
					Text = "X",
					Size = UDim2.new(0, 25, 1, 0),
					OnClick = function()
						if onRemovePlayer then
							onRemovePlayer(playerInfo)
						end
					end,
					BackgroundTransparency = 1,
					TextColor3 = Color3.fromRGB(255, 100, 100),
					TextSize = 16,
				}) or nil,
			})
		)
	end

	if #players < 4 and Button then
		table.insert(
			playerFrameChildren,
			React.createElement(Button, {
				key = "AddAIButton",
				LayoutOrder = #players + 1,
				Text = "+ Add AI Opponent",
				Size = UDim2.new(1, 0, 0, 30),
				OnClick = onAddAI,
				BackgroundTransparency = 1,
				TextColor3 = lobbyConfig.AddAIButtonTextColor,
				TextSize = lobbyConfig.AddAIButtonTextSize,
				TextXAlignment = Enum.TextXAlignment.Left,
			})
		)
	end

	return React.createElement("Frame", {
		Name = "PlayerList",
		Size = self.props.Size,
		BackgroundColor3 = lobbyConfig.PanelBackgroundColor,
		BackgroundTransparency = lobbyConfig.PanelBackgroundTransparency,
		LayoutOrder = self.props.LayoutOrder,
		ClipsDescendants = false,
	}, {
		Padding = React.createElement("UIPadding", {
			PaddingTop = paddingConfig.PlayerListContentPadding.Top,
			PaddingBottom = paddingConfig.PlayerListContentPadding.Bottom,
			PaddingLeft = paddingConfig.PlayerListContentPadding.Left,
			PaddingRight = paddingConfig.PlayerListContentPadding.Right,
		}),
		Layout = React.createElement("UIListLayout", {
			Padding = paddingConfig.PlayerListSpacing,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		Title = React.createElement("TextLabel", {
			LayoutOrder = 1,
			Text = "Players",
			Size = UDim2.new(1, 0, 0, 40),
			FontFace = UIConfig.Font.Title,
			TextColor3 = lobbyConfig.PlayerListTitleColor,
			TextSize = lobbyConfig.PlayerListTitleSize,
			BackgroundTransparency = 1,
		}),
		PlayersFrame = React.createElement("Frame", {
			LayoutOrder = 2,
			Size = UDim2.new(1, 0, 1, -45),
			BackgroundTransparency = 1,
			ClipsDescendants = false,
		}, playerFrameChildren),
	})
end

return PlayerList
