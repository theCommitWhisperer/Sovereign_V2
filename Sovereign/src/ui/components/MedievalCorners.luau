-- MedievalCorners: Decorative corner accents for medieval styling
local React = require(game.ReplicatedStorage.Packages.react)
local UIConfig = require(script.Parent.Parent.UIConfig)

local MedievalCorners = React.Component:extend("MedievalCorners")

function MedievalCorners:render()
	local size = self.props.size or 12
	local color = self.props.color or UIConfig.HUD.AccentGold
	local thickness = self.props.thickness or 2

	return React.createElement(React.Fragment, nil, {
		TopLeft = React.createElement("Frame", {
			Name = "TopLeftCorner",
			Size = UDim2.new(0, size, 0, size),
			Position = UDim2.new(0, 0, 0, 0),
			BackgroundTransparency = 1,
			ZIndex = 10,
		}, {
			Horizontal = React.createElement("Frame", {
				Size = UDim2.new(1, 0, 0, thickness),
				Position = UDim2.new(0, 0, 0, 0),
				BackgroundColor3 = color,
				BorderSizePixel = 0,
			}),
			Vertical = React.createElement("Frame", {
				Size = UDim2.new(0, thickness, 1, 0),
				Position = UDim2.new(0, 0, 0, 0),
				BackgroundColor3 = color,
				BorderSizePixel = 0,
			}),
		}),

		TopRight = React.createElement("Frame", {
			Name = "TopRightCorner",
			Size = UDim2.new(0, size, 0, size),
			Position = UDim2.new(1, -size, 0, 0),
			BackgroundTransparency = 1,
			ZIndex = 10,
		}, {
			Horizontal = React.createElement("Frame", {
				Size = UDim2.new(1, 0, 0, thickness),
				Position = UDim2.new(0, 0, 0, 0),
				BackgroundColor3 = color,
				BorderSizePixel = 0,
			}),
			Vertical = React.createElement("Frame", {
				Size = UDim2.new(0, thickness, 1, 0),
				Position = UDim2.new(1, -thickness, 0, 0),
				BackgroundColor3 = color,
				BorderSizePixel = 0,
			}),
		}),

		BottomLeft = React.createElement("Frame", {
			Name = "BottomLeftCorner",
			Size = UDim2.new(0, size, 0, size),
			Position = UDim2.new(0, 0, 1, -size),
			BackgroundTransparency = 1,
			ZIndex = 10,
		}, {
			Horizontal = React.createElement("Frame", {
				Size = UDim2.new(1, 0, 0, thickness),
				Position = UDim2.new(0, 0, 1, -thickness),
				BackgroundColor3 = color,
				BorderSizePixel = 0,
			}),
			Vertical = React.createElement("Frame", {
				Size = UDim2.new(0, thickness, 1, 0),
				Position = UDim2.new(0, 0, 0, 0),
				BackgroundColor3 = color,
				BorderSizePixel = 0,
			}),
		}),

		BottomRight = React.createElement("Frame", {
			Name = "BottomRightCorner",
			Size = UDim2.new(0, size, 0, size),
			Position = UDim2.new(1, -size, 1, -size),
			BackgroundTransparency = 1,
			ZIndex = 10,
		}, {
			Horizontal = React.createElement("Frame", {
				Size = UDim2.new(1, 0, 0, thickness),
				Position = UDim2.new(0, 0, 1, -thickness),
				BackgroundColor3 = color,
				BorderSizePixel = 0,
			}),
			Vertical = React.createElement("Frame", {
				Size = UDim2.new(0, thickness, 1, 0),
				Position = UDim2.new(1, -thickness, 0, 0),
				BackgroundColor3 = color,
				BorderSizePixel = 0,
			}),
		}),
	})
end

return MedievalCorners
