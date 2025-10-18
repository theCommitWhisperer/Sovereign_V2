-- src/ui/components/Row.luau
local React = require(game.ReplicatedStorage.Packages.react)

local Row = React.Component:extend("Row")

function Row:render()
	local props = self.props
	local children = props.children

	local elementsToRender = {
		Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			-- [FIX] This property spreads the items out across the full width
			HorizontalAlignment = Enum.HorizontalAlignment.Spread,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}

	if children then
		for _, child in pairs(children) do
			table.insert(elementsToRender, child)
		end
	end

	return React.createElement("Frame", {
		Name = "Row",
		Size = props.Size or UDim2.new(1, 0, 0, 40),
		LayoutOrder = props.LayoutOrder,
		BackgroundTransparency = 1,
	}, elementsToRender)
end

return Row
