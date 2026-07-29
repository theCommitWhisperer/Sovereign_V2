--!strict
-- MobileShell: chrome for the touch layout, per docs/EconomyRedesign.md
-- section 8's design rules. Unlike DesktopShell, there is no existing mobile
-- layout to preserve -- HUD.luau has never had one -- so this is a fresh
-- design against the doc's rules rather than a port of anything:
--
--   * Top strip is DISPLAY-ONLY. Nothing interactive within 60px of the top
--     edge: it renders ResourceDisplay and nothing with a click handler.
--   * Primary actions live in the lower third (thumb zone).
--   * Building menu is category -> drawer, one level open at a time, not the
--     desktop habit of a permanently visible grid.
--   * The bottom bar is SELECTION-DRIVEN: units selected replaces the
--     category chips with a selection summary instead of stacking both.
--
-- Same panels as DesktopShell (BuildingMenu, SelectionPanel) and the same
-- HUDStore -- this proves the "one component tree" rule: neither panel forks
-- for mobile, they just receive different tokens/props.
--
-- Not wired into App.luau's router -- see AdaptiveHUD.luau's header.

local React = require(game.ReplicatedStorage.Packages.react)

local UIConfig = require(script.Parent.Parent.UIConfig)
local Platform = require(script.Parent.Parent.Platform)
local HUDStore = require(script.Parent.Parent.state.HUDStore)

local ResourceDisplay = require(script.Parent.Parent.screens.HUD.ResourceDisplay)
local BuildingMenu = require(script.Parent.Parent.screens.HUD.BuildingMenu)
local SelectionPanel = require(script.Parent.Parent.screens.HUD.SelectionPanel)

export type Props = {
	tooltip: any?,
}

local CATEGORIES = { "Defense", "Military", "Industry", "Food", "Housing", "Prestige" }
local CATEGORY_ICONS: { [string]: string } = {
	Defense = "🛡️",
	Military = "⚔️",
	Industry = "💰",
	Food = "🌾",
	Housing = "🏠",
	Prestige = "👑",
}

local DRAWER_HEIGHT = 220

local function MobileShell(props: Props)
	local tokens = Platform.tokens

	local resources = HUDStore.useHUDState(function(s)
		return s.resources
	end)
	local gloryLifetime = HUDStore.useHUDState(function(s)
		return s.gloryLifetime
	end)
	local selectedUnits = HUDStore.useHUDState(function(s)
		return s.selectedUnits
	end)
	local selectedCategory = HUDStore.useHUDState(function(s)
		return s.selectedCategory
	end)

	-- Drawer open/closed is view-only chrome state, not game state, so it lives
	-- here rather than in HUDStore (which both shells share). Rotating a
	-- tablet across the compact breakpoint remounts this component, which
	-- correctly closes the drawer rather than leaving a stale one open.
	local drawerOpen, setDrawerOpen = React.useState(false)

	local hasUnitsSelected = #selectedUnits > 0

	-- A unit selection takes over the bottom bar; a still-open drawer
	-- underneath it would be exactly the "everything visible at once" habit
	-- the design doc calls out, so selecting units force-closes it.
	React.useEffect(function()
		if hasUnitsSelected and drawerOpen then
			setDrawerOpen(false)
		end
	end, { hasUnitsSelected })

	local categoryChips = {}
	for i, category in CATEGORIES do
		local isActiveTab = selectedCategory == category and drawerOpen
		categoryChips[category .. "Chip"] = React.createElement("TextButton", {
			Name = category .. "Chip",
			LayoutOrder = i,
			Size = UDim2.fromOffset(tokens.hitTarget, tokens.hitTarget),
			Text = CATEGORY_ICONS[category] or "?",
			TextSize = 20 * tokens.fontScale,
			Font = Enum.Font.GothamBold,
			TextColor3 = UIConfig.HUD.PanelTextColor,
			BackgroundColor3 = if isActiveTab
				then UIConfig.HUD.CategoryButtonSelected
				else UIConfig.HUD.CategoryButtonBackground,
			BorderSizePixel = 0,
			[React.Event.Activated] = function()
				if selectedCategory == category and drawerOpen then
					setDrawerOpen(false)
				else
					HUDStore.setState({ selectedCategory = category })
					setDrawerOpen(true)
				end
			end,
		}, {
			Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, tokens.cornerRadius) }),
		})
	end

	local showDrawer = drawerOpen and not hasUnitsSelected

	local actionBarChildren: { [string]: any }
	if hasUnitsSelected then
		actionBarChildren = {
			Selection = React.createElement(SelectionPanel, {
				selectedUnits = selectedUnits,
			}),
		}
	else
		actionBarChildren = {
			Layout = React.createElement("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, tokens.padding),
			}),
		}
		for key, chip in categoryChips do
			actionBarChildren[key] = chip
		end
	end

	return React.createElement("Frame", {
		Name = "MobileShell",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, {
		-- Display-only: no [React.Event.*] handlers anywhere in this frame,
		-- ever. That is the whole point of the 60px-clear-zone rule.
		TopStrip = React.createElement("Frame", {
			Name = "TopStrip",
			Size = UDim2.new(1, 0, 0, 56),
			Position = UDim2.fromOffset(0, Platform.safeArea.Top),
			BackgroundColor3 = UIConfig.HUD.TopBarBackground,
			BackgroundTransparency = 0.1,
			BorderSizePixel = 0,
		}, {
			Resources = React.createElement(ResourceDisplay, { resources = resources }),
		}),

		BottomArea = React.createElement("Frame", {
			Name = "BottomArea",
			Size = UDim2.new(1, 0, 0, tokens.bottomBarHeight + (if showDrawer then DRAWER_HEIGHT else 0)),
			Position = UDim2.new(0, 0, 1, -Platform.safeArea.Bottom),
			AnchorPoint = Vector2.new(0, 1),
			BackgroundTransparency = 1,
		}, {
			-- One level open at a time: this is the ONLY drawer that can be on
			-- screen, and it closes itself the moment a selection takes over.
			Drawer = showDrawer and React.createElement("Frame", {
				Name = "Drawer",
				Size = UDim2.new(1, -tokens.padding * 2, 0, DRAWER_HEIGHT),
				Position = UDim2.fromOffset(tokens.padding, 0),
				BackgroundColor3 = UIConfig.HUD.ContentAreaBackground,
				BorderSizePixel = 0,
			}, {
				Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, tokens.cornerRadius) }),
				Menu = React.createElement(BuildingMenu, {
					tooltip = props.tooltip,
					resources = resources,
					gloryLifetime = gloryLifetime,
					selectedCategory = selectedCategory,
					onBuildingSelected = function(buildingName: string)
						HUDStore.startPlacement(buildingName)
						setDrawerOpen(false)
					end,
				}),
			}) or nil,

			ActionBar = React.createElement("Frame", {
				Name = "ActionBar",
				Size = UDim2.new(1, 0, 0, tokens.bottomBarHeight),
				Position = UDim2.new(0, 0, 1, 0),
				AnchorPoint = Vector2.new(0, 1),
				BackgroundColor3 = UIConfig.HUD.BottomBarBackground,
				BorderSizePixel = 0,
			}, actionBarChildren),
		}),
	})
end

return MobileShell
