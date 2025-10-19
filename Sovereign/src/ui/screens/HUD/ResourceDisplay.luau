local React = require(game.ReplicatedStorage.Packages.react)
local UIConfig = require(script.Parent.Parent.Parent.UIConfig)

local ResourceDisplay = React.Component:extend("ResourceDisplay")

local RESOURCE_ORDER = { "Wood", "Stone", "Food", "Gold", "Weapons", "Iron_Bars" }

local RESOURCE_ICONS = {
	Wood = "🌲",
	Stone = "🪨",
	Gold = "💰",
	Food = "🌾",
	Weapons = "⚔️",
	Iron_Bars = "🔩",
}

function ResourceDisplay:render()
	local resources = self.props.resources or {}

	local resourceElements = {}

	-- Add layout
	resourceElements.Layout = React.createElement("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 20),
	})

	-- Create a display for each resource
	for i, resourceName in ipairs(RESOURCE_ORDER) do
		local amount = resources[resourceName] or 0
		local displayName = resourceName:gsub("_", " ")
		local icon = RESOURCE_ICONS[resourceName] or "📦"

		resourceElements[resourceName] = React.createElement("Frame", {
			Name = resourceName .. "Frame",
			Size = UDim2.new(0, 100, 1, 0),
			BackgroundTransparency = 1,
			LayoutOrder = i,
		}, {
			Layout = React.createElement("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 6),
			}),

			Icon = React.createElement("TextLabel", {
				Size = UDim2.new(0, 24, 0, 24),
				BackgroundTransparency = 1,
				Text = icon,
				Font = Enum.Font.Gotham,
				TextSize = 20,
			}),

			Info = React.createElement("Frame", {
				Size = UDim2.new(1, -30, 1, 0),
				BackgroundTransparency = 1,
			}, {
				Layout = React.createElement("UIListLayout", {
					FillDirection = Enum.FillDirection.Vertical,
					VerticalAlignment = Enum.VerticalAlignment.Center,
				}),

				Name = React.createElement("TextLabel", {
					Size = UDim2.new(1, 0, 0, 14),
					BackgroundTransparency = 1,
					Text = displayName,
					Font = Enum.Font.GothamBold,
					TextSize = 11,
					TextColor3 = Color3.fromRGB(200, 200, 200),
					TextXAlignment = Enum.TextXAlignment.Left,
				}),

				Amount = React.createElement("TextLabel", {
					Size = UDim2.new(1, 0, 0, 18),
					BackgroundTransparency = 1,
					Text = tostring(math.floor(amount)),
					Font = Enum.Font.Gotham,
					TextSize = 16,
					TextColor3 = Color3.fromRGB(255, 255, 255),
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
			}),
		})
	end

	return React.createElement("Frame", {
		Name = "ResourceDisplay",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, resourceElements)
end

return ResourceDisplay
