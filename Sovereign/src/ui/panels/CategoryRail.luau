--!strict
-- CategoryRail: the idle-state bottom strip -- one row of category buttons.
-- Stays on screen under the BuildDrawer too (see MobileShell's bottom-zone
-- composition): closing the drawer needs a still-visible rail to close it FROM.

local React = require(game.ReplicatedStorage.Packages.react)
local Theme = require(script.Parent.Parent.Theme)
local BuildingCatalog = require(script.Parent.Parent.BuildingCatalog)

export type Props = {
	categories: { string },
	-- nil when no category is open (idle); otherwise the open category, so the
	-- rail can gold-highlight the tab that owns the currently open drawer.
	activeCategory: string?,
	onSelect: (string) -> (),
	LayoutOrder: number?,
}

-- Wide enough for an icon glyph plus an 8-character category name at Body size
-- without truncating, tall enough to clear TouchTarget with room for the label.
local BUTTON_WIDTH = Theme.Metrics.TouchTarget * 1.6

local function CategoryRail(props: Props)
	local buttons = {}
	buttons.Layout = React.createElement("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, Theme.Metrics.Gap),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})

	for i, category in props.categories do
		local isActive = props.activeCategory == category
		buttons[category] = React.createElement("TextButton", {
			Name = category .. "Button",
			LayoutOrder = i,
			Size = UDim2.fromOffset(BUTTON_WIDTH, Theme.Metrics.CategoryRailHeight),
			BackgroundColor3 = isActive and Theme.Color.Accent or Theme.Color.SurfaceRaised,
			BackgroundTransparency = isActive and Theme.Transparency.CardActive or Theme.Transparency.Card,
			AutoButtonColor = false,
			BorderSizePixel = 0,
			Text = "",
			[React.Event.Activated] = function()
				props.onSelect(category)
			end,
		}, {
			Corner = React.createElement("UICorner", { CornerRadius = Theme.corner(Theme.Metrics.RadiusSmall) }),
			Stroke = React.createElement("UIStroke", isActive and {
				Color = Theme.Color.Accent,
				Transparency = Theme.Transparency.BorderStrong,
				Thickness = 1.5,
			} or Theme.strokeProps()),
			Layout = React.createElement("UIListLayout", {
				FillDirection = Enum.FillDirection.Vertical,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, Theme.Metrics.GapTight),
			}),
			Icon = React.createElement("TextLabel", {
				LayoutOrder = 1,
				Size = UDim2.new(1, 0, 0, 18),
				BackgroundTransparency = 1,
				Text = BuildingCatalog.getCategoryIcon(category),
				Font = Theme.Font.Body,
				TextSize = Theme.TextSize.Heading,
				TextColor3 = isActive and Theme.Color.Accent or Theme.Color.TextPrimary,
			}),
			Label = React.createElement("TextLabel", {
				LayoutOrder = 2,
				Size = UDim2.new(1, -4, 0, 14),
				BackgroundTransparency = 1,
				Text = category,
				Font = Theme.Font.Body,
				TextSize = Theme.TextSize.Caption,
				TextColor3 = isActive and Theme.Color.Accent or Theme.Color.TextSecondary,
				TextTruncate = Enum.TextTruncate.AtEnd,
			}),
		})
	end

	return React.createElement("ScrollingFrame", {
		Name = "CategoryRail",
		LayoutOrder = props.LayoutOrder,
		Size = UDim2.new(1, 0, 0, Theme.Metrics.CategoryRailHeight),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollingDirection = Enum.ScrollingDirection.X,
		ScrollBarThickness = 0,
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		CanvasSize = UDim2.fromScale(0, 0),
	}, buttons)
end

return CategoryRail
