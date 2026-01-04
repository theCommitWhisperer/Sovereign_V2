-- thecommitwhisperer/sovereign_v2/Sovereign_V2-a5a2c87f4791d0aeedd3f50cf8nde31685a4f9fb/Sovereign/src/ui/screens/Lobby/PlayerList.luau
local React = require(game.ReplicatedStorage.Packages.react)
local UIConfig = require(script.Parent.Parent.Parent.UIConfig)
local Toggle = require(script.Parent.Parent.Parent.components.Toggle)

local PlayerList = React.Component:extend("PlayerList")

local FACTIONS = { "Kingdom", "Empire", "Tribes", "IronLegion" }

function PlayerList:render()
	local players = self.props.players or {}
	local onAddAI = self.props.onAddAI
	local onRemovePlayer = self.props.onRemovePlayer
	local onSelectFaction = self.props.onSelectFaction
	local localPlayerId = self.props.localPlayerId
	local Button = self.props.Button
	local lobbyConfig = UIConfig.LobbyPage
	local paddingConfig = lobbyConfig.Padding

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

		-- Filter available factions (exclude taken ones, except the player's current faction)
		local availableFactions = {}
		for _, faction in ipairs(FACTIONS) do
			local isTaken = isFactionTaken(faction, playerInfo.userId)
			if not isTaken or playerInfo.faction == faction then
				table.insert(availableFactions, faction)
			end
		end

		-- If no faction selected and all are taken, still show all factions (shouldn't happen)
		if #availableFactions == 0 then
			availableFactions = FACTIONS
		end

		table.insert(
			playerFrameChildren,
			React.createElement("Frame", {
				key = playerInfo.name .. i,
				LayoutOrder = i,
				Size = UDim2.new(1, 0, 0, 35),
				BackgroundColor3 = Color3.fromRGB(40, 40, 40),
				BackgroundTransparency = 0.3,
				BorderSizePixel = 0,
			}, {
				UIPadding = React.createElement("UIPadding", {
					PaddingTop = UDim.new(0, 5),
					PaddingBottom = UDim.new(0, 5),
					PaddingLeft = UDim.new(0, 8),
					PaddingRight = UDim.new(0, 8),
				}),
				Layout = React.createElement("UIListLayout", {
					FillDirection = Enum.FillDirection.Horizontal,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 8),
				}),
				-- Player name
				PlayerName = React.createElement("TextLabel", {
					LayoutOrder = 1,
					Text = playerInfo.name .. (playerInfo.isAI and " (AI)" or ""),
					Size = UDim2.new(0, 150, 1, 0),
					FontFace = UIConfig.Font.Default,
					TextColor3 = if isLocalPlayer then Color3.fromRGB(255, 220, 100)
						else lobbyConfig.PlayerListNameColor,
					TextSize = 16,
					BackgroundTransparency = 1,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				-- Faction selector
				FactionToggle = React.createElement(Toggle, {
					LayoutOrder = 2,
					Size = UDim2.new(1, -280, 1, 0),
					value = playerInfo.faction or "Kingdom",
					options = availableFactions,
					onValueChanged = if onSelectFaction then function(newFaction)
						onSelectFaction(newFaction, playerInfo.userId)
					end else nil,
				}),
				-- Ready status
				ReadyStatus = React.createElement("TextLabel", {
					LayoutOrder = 3,
					Text = if playerInfo.isReady then "✓ Ready" else "✗ Not Ready",
					Size = UDim2.new(0, 90, 1, 0),
					FontFace = UIConfig.Font.Default,
					TextColor3 = if playerInfo.isReady
						then Color3.fromRGB(100, 255, 100)
						else Color3.fromRGB(255, 100, 100),
					TextSize = 14,
					BackgroundTransparency = 1,
					TextXAlignment = Enum.TextXAlignment.Right,
				}),
				-- Remove button (AI only)
				RemoveButton = playerInfo.isAI and Button and React.createElement(Button, {
					LayoutOrder = 4,
					Text = "✕",
					Size = UDim2.new(0, 30, 1, 0),
					OnClick = function()
						if onRemovePlayer then
							onRemovePlayer(playerInfo)
						end
					end,
					BackgroundTransparency = 1,
					TextColor3 = Color3.fromRGB(255, 100, 100),
					TextSize = 18,
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
		Size = self.props.Size, -- Use the size passed in from props
		BackgroundColor3 = lobbyConfig.PanelBackgroundColor,
		BackgroundTransparency = lobbyConfig.PanelBackgroundTransparency,
		LayoutOrder = self.props.LayoutOrder,
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
		}, playerFrameChildren),
	})
end

return PlayerList
