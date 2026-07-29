--!strict
-- DesktopShell: chrome for the mouse/keyboard layout. Positions panels; owns no
-- game state itself (HUDStore does). Per docs/EconomyRedesign.md section 8,
-- this is required to be VISUAL PARITY with HUD.luau's current desktop
-- layout, not a redesign -- so every position/size below is copied from
-- HUD.luau's render() (top bar, bottom bar, minimap frame, category button
-- positions, content area) rather than re-derived.
--
-- ---------------------------------------------------------------------------
-- THIS IS A PROOF SLICE, NOT A FULL PORT
-- ---------------------------------------------------------------------------
-- HUD.luau owns ~30 pieces of state and two dozen panels/modals (Policies,
-- TechTree, Undo, BattleLog, tutorial, delete confirmation, ability tree...).
-- Migrating all of it in one pass was explicitly out of scope. This shell only
-- mounts the panels that have been converted to presentational components so
-- far: TopBar (already props-only), BuildingMenu, and SelectionPanel as a
-- stand-in for the units-selected case. HUD.luau's real units-selected panel,
-- UnitSelectionPanel (formation/stance controls), has NOT been migrated yet,
-- so a player with units selected sees a simpler summary here than on the live
-- HUD until that panel gets its own presentational pass.
--
-- Not wired into App.luau's router -- see AdaptiveHUD.luau's header.

local React = require(game.ReplicatedStorage.Packages.react)

local UIConfig = require(script.Parent.Parent.UIConfig)
local HUDStore = require(script.Parent.Parent.state.HUDStore)

local TopBar = require(script.Parent.Parent.screens.HUD.TopBar)
local MiniMap = require(script.Parent.Parent.screens.HUD.MiniMap)
local BuildingMenu = require(script.Parent.Parent.screens.HUD.BuildingMenu)
local SelectionPanel = require(script.Parent.Parent.screens.HUD.SelectionPanel)
local IconButton = require(script.Parent.Parent.components.IconButton)

export type Props = {
	tooltip: any?,
}

-- Same six tabs and pixel positions as HUD.luau's createCategoryButton /
-- UIConfig.HUD.CategoryButtonPositions. Desktop tabs are image buttons (see
-- UIConfig.HUD.CategoryButtonImages) -- no text icons needed here, unlike
-- MobileShell's chips.
local CATEGORIES = { "Defense", "Military", "Industry", "Food", "Housing", "Prestige" }

local function DesktopShell(props: Props)
	local resources = HUDStore.useHUDState(function(s)
		return s.resources
	end)
	local honor = HUDStore.useHUDState(function(s)
		return s.honor
	end)
	local glory = HUDStore.useHUDState(function(s)
		return s.glory
	end)
	local gloryLifetime = HUDStore.useHUDState(function(s)
		return s.gloryLifetime
	end)
	local population = HUDStore.useHUDState(function(s)
		return s.population
	end)
	local date = HUDStore.useHUDState(function(s)
		return s.date
	end)
	local weather = HUDStore.useHUDState(function(s)
		return s.weather
	end)
	local peaceTimeRemaining = HUDStore.useHUDState(function(s)
		return s.peaceTimeRemaining
	end)
	local victoryCondition = HUDStore.useHUDState(function(s)
		return s.victoryCondition
	end)
	local selectedUnits = HUDStore.useHUDState(function(s)
		return s.selectedUnits
	end)
	local selectedCategory = HUDStore.useHUDState(function(s)
		return s.selectedCategory
	end)

	local hasUnitsSelected = #selectedUnits > 0

	local categoryButtons = {}
	for i, category in CATEGORIES do
		local isSelected = selectedCategory == category
		local buttonImage = UIConfig.HUD.CategoryButtonImages[category] or "rbxassetid://105781657626004"
		local position = UIConfig.HUD.CategoryButtonPositions[category] or { X = 452, Y = 38 }

		categoryButtons[category .. "Button"] = React.createElement(IconButton, {
			Size = UDim2.fromOffset(UIConfig.HUD.CategoryButtonWidth, UIConfig.HUD.CategoryButtonHeight),
			Position = UDim2.fromOffset(position.X, position.Y),
			ButtonImage = buttonImage,
			ImageColor3 = Color3.fromRGB(255, 255, 255),
			ShowGlow = false,
			VisualScale = isSelected and 1.5 or 1.0,
			ZIndex = isSelected and 20 or 11,
			OnClick = function()
				HUDStore.setState({ selectedCategory = category })
			end,
		})
	end

	local contentAreaChild
	if hasUnitsSelected then
		contentAreaChild = React.createElement(SelectionPanel, {
			selectedUnits = selectedUnits,
		})
	else
		contentAreaChild = React.createElement(BuildingMenu, {
			tooltip = props.tooltip,
			resources = resources,
			gloryLifetime = gloryLifetime,
			selectedCategory = selectedCategory,
			onBuildingSelected = function(buildingName: string)
				HUDStore.startPlacement(buildingName)
			end,
		})
	end

	local bottomBarChildren: { [string]: any } = {
		MainBackground = React.createElement("ImageLabel", {
			Name = "MainBackground",
			Size = UDim2.new(0, 800, 0, UIConfig.HUD.BottomBarHeight),
			Position = UDim2.new(0, 0, 0, 0),
			BackgroundTransparency = 1,
			Image = "rbxassetid://102075136386279",
			BorderSizePixel = 0,
			ZIndex = 10,
		}),

		MiniMapFrame = React.createElement("Frame", {
			Name = "MiniMapFrame",
			Size = UDim2.new(0, UIConfig.HUD.MinimapSize, 0, UIConfig.HUD.MinimapSize),
			Position = UDim2.new(0, 185, 0, 40),
			BackgroundColor3 = Color3.fromRGB(0, 0, 0),
			BorderColor3 = UIConfig.HUD.MinimapBorder,
			BorderSizePixel = 2,
			ClipsDescendants = true,
			ZIndex = 9,
		}, {
			Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
			MiniMap = React.createElement(MiniMap),
		}),

		ContentArea = React.createElement("Frame", {
			Name = "ContentArea",
			Size = UDim2.new(0.35, 215, 0, 10),
			Position = UDim2.new(0, 540, 0, 45),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 11,
		}, {
			Content = contentAreaChild,
		}),
	}
	for key, element in categoryButtons do
		bottomBarChildren[key] = element
	end

	return React.createElement("Frame", {
		Name = "DesktopShell",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, {
		TopBar = React.createElement(TopBar, {
			resources = resources,
			honor = honor,
			glory = glory,
			population = population,
			date = date,
			weather = weather,
			peaceTimeRemaining = peaceTimeRemaining,
			victoryCondition = victoryCondition,
		}),

		BottomBar = React.createElement("Frame", {
			Name = "BottomBar",
			Size = UDim2.new(0, 1400, 0, UIConfig.HUD.BottomBarHeight),
			Position = UDim2.new(0, 0, 1, 0),
			AnchorPoint = Vector2.new(0, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 10,
		}, bottomBarChildren),
	})
end

return DesktopShell
