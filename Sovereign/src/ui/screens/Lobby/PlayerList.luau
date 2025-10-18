local React = require(game.ReplicatedStorage.Packages.react)
local UIConfig = require(script.Parent.Parent.Parent.UIConfig)

local PlayerList = React.Component:extend("PlayerList")

function PlayerList:render()
	local players = self.props.players or {}
	local lobbyConfig = UIConfig.LobbyPage
	local paddingConfig = lobbyConfig.Padding

	-- Create a table to hold the children for the player list frame
	local playerFrameChildren = {
		Layout = React.createElement("UIListLayout", {
			Padding = paddingConfig.PlayerListSpacing,
		}),
	}

	-- Create an element for each player and add it to the children table
	for i, playerInfo in ipairs(players) do
		table.insert(
			playerFrameChildren,
			React.createElement("TextLabel", {
				key = playerInfo.name .. i, -- Add a unique key for list items
				Text = playerInfo.name .. (playerInfo.isAI and " (AI)" or ""),
				Size = UDim2.new(1, 0, 0, 30),
				FontFace = UIConfig.Font.Default,
				TextColor3 = lobbyConfig.PlayerListNameColor,
				TextSize = lobbyConfig.PlayerListNameSize,
				BackgroundTransparency = 1,
				TextXAlignment = Enum.TextXAlignment.Left,
			})
		)
	end

	return React.createElement("Frame", {
		Name = "PlayerList",
		Size = self.props.Size or UDim2.new(1, 0, 0.3, 0),
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
		}, playerFrameChildren), -- Pass the correctly structured children table here
	})
end

return PlayerList
