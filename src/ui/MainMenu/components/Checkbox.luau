local React = require(game.ReplicatedStorage.Packages.react)
local UIConfig = require(script.Parent.Parent.Parent.UIConfig)

local Checkbox = React.Component:extend("Checkbox")

function Checkbox:init()
	self:setState({ checked = self.props.defaultChecked or false })
end

function Checkbox:render()
	return React.createElement("TextButton", {
		Size = self.props.Size or UDim2.new(1, 0, 0, 30),
		LayoutOrder = self.props.LayoutOrder,
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		[React.Event.MouseButton1Click] = function()
			self:setState({ checked = not self.state.checked })
			if self.props.onValueChanged then
				self.props.onValueChanged(not self.state.checked)
			end
		end,
	}, {
		Box = React.createElement("Frame", {
			Size = UDim2.new(0, 24, 0, 24),
			Position = UDim2.new(0, 0, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			BackgroundColor3 = UIConfig.Color.Secondary,
			BorderSizePixel = 0,
		}, {
			Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 4) }),
			Check = self.state.checked and React.createElement("Frame", {
				Size = UDim2.new(0.7, 0, 0.7, 0),
				Position = UDim2.new(0.5, 0, 0.5, 0),
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = UIConfig.Color.Primary,
			}) or nil,
		}),
		Label = React.createElement("TextLabel", {
			Text = self.props.Text,
			Size = UDim2.new(1, -30, 1, 0),
			Position = UDim2.new(0, 30, 0, 0),
			TextSize = 24,
			FontFace = UIConfig.Font.Default,
			TextXAlignment = Enum.TextXAlignment.Left,
			BackgroundTransparency = 1,
			TextColor3 = UIConfig.Color.Primary, -- Changed from black to white
		}),
	})
end

return Checkbox
