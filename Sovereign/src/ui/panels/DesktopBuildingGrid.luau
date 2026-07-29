--!strict
-- DesktopBuildingGrid: category rail + the always-visible building grid that
-- is desktop's replacement for mobile's category-then-drawer flow.
--
-- WHY A GRID, NOT A DRAWER
-- ------------------------
-- Desktop has the width to show every building in a category at once, so
-- there is no "tap a category, a panel slides open" step to reproduce -- the
-- rail switches `selectedCategory` and the grid below it just always reflects
-- whatever that is. This is the literal replacement for screens/HUD/
-- BuildingMenu.luau, which drew a bare icon grid from raw GameData.Buildings
-- with no cost/output text at all; every card here is built from
-- BuildingCatalog instead, which is what makes cost/output/staffing/glory-gate
-- text possible without retyping the balance data.
--
-- ICON CHOICE: BuildingCatalog does not carry a per-building icon (no asset
-- ids in the new visual language), so each tile shows its CATEGORY glyph
-- rather than a building-specific image -- consistent with the "no
-- rbxassetid chrome" rule and with BuildingCatalog.getCategoryIcon already
-- being the only icon source that exists for this data.
--
-- CLICK GATING: a Glory-locked tile is not clickable at all (the building is
-- structurally unavailable). An unaffordable-but-unlocked tile IS still
-- clickable -- HUDStore.startPlacement fires the remote regardless, the
-- server is the real gate, and a rejection already surfaces through
-- HUDStore's "Error" -> battle-log wiring. Blocking the click client-side
-- would just be a second copy of a rule the server already owns.
--
-- WALL-PIECE SUBMODE DROPPED: the legacy BuildingMenu also highlighted
-- whichever wall segment/corner/gatehouse piece was currently selected while
-- dragging a wall path (`currentWallPiece`/`isPlacingWall`). BuildingCatalog
-- has no concept of wall pieces (only whole buildings), so that highlight
-- does not carry over here; "Stone Wall" itself remains an ordinary tile.

local React = require(game.ReplicatedStorage.Packages.react)

local Theme = require(script.Parent.Parent.Theme)
local BuildingCatalog = require(script.Parent.Parent.BuildingCatalog)
local HUDStore = require(script.Parent.Parent.state.HUDStore)

export type Props = {
	tooltip: any?,
}

-- Rail width has no dedicated Theme token (Theme.Metrics.CategoryRailHeight is
-- sized for mobile's horizontal chip STRIP height, not a vertical rail's
-- width), so this is a local layout constant, same convention MobileShell
-- uses for its own shell-specific offsets.
-- Two columns of icon tiles rather than one tall list: there are 8 rail entries
-- (6 categories + delete + abilities) and only ~140px of usable height in the
-- compact bar, so a single column would give each one 17px.
local RAIL_WIDTH = 104
local RAIL_CELL = 44
local TILE_WIDTH = Theme.Metrics.BuildTileWidth
local TILE_HEIGHT = Theme.Metrics.BuildTileHeight

-- Icon only. A 44px cell cannot legibly carry an icon AND a label, and the
-- label would be redundant anyway: the active category's name is printed as the
-- header above the tile row, so there is exactly one place to read it.
local function railButton(icon: string, label: string, active: boolean, layoutOrder: number, onClick: () -> ())
	return React.createElement("TextButton", {
		Name = label .. "RailButton",
		BackgroundColor3 = if active then Theme.Color.Accent else Theme.Color.SurfaceRaised,
		BackgroundTransparency = if active then Theme.Transparency.CardActive else Theme.Transparency.Card,
		AutoButtonColor = true,
		Text = icon,
		FontFace = Theme.FontFace.Body,
		TextSize = Theme.TextSize.Title,
		TextColor3 = if active then Theme.Color.Accent else Theme.Color.TextSecondary,
		LayoutOrder = layoutOrder,
		[React.Event.Activated] = onClick,
	}, {
		Corner = React.createElement("UICorner", { CornerRadius = Theme.corner() }),
		Stroke = React.createElement("UIStroke", {
			Color = if active then Theme.Color.Accent else Theme.Color.Border,
			Transparency = if active then 0 else Theme.Transparency.Border,
			Thickness = 1,
		}),
	})
end

--- One cost chip: resource-coloured normally, Danger-coloured when it is the
--- thing blocking affordability.
local function costChip(label: string, resource: string, short: boolean, layoutOrder: number)
	return React.createElement("TextLabel", {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 0, 16),
		BackgroundTransparency = 1,
		Text = label,
		FontFace = Theme.FontFace.Body,
		TextSize = Theme.TextSize.Caption,
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
			Padding = UDim.new(0, Theme.Metrics.GapTight),
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
		Corner = React.createElement("UICorner", { CornerRadius = Theme.corner() }),
		Stroke = React.createElement("UIStroke", Theme.strokeProps(unlocked and affordable)),
		Padding = React.createElement("UIPadding", {
			PaddingTop = UDim.new(0, Theme.Metrics.PadTight),
			PaddingBottom = UDim.new(0, Theme.Metrics.PadTight),
			PaddingLeft = UDim.new(0, Theme.Metrics.PadTight),
			PaddingRight = UDim.new(0, Theme.Metrics.PadTight),
		}),
		Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			Padding = UDim.new(0, Theme.Metrics.GapTight),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),

		Header = React.createElement("Frame", {
			Size = UDim2.new(1, 0, 0, 20),
			BackgroundTransparency = 1,
			LayoutOrder = 1,
		}, {
			Layout = React.createElement("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, Theme.Metrics.GapTight),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
			Icon = React.createElement("TextLabel", {
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.new(0, 0, 1, 0),
				BackgroundTransparency = 1,
				Text = BuildingCatalog.getCategoryIcon(entry.category),
				FontFace = Theme.FontFace.Body,
				TextSize = Theme.TextSize.Heading,
				TextColor3 = Theme.Color.TextPrimary,
				LayoutOrder = 1,
			}),
			Name = React.createElement("TextLabel", {
				Size = UDim2.new(1, -24, 1, 0),
				BackgroundTransparency = 1,
				Text = entry.name,
				FontFace = Theme.FontFace.BodyBold,
				TextSize = Theme.TextSize.Small,
				TextColor3 = if unlocked then Theme.Color.TextPrimary else Theme.Color.TextMuted,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				LayoutOrder = 2,
			}),
		}),

		Body = if unlocked
			then React.createElement("Frame", {
				Size = UDim2.new(1, 0, 1, -20),
				BackgroundTransparency = 1,
				LayoutOrder = 2,
			}, {
				Layout = React.createElement("UIListLayout", {
					FillDirection = Enum.FillDirection.Vertical,
					Padding = UDim.new(0, Theme.Metrics.GapTight),
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
				Cost = React.createElement("Frame", {
					Size = UDim2.new(1, 0, 0, 16),
					BackgroundTransparency = 1,
					LayoutOrder = 1,
				}, costChildren),
				Output = entry.output and React.createElement("TextLabel", {
					Size = UDim2.new(1, 0, 0, 14),
					BackgroundTransparency = 1,
					Text = entry.output :: string,
					FontFace = Theme.FontFace.Body,
					TextSize = Theme.TextSize.Caption,
					TextColor3 = Theme.Color.Accent,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextTruncate = Enum.TextTruncate.AtEnd,
					LayoutOrder = 2,
				}) or nil,
				Staffing = entry.staffing and React.createElement("TextLabel", {
					Size = UDim2.new(1, 0, 0, 14),
					BackgroundTransparency = 1,
					Text = entry.staffing :: string,
					FontFace = Theme.FontFace.Body,
					TextSize = Theme.TextSize.Caption,
					TextColor3 = Theme.Color.TextSecondary,
					TextXAlignment = Enum.TextXAlignment.Left,
					LayoutOrder = 3,
				}) or nil,
			})
			else React.createElement("TextLabel", {
				Size = UDim2.new(1, 0, 1, -20),
				BackgroundTransparency = 1,
				Text = string.format("🔒 Requires %d Glory (%d/%d)", entry.gloryRequired, gloryLifetime, entry.gloryRequired),
				FontFace = Theme.FontFace.Body,
				TextSize = Theme.TextSize.Caption,
				TextColor3 = Theme.Color.TextMuted,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				LayoutOrder = 2,
			}),
	})
end

local function DesktopBuildingGrid(props: Props)
	local resources = HUDStore.useHUDState(function(s)
		return s.resources
	end)
	local gloryLifetime = HUDStore.useHUDState(function(s)
		return s.gloryLifetime
	end)
	local selectedCategory = HUDStore.useHUDState(function(s)
		return s.selectedCategory
	end)
	local isDeleteMode = HUDStore.useHUDState(function(s)
		return s.isDeleteMode
	end)
	local showAbilityTree = HUDStore.useHUDState(function(s)
		return s.showAbilityTree
	end)

	local railChildren: { [string]: any } = {
		Layout = React.createElement("UIGridLayout", {
			CellSize = UDim2.fromOffset(RAIL_CELL, RAIL_CELL),
			CellPadding = UDim2.fromOffset(Theme.Metrics.GapTight, Theme.Metrics.GapTight),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}
	local railOrder = 0
	for _, category in BuildingCatalog.getCategories() do
		railOrder += 1
		railChildren[category] = railButton(
			BuildingCatalog.getCategoryIcon(category),
			category,
			selectedCategory == category,
			railOrder,
			function()
				HUDStore.selectCategory(category)
			end
		)
	end

	-- Delete-mode and Ability-Tree toggles lived in the old bottom bar's left
	-- utility column; the spec's top bar only names Menu/Stats/Policies/
	-- TechTree, so these two ride along at the bottom of the category rail
	-- instead of losing their only on-screen control.
	-- No divider between categories and the utility toggles: a UIGridLayout gives
	-- every child a full cell, so a 1px separator would occupy a whole 44px slot.
	railOrder += 1
	railChildren.DeleteMode = railButton("🗑", "Delete", isDeleteMode, railOrder, function()
		HUDStore.toggleDeleteMode()
	end)
	railOrder += 1
	railChildren.AbilityTree = railButton("⚜", "Abilities", showAbilityTree, railOrder, function()
		HUDStore.toggleAbilityTree()
	end)

	-- ONE ROW, SCROLLING SIDEWAYS.
	--
	-- This was a UIGridLayout that wrapped onto new rows and scrolled vertically,
	-- which only made sense while the bottom bar was 330px tall. Now that the bar
	-- is a compact 164px there is room for exactly one row, and a vertical
	-- scrollbar that reveals one row at a time is worse than a horizontal one
	-- that reveals the next few buildings -- an RTS build menu is a shelf, not a
	-- grid you page through.
	local tileChildren: { [string]: any } = {
		Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, Theme.Metrics.Gap),
			SortOrder = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = Enum.VerticalAlignment.Center,
		}),
	}
	for i, entry in BuildingCatalog.getCategory(selectedCategory) do
		tileChildren[entry.name] = buildingTile(entry, resources, gloryLifetime, props.tooltip, i)
	end

	return React.createElement("Frame", {
		Name = "DesktopBuildingGrid",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, {
		Rail = React.createElement("Frame", {
			Name = "CategoryRail",
			Size = UDim2.new(0, RAIL_WIDTH, 1, 0),
			BackgroundTransparency = 1,
		}, railChildren),

		-- The rail is icon-only, so this is the one place the active category is
		-- named. Also states the count, which tells you whether the row scrolls.
		Header = React.createElement("TextLabel", {
			Name = "CategoryHeader",
			Size = UDim2.new(1, -RAIL_WIDTH - Theme.Metrics.Gap, 0, 16),
			Position = UDim2.new(0, RAIL_WIDTH + Theme.Metrics.Gap, 0, 0),
			BackgroundTransparency = 1,
			Text = ("%s  ·  %d buildings"):format(selectedCategory, #BuildingCatalog.getCategory(selectedCategory)),
			FontFace = Theme.FontFace.BodyBold,
			TextSize = Theme.TextSize.Small,
			TextColor3 = Theme.Color.TextSecondary,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),

		Grid = React.createElement("ScrollingFrame", {
			Name = "BuildingGrid",
			Size = UDim2.new(1, -RAIL_WIDTH - Theme.Metrics.Gap, 1, -20),
			Position = UDim2.new(0, RAIL_WIDTH + Theme.Metrics.Gap, 0, 20),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollingDirection = Enum.ScrollingDirection.X,
			ScrollBarThickness = 4,
			AutomaticCanvasSize = Enum.AutomaticSize.X,
			CanvasSize = UDim2.fromScale(0, 0),
		}, tileChildren),
	})
end

return DesktopBuildingGrid
