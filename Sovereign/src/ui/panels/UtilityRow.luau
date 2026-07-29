--!strict
-- UtilityRow: compact icon row that opens the full-screen modals (Policies,
-- Menu, Stats, TechTree, AbilityTree) plus the delete-mode toggle. Docked
-- below the top strip on the LEFT edge -- MiniMap/ViewToggle already own the
-- top-right corner, and anything living inside BottomZone gets covered
-- whenever the drawer/worker-panel/units-panel grows tall, so top-left is the
-- one spot guaranteed clear of both the 60px no-tap zone and the state-driven
-- bottom zone.

local React = require(game.ReplicatedStorage.Packages.react)
local Theme = require(script.Parent.Parent.Theme)

export type Item = {
	key: string,
	icon: string,
	active: boolean,
	onClick: () -> (),
}

export type Props = {
	items: { Item },
}

local function UtilityRow(props: Props)
	local buttons = {}
	buttons.Layout = React.createElement("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, Theme.Metrics.GapTight),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})

	for i, item in props.items do
		buttons[item.key] = React.createElement("TextButton", {
			LayoutOrder = i,
			Size = UDim2.fromOffset(Theme.Metrics.TouchTarget, Theme.Metrics.TouchTarget),
			BackgroundColor3 = item.active and Theme.Color.Accent or Theme.Color.Surface,
			BackgroundTransparency = item.active and Theme.Transparency.CardActive or Theme.Transparency.Panel,
			AutoButtonColor = false,
			Text = item.icon,
			FontFace = Theme.FontFace.Body,
			TextSize = Theme.TextSize.Heading,
			TextColor3 = item.active and Theme.Color.Accent or Theme.Color.TextPrimary,
			[React.Event.Activated] = item.onClick,
		}, {
			Corner = React.createElement("UICorner", { CornerRadius = Theme.corner(Theme.Metrics.RadiusSmall) }),
			Stroke = React.createElement("UIStroke", Theme.strokeProps()),
		})
	end

	return React.createElement("Frame", {
		Name = "UtilityRow",
		Size = UDim2.new(0, 0, 0, Theme.Metrics.TouchTarget),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
	}, buttons)
end

return UtilityRow
