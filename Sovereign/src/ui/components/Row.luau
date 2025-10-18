-- A component that displays a label and a control in a single row.
local React = require(game.ReplicatedStorage.Packages.react)
local UIConfig = require(script.Parent.Parent.UIConfig)

local Row = React.Component:extend("Row")

function Row:render()
	return React.createElement("Frame", {
		Name = "Row",
		Size = self.props.Size or UDim2.new(1, 0, 0, 30),
		BackgroundTransparency = 1,
		LayoutOrder = self.props.LayoutOrder,
	}, {
		Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 10),
			SortOrder = Enum.SortOrder.LayoutOrder, -- This tells the layout to respect order
		}),
		Label = React.createElement("TextLabel", {
			LayoutOrder = 1, -- The label is now explicitly first
			Name = "Label",
			Text = self.props.Label,
			Size = UDim2.new(0.5, -5, 1, 0),
			FontFace = UIConfig.Font.Default,
			TextColor3 = self.props.TextColor3 or UIConfig.Color.Primary, -- Use prop or default
			TextSize = self.props.TextSize or 22, -- Use prop or default
			BackgroundTransparency = 1,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		ControlContainer = React.createElement("Frame", {
			LayoutOrder = 2, -- The control is now explicitly second
			Name = "ControlContainer",
			Size = UDim2.new(0.5, -5, 1, 0),
			BackgroundTransparency = 1,
		}, self.props.children),
	})
end

return Row
