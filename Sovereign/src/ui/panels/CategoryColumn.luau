--!strict
-- CategoryColumn: vertical column of building category buttons (Food, Industry, Military, Defense, Housing, Prestige).
-- Buttons automatically shrink horizontally to snugly hug readable 13px text labels with zero empty space.

local React = require(game.ReplicatedStorage.Packages.react)

local Theme = require(script.Parent.Parent.Theme)
local BuildingCatalog = require(script.Parent.Parent.BuildingCatalog)
local HUDStore = require(script.Parent.Parent.state.HUDStore)

local function categoryTab(icon: string, label: string, active: boolean, layoutOrder: number, onClick: () -> ())
	return React.createElement("TextButton", {
		Name = label .. "Tab",
		Size = UDim2.new(1, 0, 0, 32), -- Comfortable 32px height
		BackgroundColor3 = if active then Theme.Color.Accent else Theme.Color.SurfaceRaised,
		BackgroundTransparency = if active then 0 else Theme.Transparency.Card,
		AutoButtonColor = true,
		Text = icon .. " " .. label,
		FontFace = if active then Theme.FontFace.BodyBold else Theme.FontFace.Body,
		TextSize = 18, -- Clear, readable 18px text
		TextColor3 = if active then Theme.Color.OnAccent else Theme.Color.TextSecondary,
		TextXAlignment = Enum.TextXAlignment.Left,
		ClipsDescendants = true,
		LayoutOrder = layoutOrder,
		[React.Event.Activated] = onClick,
	}, {
		Corner = React.createElement("UICorner", { CornerRadius = Theme.corner(Theme.Metrics.RadiusSmall) }),
		Stroke = React.createElement("UIStroke", {
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Color = Theme.Color.Accent,
			Transparency = if active then 0.4 else 0.6,
			Thickness = if active then 2.5 else 1.8,
		}),
		Padding = React.createElement("UIPadding", {
			PaddingLeft = UDim.new(0, 8),
			PaddingRight = UDim.new(0, 8),
		}),
	})
end

local function CategoryColumn()
	local selectedCategory = HUDStore.useHUDState(function(s)
		return s.selectedCategory
	end)

	local tabChildren: { [string]: any } = {
		Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			Padding = UDim.new(0, 4),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}

	local tabOrder = 0
	for _, category in BuildingCatalog.getCategories() do
		tabOrder += 1
		tabChildren[category] = categoryTab(
			BuildingCatalog.getCategoryIcon(category),
			category,
			selectedCategory == category,
			tabOrder,
			function()
				HUDStore.setState({ selectedCategory = category })
			end
		)
	end

	return React.createElement("Frame", {
		Name = "CategoryColumn",
		Size = UDim2.new(0, 90, 1, 0),
		BackgroundTransparency = 1,
	}, tabChildren)
end

return CategoryColumn
