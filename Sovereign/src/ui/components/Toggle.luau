-- A reusable component for toggling between true and false.
local React = require(game.ReplicatedStorage.Packages.react)
local UIConfig = require(script.Parent.Parent.UIConfig)

local Toggle = React.Component:extend("Toggle")

function Toggle:render()
	local value = self.props.value
	local onValueChanged = self.props.onValueChanged

	return React.createElement("Frame", {
		Name = "Toggle",
		Size = self.props.Size or UDim2.new(0, 250, 0, 24),
		Position = self.props.Position,
		AnchorPoint = self.props.AnchorPoint,
		LayoutOrder = self.props.LayoutOrder,
		BackgroundTransparency = 1,
	}, {
		-- [FIX] Manually positioning elements instead of using UIListLayout

		-- Left Arrow Button
		LeftArrow = React.createElement("TextButton", {
			Name = "LeftArrow",
			Size = UDim2.new(0, 24, 0, 24),
			Position = UDim2.fromScale(0, 0.5), -- Positioned at the far left
			AnchorPoint = Vector2.new(0, 0.5),
			Text = "<",
			FontFace = UIConfig.Font.Default,
			TextColor3 = UIConfig.Color.Primary,
			TextSize = 24,
			BackgroundTransparency = 1,
			[React.Event.MouseButton1Click] = function()
				if onValueChanged then
					onValueChanged(not value)
				end
			end,
		}),

		-- Text Label for the current value
		ValueLabel = React.createElement("TextLabel", {
			Name = "ValueLabel",
			Size = UDim2.fromScale(1, 1), -- Fills the entire frame
			Position = UDim2.fromScale(0.5, 0.5), -- Centered in the frame
			AnchorPoint = Vector2.new(0.5, 0.5),
			Text = tostring(value):sub(1, 1):upper() .. tostring(value):sub(2),
			FontFace = UIConfig.Font.Default,
			TextColor3 = UIConfig.Color.Primary,
			TextSize = 24,
			BackgroundTransparency = 1,
		}),

		-- Right Arrow Button
		RightArrow = React.createElement("TextButton", {
			Name = "RightArrow",
			Size = UDim2.new(0, 24, 0, 24),
			Position = UDim2.fromScale(1, 0.5), -- Positioned at the far right
			AnchorPoint = Vector2.new(1, 0.5),
			Text = ">",
			FontFace = UIConfig.Font.Default,
			TextColor3 = UIConfig.Color.Primary,
			TextSize = 24,
			BackgroundTransparency = 1,
			[React.Event.MouseButton1Click] = function()
				if onValueChanged then
					onValueChanged(not value)
				end
			end,
		}),
	})
end

return Toggle
