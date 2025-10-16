local React = require(game.ReplicatedStorage.Packages.react)
local UIConfig = require(script.Parent.Parent.Parent.UIConfig)

local Textbox = React.Component:extend("Textbox")

function Textbox:render()
	return React.createElement("Frame", {
		Size = self.props.Size or UDim2.new(1, 0, 0, 40),
		LayoutOrder = self.props.LayoutOrder,
		BackgroundTransparency = 1,
	}, {
		Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 10),
		}),
		-- Input is now first to appear on the left.
		Input = React.createElement("TextBox", {
			Size = UDim2.new(0.3, 0, 1, 0),
			Text = self.props.defaultText or "",
			TextSize = 24,
			Font = Enum.Font.SourceSans,
			TextColor3 = UIConfig.Color.Primary,
			BackgroundColor3 = UIConfig.Color.Background,
			BackgroundTransparency = 0.5,
			BorderSizePixel = 0,
			[React.Event.FocusLost] = function(rbx)
				if self.props.onTextChanged then
					self.props.onTextChanged(rbx.Text)
				end
			end,
		}),
		-- Label is second to appear on the right.
		Label = React.createElement("TextLabel", {
			Text = self.props.Label,
			Size = UDim2.new(0.7, 0, 1, 0),
			TextSize = 24,
			FontFace = UIConfig.Font.Default,
			TextColor3 = UIConfig.Color.Primary, -- Use white text
			BackgroundTransparency = 1,
			TextXAlignment = Enum.TextXAlignment.Right,
		}),
	})
end

return Textbox
