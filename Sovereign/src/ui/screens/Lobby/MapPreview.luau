-- In thecommitwhisperer/sovereign_v2/Sovereign_V2-2a7f9b1a80569056b2a17430b670ecd3e29324fa/Sovereign/src/ui/screens/Lobby/MapPreview.luau
-- Shows a preview of the selected map in the lobby.
local React = require(game.ReplicatedStorage.Packages.react)
local UIConfig = require(script.Parent.Parent.Parent.UIConfig)

local MapPreview = React.Component:extend("MapPreview")

function MapPreview:render()
	local mapName = self.props.mapName

	return React.createElement("Frame", {
		Name = "MapPreview",
		Size = self.props.Size or UDim2.new(1, 0, 0.6, 0),
		BackgroundColor3 = UIConfig.Color.Background,
		BackgroundTransparency = 0.7,
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
			TextColor3 = UIConfig.Color.Primary,
			TextSize = 28,
			BackgroundTransparency = 1,
		}),
		MapName = React.createElement("TextLabel", {
			Text = mapName,
			Size = UDim2.new(1, 0, 0, 30),
			Position = UDim2.fromScale(0.5, 1),
			AnchorPoint = Vector2.new(0.5, 1),
			FontFace = UIConfig.Font.Default,
			TextColor3 = UIConfig.Color.Primary,
			TextSize = 24,
			BackgroundTransparency = 0.5,
			BackgroundColor3 = UIConfig.Color.Background,
		}),
	})
end

return MapPreview
