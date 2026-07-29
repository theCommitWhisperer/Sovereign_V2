local React = require(game.ReplicatedStorage.Packages.react)
local UIConfig = require(script.Parent.Parent.Parent.UIConfig)
local Platform = require(script.Parent.Parent.Parent.Platform)

local ResourceDisplay = React.Component:extend("ResourceDisplay")

-- Stronghold-style resource order: HONOR | JUNK/ISO | GOLD | FOOD | POP | 3x6
local RESOURCE_ORDER = { "Gold", "Food", "Wood", "Stone", "Weapons", "Iron_Bars" }

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
	-- Desktop's fontScale/padding tokens equal the numbers this component
	-- always hardcoded (1.0 / 8px), so routing through Platform.tokens is a
	-- no-op there; Mobile is the only device where these actually move. See
	-- Platform.luau's comment on why Desktop values mirror the old constants.
	local tokens = Platform.tokens
	local iconSize = UIConfig.HUD.ResourceIconSize * tokens.fontScale

	local resourceElements = {}

	-- Add layout
	resourceElements.Layout = React.createElement("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, tokens.padding),
	})

	-- Create a display for each resource
	for i, resourceName in ipairs(RESOURCE_ORDER) do
		local amount = resources[resourceName] or 0
		local displayName = resourceName:gsub("_", " ")
		local icon = RESOURCE_ICONS[resourceName] or "📦"

		resourceElements[resourceName] = React.createElement("Frame", {
			Name = resourceName .. "Frame",
			Size = UDim2.new(0, 85 * tokens.fontScale, 1, -6),
			BackgroundColor3 = UIConfig.HUD.ResourceBackgroundColor,
			BorderSizePixel = 0,
			LayoutOrder = i,
		}, {
			Border = React.createElement("UIStroke", {
				Color = UIConfig.HUD.ResourceBorderColor,
				Thickness = UIConfig.HUD.BorderThickness,
			}),

			Padding = React.createElement("UIPadding", {
				PaddingTop = UDim.new(0, 3),
				PaddingBottom = UDim.new(0, 3),
				PaddingLeft = UDim.new(0, 5),
				PaddingRight = UDim.new(0, 5),
			}),

			Layout = React.createElement("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 4),
			}),

			Icon = React.createElement("TextLabel", {
				Size = UDim2.new(0, iconSize, 0, iconSize),
				BackgroundTransparency = 1,
				Text = icon,
				FontFace = UIConfig.Font.Default,
				TextSize = 16 * tokens.fontScale,
			}),

			Amount = React.createElement("TextLabel", {
				Size = UDim2.new(1, -(iconSize + 4), 1, 0),
				BackgroundTransparency = 1,
				Text = tostring(math.floor(amount)),
				FontFace = UIConfig.Font.Title,
				TextSize = 14 * tokens.fontScale,
				TextColor3 = UIConfig.HUD.ResourceTextColor,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Center,
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
