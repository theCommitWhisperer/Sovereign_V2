--!strict
-- BuildDrawer: the scrolling list of building cards for the active category.
-- Slides up above CategoryRail when a category is selected (MobileShell owns
-- that transition; this component only ever renders "open").
--
-- Every number on a card (cost, output) is read straight off BuildingCatalog,
-- which itself derives from BuildingSpec -- nothing here re-types a balance
-- number, so a config change shows up without touching this file.

local React = require(game.ReplicatedStorage.Packages.react)
local Theme = require(script.Parent.Parent.Theme)
local BuildingCatalog = require(script.Parent.Parent.BuildingCatalog)

export type Props = {
	category: string,
	resources: { [string]: number },
	gloryLifetime: number,
	onSelectBuilding: (string) -> (),
	LayoutOrder: number?,
}

local function costChip(chip: BuildingCatalog.CostChip, short: boolean, layoutOrder: number)
	return React.createElement("Frame", {
		Name = chip.resource .. "Chip",
		LayoutOrder = layoutOrder,
		Size = UDim2.new(0, 0, 0, Theme.Metrics.TouchTarget * 0.5),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Theme.Color.Surface,
		BackgroundTransparency = Theme.Transparency.Card,
	}, {
		Corner = React.createElement("UICorner", { CornerRadius = Theme.corner(Theme.Metrics.RadiusSmall) }),
		Padding = React.createElement("UIPadding", {
			PaddingLeft = UDim.new(0, Theme.Metrics.PadTight),
			PaddingRight = UDim.new(0, Theme.Metrics.PadTight),
		}),
		Label = React.createElement("TextLabel", {
			Size = UDim2.new(0, 0, 1, 0),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			Text = chip.label,
			FontFace = Theme.FontFace.Body,
			TextSize = Theme.TextSize.Caption,
			TextColor3 = short and Theme.Color.Danger or Theme.Color.TextSecondary,
		}),
	})
end

local function buildingCard(entry: BuildingCatalog.Entry, resources: { [string]: number }, gloryLifetime: number, layoutOrder: number, onSelect: (string) -> ())
	local affordable, short = BuildingCatalog.affordability(entry, resources)
	local unlocked = BuildingCatalog.isUnlocked(entry, gloryLifetime)
	local clickable = affordable and unlocked
	-- Dimmed reads as "not right now", not "broken" -- text goes muted rather
	-- than the whole card disappearing, so the player still sees what exists.
	local textColor = clickable and Theme.Color.TextPrimary or Theme.Color.TextMuted
	local descColor = clickable and Theme.Color.TextSecondary or Theme.Color.TextMuted

	local chipRow
	if not unlocked then
		chipRow = React.createElement("TextLabel", {
			LayoutOrder = 2,
			Size = UDim2.new(1, 0, 0, Theme.Metrics.TouchTarget * 0.5),
			BackgroundTransparency = 1,
			Text = `🔒 Requires {entry.gloryRequired} Glory`,
			FontFace = Theme.FontFace.BodyBold,
			TextSize = Theme.TextSize.Small,
			TextColor3 = Theme.Color.Warning,
			TextXAlignment = Enum.TextXAlignment.Left,
		})
	else
		local chips = {}
		chips.Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, Theme.Metrics.GapTight),
			SortOrder = Enum.SortOrder.LayoutOrder,
		})
		for i, chip in entry.cost do
			chips[chip.resource] = costChip(chip, short[chip.resource] == true, i)
		end
		chipRow = React.createElement("Frame", {
			LayoutOrder = 2,
			Size = UDim2.new(1, 0, 0, Theme.Metrics.TouchTarget * 0.5),
			BackgroundTransparency = 1,
		}, chips)
	end

	return React.createElement("TextButton", {
		Name = entry.name,
		LayoutOrder = layoutOrder,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Theme.Color.SurfaceRaised,
		BackgroundTransparency = Theme.Transparency.Card,
		AutoButtonColor = false,
		Active = clickable,
		Text = "",
		[React.Event.Activated] = clickable and function()
			onSelect(entry.name)
		end or nil,
	}, {
		Corner = React.createElement("UICorner", { CornerRadius = Theme.corner(Theme.Metrics.RadiusCard) }),
		Stroke = React.createElement("UIStroke", Theme.strokeProps()),
		Padding = React.createElement("UIPadding", {
			PaddingTop = UDim.new(0, Theme.Metrics.Pad),
			PaddingBottom = UDim.new(0, Theme.Metrics.Pad),
			PaddingLeft = UDim.new(0, Theme.Metrics.Pad),
			PaddingRight = UDim.new(0, Theme.Metrics.Pad),
		}),
		Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			Padding = UDim.new(0, Theme.Metrics.GapTight),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		TopRow = React.createElement("Frame", {
			LayoutOrder = 1,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
		}, {
			IconTile = React.createElement("Frame", {
				Size = UDim2.fromOffset(Theme.Metrics.TouchTarget, Theme.Metrics.TouchTarget),
				BackgroundColor3 = Theme.Color.Surface,
				BackgroundTransparency = Theme.Transparency.Card,
			}, {
				Corner = React.createElement("UICorner", { CornerRadius = Theme.corner(Theme.Metrics.RadiusSmall) }),
				Icon = React.createElement("TextLabel", {
					Size = UDim2.fromScale(1, 1),
					BackgroundTransparency = 1,
					Text = BuildingCatalog.getCategoryIcon(entry.category),
					FontFace = Theme.FontFace.Body,
					TextSize = Theme.TextSize.Title,
					TextColor3 = textColor,
				}),
			}),
			Name = React.createElement("TextLabel", {
				Position = UDim2.fromOffset(Theme.Metrics.TouchTarget + Theme.Metrics.Gap, 0),
				Size = UDim2.new(1, -(Theme.Metrics.TouchTarget + Theme.Metrics.Gap) - 90, 0, 18),
				BackgroundTransparency = 1,
				Text = entry.name,
				FontFace = Theme.FontFace.BodyBold,
				TextSize = Theme.TextSize.Heading,
				TextColor3 = textColor,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
			}),
			Description = React.createElement("TextLabel", {
				Position = UDim2.fromOffset(Theme.Metrics.TouchTarget + Theme.Metrics.Gap, 18),
				Size = UDim2.new(1, -(Theme.Metrics.TouchTarget + Theme.Metrics.Gap) - 90, 0, 32),
				BackgroundTransparency = 1,
				Text = entry.description,
				FontFace = Theme.FontFace.Body,
				TextSize = Theme.TextSize.Small,
				TextColor3 = descColor,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
			}),
			Output = entry.output and React.createElement("TextLabel", {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, 0, 0, 0),
				Size = UDim2.fromOffset(90, 18),
				BackgroundTransparency = 1,
				Text = entry.output,
				FontFace = Theme.FontFace.BodyBold,
				TextSize = Theme.TextSize.Small,
				TextColor3 = clickable and Theme.Color.Success or Theme.Color.TextMuted,
				TextXAlignment = Enum.TextXAlignment.Right,
				TextWrapped = true,
			}) or nil,
			Sizer = React.createElement("Frame", {
				-- Invisible spacer so AutomaticSize.Y on TopRow accounts for the two
				-- absolutely-positioned label rows above (they don't otherwise
				-- contribute to a Frame's automatic height).
				Size = UDim2.new(1, 0, 0, 50),
				BackgroundTransparency = 1,
			}),
		}),
		ChipRow = chipRow,
	})
end

local function BuildDrawer(props: Props)
	local entries = BuildingCatalog.getCategory(props.category)

	local cards = {}
	cards.Layout = React.createElement("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		Padding = UDim.new(0, Theme.Metrics.Gap),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
	for i, entry in entries do
		cards[entry.name] = buildingCard(entry, props.resources, props.gloryLifetime, i, props.onSelectBuilding)
	end

	return React.createElement("Frame", {
		Name = "BuildDrawer",
		LayoutOrder = props.LayoutOrder,
		Size = UDim2.new(1, 0, 0, Theme.Metrics.DrawerMaxHeight),
		BackgroundColor3 = Theme.Color.SurfaceRaised,
		BackgroundTransparency = Theme.Transparency.Drawer,
		BorderSizePixel = 0,
	}, {
		Corner = React.createElement("UICorner", { CornerRadius = Theme.corner(Theme.Metrics.RadiusCard) }),
		Stroke = React.createElement("UIStroke", Theme.strokeProps()),
		List = React.createElement("ScrollingFrame", {
			Size = UDim2.new(1, -Theme.Metrics.Pad * 2, 1, -Theme.Metrics.Pad * 2),
			Position = UDim2.fromOffset(Theme.Metrics.Pad, Theme.Metrics.Pad),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			ScrollBarThickness = 4,
			ScrollBarImageColor3 = Theme.Color.Accent,
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			CanvasSize = UDim2.fromScale(0, 0),
		}, cards),
	})
end

return BuildDrawer
