-- Shows a preview of the selected map in the lobby.
local React = require(game.ReplicatedStorage.Packages.react)
local UIConfig = require(script.Parent.Parent.Parent.UIConfig)

local MapPreview = React.Component:extend("MapPreview")

function MapPreview:render()
	local mapName = self.props.mapName

	return React.createElement("Frame", {
		Name = "MapPreview",
		Size = UDim2.new(1, 0, 0.6, 0),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
	}, {
		Image = React.createElement("ImageLabel", {
			Size = UDim2.fromScale(1, 1),
			Image = "rbxassetid://97541657322605", -- Placeholder map image
			ScaleType = Enum.ScaleType.Fit,
		}),
		Title = React.createElement("TextLabel", {
			Text = mapName,
			Size = UDim2.new(1, 0, 0.2, 0),
			Position = UDim2.fromScale(0, 0.8),
			FontFace = UIConfig.Font.Title,
			TextColor3 = UIConfig.Color.Primary,
			TextSize = 28,
			BackgroundTransparency = 0.5,
			BackgroundColor3 = Color3.new(0, 0, 0),
		}),
	})
end

return MapPreview
