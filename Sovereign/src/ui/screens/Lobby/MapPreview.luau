-- Shows a preview of the selected map in the lobby.
local React = require(game.ReplicatedStorage.Packages.react)
local UIConfig = require(script.Parent.Parent.Parent.UIConfig)

local MapPreview = React.Component:extend("MapPreview")

function MapPreview:render()
	local mapName = self.props.mapName
	local lobbyConfig = UIConfig.LobbyPage

	return React.createElement("Frame", {
		Name = "MapPreview",
		Size = self.props.Size or UDim2.new(1, 0, 0.6, 0),
		BackgroundColor3 = lobbyConfig.PanelBackgroundColor,
		BackgroundTransparency = lobbyConfig.PanelBackgroundTransparency,
		BorderSizePixel = 0,
	}, {
		-- A simple frame instead of an image for a cleaner look
		PreviewArea = React.createElement("Frame", {
			Size = UDim2.fromScale(0.9, 0.9),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Color3.new(0.1, 0.1, 0.1),
			BackgroundTransparency = 0.5,
		}),
		Title = React.createElement("TextLabel", {
			Text = "Map Preview",
			Size = UDim2.new(1, 0, 0, 40),
			Position = UDim2.fromScale(0.5, 0),
			AnchorPoint = Vector2.new(0.5, 0),
			FontFace = UIConfig.Font.Title,
			TextColor3 = lobbyConfig.MapPreviewTitleColor,
			TextSize = lobbyConfig.MapPreviewTitleSize,
			BackgroundTransparency = 1,
		}),
		MapName = React.createElement("TextLabel", {
			Text = mapName,
			Size = UDim2.new(1, 0, 0, 30),
			Position = UDim2.fromScale(0.5, 1),
			AnchorPoint = Vector2.new(0.5, 1),
			FontFace = UIConfig.Font.Default,
			TextColor3 = lobbyConfig.MapNameColor,
			TextSize = lobbyConfig.MapNameSize,
			BackgroundTransparency = 0.5,
			BackgroundColor3 = UIConfig.Color.Background,
		}),
	})
end

return MapPreview
