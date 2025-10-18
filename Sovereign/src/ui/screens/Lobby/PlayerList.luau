-- thecommitwhisperer/sovereign_v2/Sovereign_V2-a5a2c87f4791d0aeedd3f50cf8nde31685a4f9fb/Sovereign/src/ui/screens/Lobby/PlayerList.luau
local React = require(game.ReplicatedStorage.Packages.react)
local UIConfig = require(script.Parent.Parent.Parent.UIConfig)

local PlayerList = React.Component:extend("PlayerList")

function PlayerList:render()
	local players = self.props.players or {}
	local onAddAI = self.props.onAddAI
	local onRemovePlayer = self.props.onRemovePlayer
	local Button = self.props.Button
	local lobbyConfig = UIConfig.LobbyPage
	local paddingConfig = lobbyConfig.Padding

	local playerFrameChildren = {
		Layout = React.createElement("UIListLayout", {
			Padding = paddingConfig.PlayerListSpacing,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}

	for i, playerInfo in ipairs(players) do
		table.insert(
			playerFrameChildren,
			React.createElement("Frame", {
				key = playerInfo.name .. i,
				LayoutOrder = i,
				Size = UDim2.new(1, 0, 0, 30),
				BackgroundTransparency = 1,
			}, {
				Layout = React.createElement("UIListLayout", {
					FillDirection = Enum.FillDirection.Horizontal,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
				PlayerName = React.createElement("TextLabel", {
					LayoutOrder = 1,
					Text = playerInfo.name .. (playerInfo.isAI and " (AI)" or ""),
					Size = UDim2.new(0.8, 0, 1, 0),
					FontFace = UIConfig.Font.Default,
					TextColor3 = lobbyConfig.PlayerListNameColor,
					TextSize = lobbyConfig.PlayerListNameSize,
					BackgroundTransparency = 1,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				RemoveButton = playerInfo.isAI and Button and React.createElement(Button, {
					LayoutOrder = 2,
					Text = "X",
					Size = UDim2.new(0.2, 0, 1, 0),
					OnClick = function()
						if onRemovePlayer then
							onRemovePlayer(playerInfo)
						end
					end,
					BackgroundTransparency = 1,
					TextColor3 = lobbyConfig.RemoveButtonTextColor,
					TextSize = lobbyConfig.RemoveButtonTextSize,
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
