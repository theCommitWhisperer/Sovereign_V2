--!strict
-- DesktopBuildingGrid: sleek rectangular building pill cards (140x56px) with generous padding & gold border strokes.

local React = require(game.ReplicatedStorage.Packages.react)

local Theme = require(script.Parent.Parent.Theme)
local BuildingCatalog = require(script.Parent.Parent.BuildingCatalog)
local HUDStore = require(script.Parent.Parent.state.HUDStore)

export type Props = {
	tooltip: any?,
	gridOnly: boolean?,
}

local TILE_WIDTH = 140
local TILE_HEIGHT = 56

--- One cost chip: resource-coloured normally, Danger-coloured when short.
local function costChip(label: string, resource: string, short: boolean, layoutOrder: number)
	return React.createElement("TextLabel", {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 0, 14),
		BackgroundTransparency = 1,
		Text = label,
		FontFace = Theme.FontFace.Body,
		TextSize = 10,
		TextColor3 = if short then Theme.Color.Danger else Theme.resourceColor(resource),
		LayoutOrder = layoutOrder,
	})
end

local function buildingTile(
	entry: BuildingCatalog.Entry,
	resources: { [string]: number },
	gloryLifetime: number,
	tooltip: any?,
	layoutOrder: number
)
	local unlocked = BuildingCatalog.isUnlocked(entry, gloryLifetime)
	local affordable, short = BuildingCatalog.affordability(entry, resources)

	local costChildren: { [string]: any } = {
		Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 4),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}
	for i, chip in entry.cost do
		costChildren[chip.resource] = costChip(chip.label, chip.resource, short[chip.resource] == true, i)
	end

	local buttonRef = React.createRef()

	return React.createElement("TextButton", {
		Name = entry.name,
		ref = buttonRef,
		Size = UDim2.fromOffset(TILE_WIDTH, TILE_HEIGHT),
		BackgroundColor3 = Theme.Color.SurfaceRaised,
		BackgroundTransparency = if not unlocked
			then Theme.Transparency.Border
			elseif not affordable then Theme.Transparency.Card
			else Theme.Transparency.CardActive,
		AutoButtonColor = unlocked,
		Text = "",
		LayoutOrder = layoutOrder,
		Active = unlocked,
		[React.Event.Activated] = function()
			if unlocked then
				HUDStore.startPlacement(entry.name)
			end
		end,
		[React.Event.MouseEnter] = function()
			if tooltip and entry.description ~= "" then
				tooltip.show(entry.description, buttonRef.current)
			end
		end,
		[React.Event.MouseLeave] = function()
			if tooltip then
				tooltip.hide()
			end
		end,
	}, {
		Corner = React.createElement("UICorner", { CornerRadius = Theme.corner(Theme.Metrics.RadiusSmall) }),

		-- OUTER GOLD BORDER STROKE ON THE BUTTON ITSELF (ApplyStrokeMode.Border)
		OuterStroke = React.createElement("UIStroke", {
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Color = Theme.Color.Accent,
			Transparency = if unlocked and affordable then 0 else 0.4,
			Thickness = if unlocked and affordable then 2 else 1.5,
		}),

		-- GENEROUS CARD INTERNAL PADDING
		Padding = React.createElement("UIPadding", {
			PaddingTop = UDim.new(0, 6),
			PaddingBottom = UDim.new(0, 6),
			PaddingLeft = UDim.new(0, 7),
			PaddingRight = UDim.new(0, 7),
		}),

		-- Left Icon Preview Container (44x44px)
		IconPreview = React.createElement("Frame", {
			Size = UDim2.fromOffset(44, 44),
			Position = UDim2.new(0, 0, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			BackgroundColor3 = Theme.Color.Surface,
			BackgroundTransparency = 0.4,
			BorderSizePixel = 0,
			ClipsDescendants = true,
		}, {
			Corner = React.createElement("UICorner", { CornerRadius = Theme.corner(Theme.Metrics.RadiusSmall) }),
			IconImage = entry.iconAssetId and React.createElement("ImageLabel", {
				Size = UDim2.fromScale(0.85, 0.85),
				Position = UDim2.fromScale(0.5, 0.5),
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 1,
				Image = entry.iconAssetId,
				ScaleType = Enum.ScaleType.Fit,
			}) or React.createElement("TextLabel", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Text = BuildingCatalog.getCategoryIcon(entry.category),
				FontFace = Theme.FontFace.Display,
				TextSize = 22,
				TextColor3 = Theme.Color.Accent,
			}),
		}),

		-- Right Details Column (Title, Cost Chips, Output)
		DetailsColumn = React.createElement("Frame", {
			Size = UDim2.new(1, -50, 1, 0),
			Position = UDim2.new(0, 50, 0, 0),
			BackgroundTransparency = 1,
		}, {
			Layout = React.createElement("UIListLayout", {
				FillDirection = Enum.FillDirection.Vertical,
				Padding = UDim.new(0, 2),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),

			-- Building Name
			Name = React.createElement("TextLabel", {
				Size = UDim2.new(1, 0, 0, 16),
				BackgroundTransparency = 1,
				Text = entry.name,
				FontFace = Theme.FontFace.BodyBold,
				TextSize = 11,
				TextColor3 = if unlocked then Theme.Color.TextPrimary else Theme.Color.TextMuted,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				LayoutOrder = 1,
			}),

			-- Cost & Output Details
			Body = if unlocked
				then React.createElement("Frame", {
					Size = UDim2.new(1, 0, 0, 26),
					BackgroundTransparency = 1,
					LayoutOrder = 2,
				}, {
					Layout = React.createElement("UIListLayout", {
						FillDirection = Enum.FillDirection.Vertical,
						Padding = UDim.new(0, 1),
						SortOrder = Enum.SortOrder.LayoutOrder,
					}),
					Cost = React.createElement("Frame", {
						Size = UDim2.new(1, 0, 0, 14),
						BackgroundTransparency = 1,
						LayoutOrder = 1,
					}, costChildren),
					Output = entry.output and React.createElement("TextLabel", {
						Size = UDim2.new(1, 0, 0, 12),
						BackgroundTransparency = 1,
						Text = entry.output :: string,
						FontFace = Theme.FontFace.Body,
						TextSize = 10,
						TextColor3 = Theme.Color.Accent,
						TextXAlignment = Enum.TextXAlignment.Left,
						TextTruncate = Enum.TextTruncate.AtEnd,
						LayoutOrder = 2,
					}) or nil,
				})
				else React.createElement("TextLabel", {
					Size = UDim2.new(1, 0, 0, 26),
					BackgroundTransparency = 1,
					Text = string.format("🔒 Glory %d", entry.gloryRequired or 0),
					FontFace = Theme.FontFace.Body,
					TextSize = 10,
					TextColor3 = Theme.Color.TextMuted,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextYAlignment = Enum.TextYAlignment.Center,
					LayoutOrder = 2,
				}),
		}),
	})
end

local function DesktopBuildingGrid(props: Props)
	local selectedCategory = HUDStore.useHUDState(function(s)
		return s.selectedCategory
	end)
	local resources = HUDStore.useHUDState(function(s)
		return s.resources
	end)
	local gloryLifetime = HUDStore.useHUDState(function(s)
		return s.gloryLifetime
	end)

	local category = selectedCategory or "Food"
	local entries = BuildingCatalog.getCategory(category)

	local tileChildren: { [string]: any } = {
		Padding = React.createElement("UIPadding", {
			PaddingTop = UDim.new(0, 6),
			PaddingBottom = UDim.new(0, 6),
			PaddingLeft = UDim.new(0, 8),
			PaddingRight = UDim.new(0, 8),
		}),
		Layout = React.createElement("UIGridLayout", {
			CellSize = UDim2.fromOffset(TILE_WIDTH, TILE_HEIGHT),
			CellPadding = UDim2.fromOffset(8, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
			FillDirection = Enum.FillDirection.Horizontal,
		}),
	}

	for i, entry in entries do
		tileChildren[entry.name] = buildingTile(entry, resources, gloryLifetime, props.tooltip, i)
	end

	return React.createElement("ScrollingFrame", {
		Name = "BuildingGridScroll",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 4,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.fromScale(0, 0),
	}, tileChildren)
end

return DesktopBuildingGrid
