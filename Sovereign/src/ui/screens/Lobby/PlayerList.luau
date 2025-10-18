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
		Size = UDim2.new(1, 0, 0.3, 0),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.5,
	}, {
		Layout = React.createElement("UIListLayout", {
			Padding = UDim.new(0, 5),
		}),
		Title = React.createElement("TextLabel", {
			Text = "Players",
			Size = UDim2.new(1, 0, 0, 40),
			FontFace = UIConfig.Font.Title,
			TextColor3 = UIConfig.Color.Primary,
			TextSize = 28,
			BackgroundTransparency = 1,
		}),
		Players = React.createElement("Frame", {
			Size = UDim2.new(0.9, 0, 0.7, 0),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
		}, playerElements),
	})
end

return PlayerList
