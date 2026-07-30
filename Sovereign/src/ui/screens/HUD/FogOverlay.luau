--!strict
-- FogOverlay: Simple fog of war status indicator

local React = require(game.ReplicatedStorage.Packages.react)

local FogOverlay = React.Component:extend("FogOverlay")

function FogOverlay:render()
	-- Simple "FOG OF WAR" indicator at top of screen
	return React.createElement("TextLabel", {
		Name = "FogIndicator",
		Size = UDim2.new(0, 180, 0, 25),
		Position = UDim2.new(0.5, -90, 0, 45),  -- Below resource bar
		BackgroundTransparency = 0.3,
		BackgroundColor3 = Color3.fromRGB(10, 10, 30),
		BorderSizePixel = 1,
		BorderColor3 = Color3.fromRGB(100, 100, 150),
		Text = "FOG OF WAR",
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		TextColor3 = Color3.fromRGB(150, 200, 255),
		ZIndex = 100,
	}, {
		Corner = React.createElement("UICorner", {
			CornerRadius = UDim.new(0, 4),
		}),
		Stroke = React.createElement("UIStroke", {
			Color = Color3.fromRGB(100, 150, 200),
			Transparency = 0.5,
			Thickness = 1,
		}),
	})
end

return FogOverlay
