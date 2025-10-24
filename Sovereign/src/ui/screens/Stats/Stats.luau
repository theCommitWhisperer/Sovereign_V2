--!strict
-- Stats modal for displaying kingdom statistics
local React = require(game.ReplicatedStorage.Packages.react)
local Modal = require(script.Parent.Parent.Parent.components.Modal)
local UIConfig = require(script.Parent.Parent.Parent.UIConfig)

local Stats = React.Component:extend("Stats")

export type Props = {
	visible: boolean,
	onClose: () -> (),
	-- Stats data passed from HUD
	population: number?,
	armySize: number?,
	honor: number?,
	glory: number?,
	happiness: number?,
}

-- Stat categories with their display info
local STAT_CATEGORIES = {
	{
		name = "Population",
		icon = "👥",
		key = "population",
		description = "Total population in your kingdom",
	},
	{
		name = "Army Size",
		icon = "⚔️",
		key = "armySize",
		description = "Total military units available",
	},
	{
		name = "Honor",
		icon = "🏆",
		key = "honor",
		description = "Kingdom's honor and reputation",
	},
	{
		name = "Glory",
		icon = "⭐",
		key = "glory",
		description = "Glory from battles and achievements",
	},
	{
		name = "Happiness",
		icon = "😊",
		key = "happiness",
		description = "Overall happiness of your people",
	},
}

function Stats:render()
	local statBoxes = {}

	statBoxes.Layout = React.createElement("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		Padding = UDim.new(0, 15),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
	})

	-- Create stat box for each category
	for i, stat in ipairs(STAT_CATEGORIES) do
		local value = self.props[stat.key] or 0

		statBoxes[stat.key] = React.createElement("Frame", {
			Size = UDim2.new(0.9, 0, 0, 100),
			BackgroundColor3 = UIConfig.HUD.UtilityButtonBackground,
			BorderSizePixel = 2,
			BorderColor3 = UIConfig.HUD.UtilityButtonBorder,
			LayoutOrder = i,
		}, {
			Padding = React.createElement("UIPadding", {
				PaddingTop = UDim.new(0, 15),
				PaddingBottom = UDim.new(0, 15),
				PaddingLeft = UDim.new(0, 20),
				PaddingRight = UDim.new(0, 20),
			}),

			Layout = React.createElement("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 15),
			}),

			-- Icon
			Icon = React.createElement("TextLabel", {
				Size = UDim2.new(0, 50, 1, 0),
				BackgroundTransparency = 1,
				Text = stat.icon,
				Font = Enum.Font.GothamBold,
				TextSize = 36,
				TextXAlignment = Enum.TextXAlignment.Center,
			}),

			-- Info section
			Info = React.createElement("Frame", {
				Size = UDim2.new(1, -65, 1, 0),
				BackgroundTransparency = 1,
			}, {
				Layout = React.createElement("UIListLayout", {
					FillDirection = Enum.FillDirection.Vertical,
					Padding = UDim.new(0, 5),
				}),

				-- Stat name
				Name = React.createElement("TextLabel", {
					Size = UDim2.new(1, 0, 0, 25),
					BackgroundTransparency = 1,
					Text = stat.name,
					Font = Enum.Font.GothamBold,
					TextSize = 20,
					TextColor3 = UIConfig.HUD.PanelHeaderColor,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),

				-- Value
				Value = React.createElement("TextLabel", {
					Size = UDim2.new(1, 0, 0, 30),
					BackgroundTransparency = 1,
					Text = tostring(value),
					Font = Enum.Font.GothamBold,
					TextSize = 28,
					TextColor3 = UIConfig.HUD.CategoryButtonSelected, -- Use Whiskey color
					TextXAlignment = Enum.TextXAlignment.Left,
				}),

				-- Description
				Description = React.createElement("TextLabel", {
					Size = UDim2.new(1, 0, 0, 20),
					BackgroundTransparency = 1,
					Text = stat.description,
					Font = Enum.Font.Gotham,
					TextSize = 14,
					TextColor3 = UIConfig.HUD.PanelTextColor,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextWrapped = true,
				}),
			}),
		})
	end

	return React.createElement(Modal, {
		title = "Kingdom Statistics",
		visible = self.props.visible,
		onClose = self.props.onClose,
	}, {
		StatBoxes = React.createElement("Frame", {
			Size = UDim2.new(1, 0, 0, 0),
			BackgroundTransparency = 1,
			AutomaticSize = Enum.AutomaticSize.Y,
		}, statBoxes),
	})
end

return Stats
