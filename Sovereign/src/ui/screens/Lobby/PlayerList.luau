-- Lists players in the current lobby.
local React = require(game.ReplicatedStorage.Packages.react)
local UIConfig = require(script.Parent.Parent.Parent.UIConfig)

local PlayerList = React.Component:extend("PlayerList")

function PlayerList:render()
	local players = self.props.players or {}
	local playerElements = {}

	for i, playerInfo in ipairs(players) do
		playerElements["Player" .. i] = React.createElement("TextLabel", {
			Text = playerInfo.name .. (playerInfo.isAI and " (AI)" or ""),
			Size = UDim2.new(1, 0, 0, 30),
			FontFace = UIConfig.Font.Default,
			TextColor3 = UIConfig.Color.Primary,
			TextSize = 22,
			BackgroundTransparency = 1,
			TextXAlignment = Enum.TextXAlignment.Left,
		})
	end

	return React.createElement("Frame", {
		Name = "PlayerList",
		Size = self.props.Size or UDim2.new(1, 0, 0.3, 0),
		BackgroundColor3 = UIConfig.Color.Background,
		BackgroundTransparency = 0.7,
		LayoutOrder = self.props.LayoutOrder,
	}, {
		Padding = React.createElement("UIPadding", {
			PaddingTop = UDim.new(0, 10),
			PaddingBottom = UDim.new(0, 10),
			PaddingLeft = UDim.new(0, 15),
			PaddingRight = UDim.new(0, 15),
		}),
		Layout = React.createElement("UIListLayout", {
			Padding = UDim.new(0, 5),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		Title = React.createElement("TextLabel", {
			LayoutOrder = 1,
			Text = "Players",
			Size = UDim2.new(1, 0, 0, 40),
			FontFace = UIConfig.Font.Title,
			TextColor3 = UIConfig.Color.Primary,
			TextSize = 28,
			BackgroundTransparency = 1,
		}),
		-- This is the corrected part. The playerElements table is now a direct child.
		Players = React.createElement("Frame", {
			LayoutOrder = 2,
			Size = UDim2.new(1, 0, 1, -45),
			BackgroundTransparency = 1,
		}, playerElements), -- The fix is here!
	})
end

return PlayerList
