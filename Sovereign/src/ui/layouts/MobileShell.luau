--!strict
-- MobileShell: chrome for the touch layout, per docs/EconomyRedesign.md
-- section 8's design rules. Unlike DesktopShell, there is no existing mobile
-- layout to preserve -- HUD.luau has never had one -- so this is a fresh
-- design against the doc's rules rather than a port of anything.
--
-- Design rules this file enforces:
--   * Top strip is DISPLAY-ONLY. Nothing interactive within 60px of the top
--     edge -- the whole top chrome cluster (resources + status row) has no
--     [React.Event.*] handler anywhere in it.
--   * Primary actions live in the lower third (thumb zone): the utility row,
--     category chips, and every selection-driven panel render inside
--     BottomArea, anchored to the bottom of the screen.
--   * Building menu is category -> drawer, one level open at a time, not the
--     desktop habit of a permanently visible grid.
--   * The bottom bar is SELECTION-DRIVEN: whichever of
--     Training > Production > HeroAbilities > Upgrade > UnitSelection is
--     active takes over DetailArea; the building-menu drawer is only the
--     fallback when none of those are and a category chip was tapped. Same
--     priority order DesktopShell uses for its content area, so the two
--     shells never disagree about what a given selection should show.
--   * Modals (Policies/Menu/Stats/TechTree/AbilityTree/Tutorial) are FULL-
--     SCREEN SHEETS here: each of those panels' `size` prop is left nil on
--     Desktop (preserving its original centred-box default) and overridden
--     here to near-fullscreen.
--
-- Same panels as DesktopShell -- BuildingMenu, SelectionPanel,
-- UnitSelectionPanel, TrainingPanel, WorkerAssignmentPanel,
-- HeroAbilitiesPanel, UpgradePanel, MiniMap, FogOverlay, Policies, Menu,
-- Stats, TechTree, AbilityTreePanel, QuestTracker, AchievementNotification,
-- ConfirmDeleteModal, MultiDeleteModal, UndoButton, BattleLog, TutorialModal,
-- ViewToggleButton, HeroTouchControls -- and the same HUDStore. This proves
-- the "one component tree" rule: no panel forks for mobile, they only ever
-- receive different tokens/props/sizes than DesktopShell passes them.

local React = require(game.ReplicatedStorage.Packages.react)

local UIConfig = require(script.Parent.Parent.UIConfig)
local Platform = require(script.Parent.Parent.Platform)
local HUDStore = require(script.Parent.Parent.state.HUDStore)

local ResourceDisplay = require(script.Parent.Parent.screens.HUD.ResourceDisplay)
local FogOverlay = require(script.Parent.Parent.screens.HUD.FogOverlay)
local MiniMap = require(script.Parent.Parent.screens.HUD.MiniMap)
local BuildingMenu = require(script.Parent.Parent.screens.HUD.BuildingMenu)
local UnitSelectionPanel = require(script.Parent.Parent.screens.HUD.UnitSelectionPanel)
local TrainingPanel = require(script.Parent.Parent.screens.HUD.TrainingPanel)
local WorkerAssignmentPanel = require(script.Parent.Parent.screens.HUD.WorkerAssignmentPanel)
local HeroAbilitiesPanel = require(script.Parent.Parent.screens.HUD.HeroAbilitiesPanel)
local UpgradePanel = require(script.Parent.Parent.screens.HUD.UpgradePanel)
local Policies = require(script.Parent.Parent.screens.Policies.Policies)
local Menu = require(script.Parent.Parent.screens.Menu.Menu)
local Stats = require(script.Parent.Parent.screens.Stats.Stats)
local TechTree = require(script.Parent.Parent.screens.HUD.TechTree)
local AbilityTreePanel = require(script.Parent.Parent.screens.HUD.AbilityTreePanel)
local QuestTracker = require(script.Parent.Parent.screens.HUD.QuestTracker)
local AchievementNotification = require(script.Parent.Parent.screens.HUD.AchievementNotification)
local ConfirmDeleteModal = require(script.Parent.Parent.screens.HUD.ConfirmDeleteModal)
local MultiDeleteModal = require(script.Parent.Parent.screens.HUD.MultiDeleteModal)
local UndoButton = require(script.Parent.Parent.screens.HUD.UndoButton)
local BattleLog = require(script.Parent.Parent.screens.HUD.BattleLog)
local TutorialModal = require(script.Parent.Parent.components.TutorialModal)
local IconButton = require(script.Parent.Parent.components.IconButton)
local ViewToggleButton = require(script.Parent.Parent.screens.HUD.ViewToggleButton)
local HeroTouchControls = require(script.Parent.Parent.screens.HUD.HeroTouchControls)

export type Props = {
	tooltip: any?,
	navigate: ((string) -> ())?,
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

-- Height of the growing detail region above the persistent ActionBar. Sized
-- for the tallest thing that lands in it (UnitSelectionPanel's civilian
-- section bottoms out around y=217) with margin, not just the building grid.
local DETAIL_HEIGHT = 280
-- Two rows (utility icons + category chips) inside Platform.tokens.bottomBarHeight.
local UTILITY_ROW_HEIGHT = 52

-- Top chrome (resources + status row) is display-only per the design doc, but
-- it still needs a fixed height so everything anchored below it (view toggle,
-- king health, capture banners) has a stable reference point.
local TOP_CHROME_HEIGHT = 66

-- Modals become full-screen sheets on mobile instead of Desktop's centred
-- box -- every wrapped panel below (Policies/Menu/Stats/TechTree/
-- AbilityTreePanel/TutorialModal) forwards this through an optional `size`
-- prop that Desktop leaves nil.
local SHEET_SIZE = UDim2.fromScale(0.96, 0.94)

local function MobileShell(props: Props)
	local tokens = Platform.tokens

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
	local selectedTrainingBuilding = HUDStore.useHUDState(function(s)
		return s.selectedTrainingBuilding
	end)
	local selectedProductionBuilding = HUDStore.useHUDState(function(s)
		return s.selectedProductionBuilding
	end)
	local trainingQueue = HUDStore.useHUDState(function(s)
		return s.trainingQueue
	end)
	local currentWallPiece = HUDStore.useHUDState(function(s)
		return s.currentWallPiece
	end)
	local isPlacingWall = HUDStore.useHUDState(function(s)
		return s.isPlacingWall
	end)
	local isDeleteMode = HUDStore.useHUDState(function(s)
		return s.isDeleteMode
	end)
	local showPoliciesModal = HUDStore.useHUDState(function(s)
		return s.showPoliciesModal
	end)
	local showAbilityTree = HUDStore.useHUDState(function(s)
		return s.showAbilityTree
	end)
	local showTechTreeModal = HUDStore.useHUDState(function(s)
		return s.showTechTreeModal
	end)
	local showMenuModal = HUDStore.useHUDState(function(s)
		return s.showMenuModal
	end)
	local showStatsModal = HUDStore.useHUDState(function(s)
		return s.showStatsModal
	end)
	local cameraMode = HUDStore.useHUDState(function(s)
		return s.cameraMode
	end)
	local showHeroAbilities = HUDStore.useHUDState(function(s)
		return s.showHeroAbilities
	end)
	local heroAbilities = HUDStore.useHUDState(function(s)
		return s.heroAbilities
	end)
	local buildingUpgradeInfo = HUDStore.useHUDState(function(s)
		return s.buildingUpgradeInfo
	end)
	local selectedFormation = HUDStore.useHUDState(function(s)
		return s.selectedFormation
	end)
	local selectedStance = HUDStore.useHUDState(function(s)
		return s.selectedStance
	end)
	local kingHealth = HUDStore.useHUDState(function(s)
		return s.kingHealth
	end)
	local kingMaxHealth = HUDStore.useHUDState(function(s)
		return s.kingMaxHealth
	end)
	local keepCapture = HUDStore.useHUDState(function(s)
		return s.keepCapture
	end)
	local estateCapture = HUDStore.useHUDState(function(s)
		return s.estateCapture
	end)
	local happiness = HUDStore.useHUDState(function(s)
		return s.happiness
	end)
	local economySnapshot = HUDStore.useHUDState(function(s)
		return s.economySnapshot
	end)
	local activeQuests = HUDStore.useHUDState(function(s)
		return s.activeQuests
	end)
	local achievementData = HUDStore.useHUDState(function(s)
		return s.achievementData
	end)
	local showDeleteConfirmation = HUDStore.useHUDState(function(s)
		return s.showDeleteConfirmation
	end)
	local buildingToDelete = HUDStore.useHUDState(function(s)
		return s.buildingToDelete
	end)
	local showMultiDeleteConfirmation = HUDStore.useHUDState(function(s)
		return s.showMultiDeleteConfirmation
	end)
	local buildingsToDelete = HUDStore.useHUDState(function(s)
		return s.buildingsToDelete
	end)
	local multiDeleteRefund = HUDStore.useHUDState(function(s)
		return s.multiDeleteRefund
	end)
	local deletionHistory = HUDStore.useHUDState(function(s)
		return s.deletionHistory
	end)
	local battleLogMessages = HUDStore.useHUDState(function(s)
		return s.battleLogMessages
	end)
	local battleLogExpanded = HUDStore.useHUDState(function(s)
		return s.battleLogExpanded
	end)
	local tutorialEnabled = HUDStore.useHUDState(function(s)
		return s.tutorialEnabled
	end)
	local showKeepModal = HUDStore.useHUDState(function(s)
		return s.showKeepModal
	end)
	local tutorialStep = HUDStore.useHUDState(function(s)
		return s.tutorialStep
	end)
	local tutorialModalHidden = HUDStore.useHUDState(function(s)
		return s.tutorialModalHidden
	end)
	local gameStartData = HUDStore.useHUDState(function(s)
		return s.gameStartData
	end)
	local stats = HUDStore.useHUDState(function(s)
		return s.stats
	end)
	local armySize = HUDStore.useHUDState(function(s)
		return s.armySize
	end)

	-- Drawer open/closed is view-only chrome state, not game state, so it lives
	-- here rather than in HUDStore (which both shells share). Rotating a
	-- tablet across the compact breakpoint remounts this component, which
	-- correctly closes the drawer rather than leaving a stale one open.
	local drawerOpen, setDrawerOpen = React.useState(false)

	local hasUnitsSelected = #selectedUnits > 0
	local hasTrainingBuildingSelected = selectedTrainingBuilding ~= nil
	local hasProductionBuildingSelected = selectedProductionBuilding ~= nil
	local hasHeroAbilitiesActive = cameraMode == "King" and showHeroAbilities
	local hasUpgradeInfo = buildingUpgradeInfo ~= nil

	-- Same six-way priority DesktopShell's content area uses. Any one of these
	-- taking over DetailArea means the building-menu drawer is not the thing on
	-- screen -- exactly the "one level open at a time" rule.
	local detailActive = hasTrainingBuildingSelected
		or hasProductionBuildingSelected
		or hasHeroAbilitiesActive
		or hasUpgradeInfo
		or hasUnitsSelected

	-- A higher-priority selection takes over DetailArea; a still-open drawer
	-- underneath it would be exactly the "everything visible at once" habit
	-- the design doc calls out, so any of them force-closes it.
	React.useEffect(function()
		if detailActive and drawerOpen then
			setDrawerOpen(false)
		end
	end, { detailActive })

	local isArenaMode = gameStartData ~= nil and gameStartData.mode == "BattleArena"

	local showDrawer = drawerOpen and not detailActive
	local detailVisible = detailActive or showDrawer

	-- Battle Arena: bottom chrome (utility row, category chips, detail area)
	-- appears only with units selected -- players get formation/stance/
	-- selection controls but no build/economy UI. Mirrors DesktopShell's
	-- `Visible = not isArenaMode or hasUnitsSelected` on its BottomBar.
	local showBottomChrome = not isArenaMode or hasUnitsSelected

	local detailContent
	if hasTrainingBuildingSelected then
		detailContent = React.createElement(TrainingPanel, {
			selectedBuilding = selectedTrainingBuilding,
			queue = trainingQueue,
			onTrainUnit = function(unitType: string)
				if selectedTrainingBuilding then
					HUDStore.startTraining((selectedTrainingBuilding :: Model).Name, unitType)
				end
			end,
			onClose = function()
				HUDStore.closeTrainingPanel()
			end,
		})
	elseif hasProductionBuildingSelected then
		detailContent = React.createElement(WorkerAssignmentPanel, {
			selectedBuilding = selectedProductionBuilding,
			onAddWorker = function()
				if selectedProductionBuilding then
					HUDStore.assignWorker((selectedProductionBuilding :: Model).Name)
				end
			end,
			onRemoveWorker = function()
				if selectedProductionBuilding then
					HUDStore.unassignWorker((selectedProductionBuilding :: Model).Name)
				end
			end,
			onClose = function()
				HUDStore.closeProductionPanel()
			end,
		})
	elseif hasHeroAbilitiesActive then
		detailContent = React.createElement(HeroAbilitiesPanel, {
			abilities = heroAbilities,
			tooltip = props.tooltip,
			onAbilityUsed = function(abilityId: string)
				HUDStore.useAbility(abilityId)
			end,
		})
	elseif hasUpgradeInfo then
		detailContent = React.createElement(UpgradePanel, {
			buildingInfo = buildingUpgradeInfo,
			playerResources = resources,
			onUpgrade = function()
				HUDStore.upgradeBuilding(buildingUpgradeInfo.buildingId)
			end,
			onClose = function()
				HUDStore.closeUpgradePanel()
			end,
		})
	elseif hasUnitsSelected then
		detailContent = React.createElement(UnitSelectionPanel, {
			selectedUnits = selectedUnits,
			selectedFormation = selectedFormation,
			selectedStance = selectedStance,
			onStanceSelected = function(stanceName: string)
				HUDStore.selectStance(stanceName)
			end,
			onFormationSelected = function(formationType: string)
				HUDStore.selectFormation(formationType)
			end,
			onCivilianOrder = function(action: string)
				HUDStore.civilianOrder(selectedUnits, action)
			end,
		})
	elseif showDrawer then
		detailContent = React.createElement(BuildingMenu, {
			tooltip = props.tooltip,
			resources = resources,
			gloryLifetime = gloryLifetime,
			selectedCategory = selectedCategory,
			currentWallPiece = currentWallPiece,
			isPlacingWall = isPlacingWall,
			onBuildingSelected = function(buildingName: string)
				HUDStore.startPlacement(buildingName)
				setDrawerOpen(false)
			end,
		})
	else
		detailContent = nil
	end

	-- Category chips: tapping one always opens the drawer on that category
	-- (HUDStore.selectCategory also clears training/production/selectedUnits,
	-- same as Desktop's category tabs), tapping the active one again closes it.
	local categoryChips = {}
	for i, category in CATEGORIES do
		local isActiveTab = selectedCategory == category and showDrawer
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
				if selectedCategory == category and showDrawer then
					setDrawerOpen(false)
				else
					HUDStore.selectCategory(category)
					setDrawerOpen(true)
				end
			end,
		}, {
			Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, tokens.cornerRadius) }),
		})
	end

	-- Utility row: the icon cluster DesktopShell stacks vertically on the left
	-- of its bottom bar, laid out horizontally here since it lives in the
	-- thumb-zone strip instead of a tall sidebar.
	local hasDeletionHistory = #deletionHistory > 0
	local utilityIcons = {
		Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, tokens.padding),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		Delete = React.createElement(IconButton, {
			Name = "DeleteButton",
			LayoutOrder = 1,
			Size = UDim2.fromOffset(tokens.hitTarget, tokens.hitTarget),
			Icon = "🗑️",
			IconSize = 16 * tokens.fontScale,
			IconColor = UIConfig.HUD.PanelTextColor,
			ImageColor3 = isDeleteMode and UIConfig.HUD.CategoryButtonSelected or UIConfig.HUD.UtilityButtonBackground,
			OnClick = function()
				HUDStore.toggleDeleteMode()
			end,
		}),
		Policies = React.createElement(IconButton, {
			Name = "PoliciesButton",
			LayoutOrder = 2,
			Size = UDim2.fromOffset(tokens.hitTarget, tokens.hitTarget),
			Icon = "📜",
			IconSize = 18 * tokens.fontScale,
			IconColor = UIConfig.HUD.PanelTextColor,
			ImageColor3 = showPoliciesModal and UIConfig.HUD.CategoryButtonSelected
				or UIConfig.HUD.UtilityButtonBackground,
			OnClick = function()
				HUDStore.togglePoliciesModal()
			end,
		}),
		AbilityTree = React.createElement(IconButton, {
			Name = "AbilityTreeButton",
			LayoutOrder = 3,
			Size = UDim2.fromOffset(tokens.hitTarget, tokens.hitTarget),
			Icon = "⚜️",
			IconSize = 18 * tokens.fontScale,
			IconColor = UIConfig.HUD.PanelTextColor,
			ImageColor3 = showAbilityTree and UIConfig.HUD.CategoryButtonSelected
				or UIConfig.HUD.UtilityButtonBackground,
			OnClick = function()
				HUDStore.toggleAbilityTree()
			end,
		}),
		TechTree = React.createElement(IconButton, {
			Name = "TechTreeButton",
			LayoutOrder = 4,
			Size = UDim2.fromOffset(tokens.hitTarget, tokens.hitTarget),
			Icon = "🔬",
			IconSize = 18 * tokens.fontScale,
			IconColor = UIConfig.HUD.PanelTextColor,
			ImageColor3 = showTechTreeModal and UIConfig.HUD.CategoryButtonSelected
				or UIConfig.HUD.UtilityButtonBackground,
			OnClick = function()
				HUDStore.setTechTreeModal(not showTechTreeModal)
			end,
		}),
		Menu = React.createElement(IconButton, {
			Name = "MenuButton",
			LayoutOrder = 5,
			Size = UDim2.fromOffset(tokens.hitTarget, tokens.hitTarget),
			Icon = "☰",
			IconSize = 18 * tokens.fontScale,
			IconColor = UIConfig.HUD.PanelTextColor,
			ImageColor3 = showMenuModal and UIConfig.HUD.CategoryButtonSelected or UIConfig.HUD.UtilityButtonBackground,
			OnClick = function()
				HUDStore.setMenuModal(not showMenuModal)
			end,
		}),
		Stats = React.createElement(IconButton, {
			Name = "StatsButton",
			LayoutOrder = 6,
			Size = UDim2.fromOffset(tokens.hitTarget, tokens.hitTarget),
			Icon = "🏰",
			IconSize = 18 * tokens.fontScale,
			IconColor = UIConfig.HUD.PanelTextColor,
			ImageColor3 = showStatsModal and UIConfig.HUD.CategoryButtonSelected or UIConfig.HUD.UtilityButtonBackground,
			OnClick = function()
				HUDStore.setStatsModal(not showStatsModal)
			end,
		}),
	}

	-- Compact status row (honor/glory/population/date/weather/peace/victory).
	-- ResourceDisplay already covers Gold/Food/Wood/Stone/Weapons/Iron; this is
	-- the rest of what DesktopShell's TopBar shows, condensed into one line so
	-- the whole top strip stays display-only and well clear of the 60px rule
	-- by virtue of having no [React.Event.*] handlers at all, not by position.
	local victoryIcons: { [string]: string } = {
		Score = "🏆",
		Conquest = "⚔️",
		Wonder = "🏛",
		Regicide = "👑",
	}
	local weatherIcons: { [string]: string } = {
		Clear = "☀️",
		Rain = "🌧️",
		Storm = "⛈️",
		Drought = "🌵",
	}
	local function statusChip(text: string, layoutOrder: number, color: Color3?)
		return React.createElement("TextLabel", {
			LayoutOrder = layoutOrder,
			Size = UDim2.fromOffset(70 * tokens.fontScale, 20 * tokens.fontScale),
			BackgroundTransparency = 1,
			Text = text,
			Font = Enum.Font.GothamBold,
			TextSize = 13 * tokens.fontScale,
			TextColor3 = color or UIConfig.HUD.ResourceTextColor,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextStrokeTransparency = 0.5,
		})
	end

	local statusStrip = React.createElement("ScrollingFrame", {
		Name = "StatusStrip",
		Size = UDim2.new(1, 0, 0, 26),
		Position = UDim2.fromOffset(0, 36),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollingDirection = Enum.ScrollingDirection.X,
		ScrollBarThickness = 0,
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		CanvasSize = UDim2.fromScale(0, 0),
	}, {
		Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, tokens.padding),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		Weather = weather and statusChip(weatherIcons[weather] or "☀️", 1),
		Honor = statusChip(`🏅{honor}`, 2),
		Glory = statusChip(`🏆{glory}`, 3, Color3.fromRGB(255, 215, 0)),
		Population = statusChip(`👥{population}`, 4),
		Date = statusChip(date, 5),
		PeaceTime = peaceTimeRemaining > 0 and statusChip(
			string.format("🕊%d:%02d", math.floor(peaceTimeRemaining / 60), peaceTimeRemaining % 60),
			6,
			Color3.fromRGB(180, 220, 255)
		) or nil,
		Victory = statusChip(victoryIcons[victoryCondition] or "🏆", 7, Color3.fromRGB(255, 215, 100)),
	})

	-- Compact king health readout, same source data as DesktopShell's
	-- LordHealthBar but condensed to one thin bar instead of a boxed panel.
	local kingHealthBar = (function()
		local health = kingHealth or 0
		local maxHealth = math.max(kingMaxHealth or 1, 1)
		local fraction = math.clamp(health / maxHealth, 0, 1)
		local barColor = if fraction > 0.5
			then Color3.fromRGB(90, 170, 80)
			elseif fraction > 0.25 then Color3.fromRGB(210, 160, 60)
			else Color3.fromRGB(190, 60, 50)
		return React.createElement("Frame", {
			Name = "KingHealthBar",
			Size = UDim2.new(0.5, -tokens.padding * 2, 0, 16),
			Position = UDim2.fromOffset(tokens.padding, TOP_CHROME_HEIGHT + 4),
			BackgroundColor3 = Color3.fromRGB(40, 40, 40),
			BorderSizePixel = 1,
			BorderColor3 = UIConfig.HUD.MeterBorder,
		}, {
			Fill = React.createElement("Frame", {
				Size = UDim2.fromScale(fraction, 1),
				BackgroundColor3 = barColor,
				BorderSizePixel = 0,
			}),
			Label = React.createElement("TextLabel", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Text = string.format("👑 %d/%d", math.floor(health), math.floor(maxHealth)),
				Font = Enum.Font.GothamBold,
				TextSize = 11 * tokens.fontScale,
				TextColor3 = Color3.fromRGB(255, 255, 255),
				TextStrokeTransparency = 0.4,
			}),
		})
	end)()

	-- Compact happiness/revolt readout -- the one thing DesktopShell's
	-- always-visible MeterPanel shows that isn't also on the Stats modal
	-- (which mobile reaches via the Stats utility icon and covers the rest:
	-- economy health, housing, tax rate, food consumption).
	local happinessBar = React.createElement("Frame", {
		Name = "HappinessBar",
		Size = UDim2.new(0.5, -tokens.padding * 2, 0, 16),
		Position = UDim2.new(0.5, tokens.padding, 0, TOP_CHROME_HEIGHT + 4),
		BackgroundColor3 = Color3.fromRGB(40, 40, 40),
		BorderSizePixel = 1,
		BorderColor3 = UIConfig.HUD.MeterBorder,
	}, {
		HappyFill = React.createElement("Frame", {
			Size = UDim2.new(happiness / 100, 0, 1, 0),
			BackgroundColor3 = UIConfig.HUD.MeterHappyColor,
			BorderSizePixel = 0,
		}),
		RevoltFill = React.createElement("Frame", {
			Size = UDim2.new(math.max(0, (50 - happiness) / 100), 0, 1, 0),
			Position = UDim2.new(1, 0, 0, 0),
			AnchorPoint = Vector2.new(1, 0),
			BackgroundColor3 = UIConfig.HUD.MeterRevoltColor,
			BorderSizePixel = 0,
		}),
		Label = React.createElement("TextLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Text = string.format("%s %d%%", if happiness >= 50 then "😊" else "😡", math.floor(happiness)),
			Font = Enum.Font.GothamBold,
			TextSize = 11 * tokens.fontScale,
			TextColor3 = Color3.fromRGB(255, 255, 255),
			TextStrokeTransparency = 0.4,
		}),
	})

	local keepCaptureBanner = keepCapture and (function()
		local capture = keepCapture :: any
		local isAttacker = capture.attacker
		local title = if isAttacker
			then string.format("⚔️ Seizing %s's Keep!", capture.keepOwnerName or "the enemy")
			else "🔥 KEEP UNDER ATTACK!"
		local accent = if isAttacker then Color3.fromRGB(214, 178, 94) else Color3.fromRGB(190, 60, 50)
		return React.createElement("Frame", {
			Name = "KeepCaptureBanner",
			Size = UDim2.new(0.85, 0, 0, 54),
			Position = UDim2.new(0.5, 0, 0, TOP_CHROME_HEIGHT + 26),
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundColor3 = Color3.fromRGB(30, 20, 18),
			BackgroundTransparency = 0.15,
			BorderSizePixel = 2,
			BorderColor3 = accent,
		}, {
			Title = React.createElement("TextLabel", {
				Size = UDim2.new(1, -70, 0, 24),
				Position = UDim2.fromOffset(10, 4),
				BackgroundTransparency = 1,
				Text = title,
				Font = Enum.Font.GothamBold,
				TextSize = 14 * tokens.fontScale,
				TextColor3 = accent,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
			}),
			Countdown = React.createElement("TextLabel", {
				Size = UDim2.fromOffset(64, 30),
				Position = UDim2.new(1, -70, 0, 2),
				BackgroundTransparency = 1,
				Text = string.format("%ds", capture.secondsRemaining or 0),
				Font = Enum.Font.GothamBold,
				TextSize = 20 * tokens.fontScale,
				TextColor3 = Color3.fromRGB(255, 255, 255),
				TextXAlignment = Enum.TextXAlignment.Right,
			}),
			BarContainer = React.createElement("Frame", {
				Size = UDim2.new(1, -20, 0, 10),
				Position = UDim2.new(0, 10, 1, -16),
				BackgroundColor3 = Color3.fromRGB(40, 40, 40),
				BorderSizePixel = 1,
				BorderColor3 = UIConfig.HUD.MeterBorder,
			}, {
				Fill = React.createElement("Frame", {
					Size = UDim2.fromScale(math.clamp(capture.fraction or 0, 0, 1), 1),
					BackgroundColor3 = accent,
					BorderSizePixel = 0,
				}),
			}),
		})
	end)() or nil

	local estateCaptureBar = estateCapture and (function()
		local capture = estateCapture :: any
		local isAttacker = capture.attacker
		local label = if isAttacker then "🚩 Capturing estate..." else "🚩 Estate under attack!"
		local accent = if isAttacker then Color3.fromRGB(120, 200, 120) else Color3.fromRGB(210, 140, 60)
		return React.createElement("Frame", {
			Name = "EstateCaptureBar",
			Size = UDim2.new(0.7, 0, 0, 40),
			Position = UDim2.new(0.5, 0, 0, TOP_CHROME_HEIGHT + 86),
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundColor3 = Color3.fromRGB(30, 25, 20),
			BackgroundTransparency = 0.25,
			BorderSizePixel = 2,
			BorderColor3 = UIConfig.HUD.MeterBorder,
		}, {
			Label = React.createElement("TextLabel", {
				Size = UDim2.new(1, -10, 0, 18),
				Position = UDim2.fromOffset(6, 2),
				BackgroundTransparency = 1,
				Text = label,
				Font = Enum.Font.GothamBold,
				TextSize = 12 * tokens.fontScale,
				TextColor3 = accent,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			BarContainer = React.createElement("Frame", {
				Size = UDim2.new(1, -12, 0, 8),
				Position = UDim2.new(0, 6, 1, -12),
				BackgroundColor3 = Color3.fromRGB(40, 40, 40),
				BorderSizePixel = 1,
				BorderColor3 = UIConfig.HUD.MeterBorder,
			}, {
				Fill = React.createElement("Frame", {
					Size = UDim2.fromScale(math.clamp(capture.fraction or 0, 0, 1), 1),
					BackgroundColor3 = accent,
					BorderSizePixel = 0,
				}),
			}),
		})
	end)() or nil

	-- Minimap hides while a detail panel/drawer is open (it would otherwise
	-- render underneath that panel's background) and while directly
	-- controlling the King, whose bottom-left thumbstick and bottom-right
	-- HeroTouchControls cluster already claim both corners the minimap could
	-- otherwise use.
	local showMiniMap = not isArenaMode and cameraMode ~= "King" and not detailVisible

	local tutorialModal = (function()
		if isArenaMode then
			return nil
		end
		local isKeepStep = tutorialStep == 1
		local showKeep = isKeepStep and showKeepModal
		local showTutorialStep = (not isKeepStep) and tutorialStep <= 3 and tutorialEnabled
		local shouldShow = not tutorialModalHidden and (showKeep or showTutorialStep)
		if not shouldShow then
			return nil
		end
		return React.createElement(TutorialModal, {
			visible = true,
			currentStep = tutorialStep,
			size = SHEET_SIZE,
			onBuildRequested = function(buildingType: string, isAutoTriggered: boolean?)
				HUDStore.requestTutorialBuild(buildingType, isAutoTriggered)
			end,
		})
	end)()

	return React.createElement("Frame", {
		Name = "MobileShell",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, {
		-- Display-only: no [React.Event.*] handlers anywhere in this frame,
		-- ever. That is the whole point of the 60px-clear-zone rule.
		TopStrip = (not isArenaMode) and React.createElement("Frame", {
			Name = "TopStrip",
			Size = UDim2.new(1, 0, 0, TOP_CHROME_HEIGHT),
			Position = UDim2.fromOffset(0, Platform.safeArea.Top),
			BackgroundColor3 = UIConfig.HUD.TopBarBackground,
			BackgroundTransparency = 0.1,
			BorderSizePixel = 0,
		}, {
			Resources = React.createElement("Frame", {
				Size = UDim2.new(1, 0, 0, 34),
				BackgroundTransparency = 1,
			}, {
				Display = React.createElement(ResourceDisplay, { resources = resources }),
			}),
			Status = statusStrip,
		}) or nil,

		FogOfWarIndicator = (not isArenaMode) and React.createElement(FogOverlay) or nil,
		KingHealthBar = kingHealthBar,
		HappinessBar = happinessBar,
		KeepCaptureBanner = keepCaptureBanner,
		EstateCaptureBar = estateCaptureBar,

		ViewToggle = React.createElement(ViewToggleButton, {
			-- Clears both the display-only top strip and the king-health/capture
			-- banner cluster stacked below it.
			topOffset = TOP_CHROME_HEIGHT + 96,
		}),
		HeroTouchControls = React.createElement(HeroTouchControls),

		MiniMapCluster = showMiniMap and React.createElement("Frame", {
			Name = "MiniMapCluster",
			Size = UDim2.fromOffset(96, 96),
			Position = UDim2.new(0, tokens.padding, 1, -(tokens.bottomBarHeight + tokens.padding + Platform.safeArea.Bottom)),
			AnchorPoint = Vector2.new(0, 1),
			BackgroundColor3 = Color3.fromRGB(0, 0, 0),
			BorderColor3 = UIConfig.HUD.MinimapBorder,
			BorderSizePixel = 2,
			ClipsDescendants = true,
		}, {
			Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
			MiniMap = React.createElement(MiniMap),
		}) or nil,

		BottomArea = showBottomChrome and React.createElement("Frame", {
			Name = "BottomArea",
			Size = UDim2.new(1, 0, 0, tokens.bottomBarHeight + (if detailVisible then DETAIL_HEIGHT else 0)),
			Position = UDim2.new(0, 0, 1, -Platform.safeArea.Bottom),
			AnchorPoint = Vector2.new(0, 1),
			BackgroundTransparency = 1,
		}, {
			-- One level open at a time: this is the ONLY detail surface on
			-- screen, and it closes itself the moment nothing needs it.
			DetailArea = detailVisible and React.createElement("Frame", {
				Name = "DetailArea",
				Size = UDim2.new(1, -tokens.padding * 2, 0, DETAIL_HEIGHT),
				Position = UDim2.fromOffset(tokens.padding, 0),
				BackgroundColor3 = UIConfig.HUD.ContentAreaBackground,
				BorderSizePixel = 0,
			}, {
				Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, tokens.cornerRadius) }),
				Padding = React.createElement("UIPadding", {
					PaddingTop = UDim.new(0, tokens.padding),
					PaddingBottom = UDim.new(0, tokens.padding),
					PaddingLeft = UDim.new(0, tokens.padding),
					PaddingRight = UDim.new(0, tokens.padding),
				}),
				Content = detailContent,
			}) or nil,

			ActionBar = React.createElement("Frame", {
				Name = "ActionBar",
				Size = UDim2.new(1, 0, 0, tokens.bottomBarHeight),
				Position = UDim2.new(0, 0, 1, 0),
				AnchorPoint = Vector2.new(0, 1),
				BackgroundColor3 = UIConfig.HUD.BottomBarBackground,
				BorderSizePixel = 0,
			}, {
				UtilityRow = React.createElement("Frame", {
					Name = "UtilityRow",
					Size = UDim2.new(1, 0, 0, UTILITY_ROW_HEIGHT),
					Position = UDim2.fromOffset(0, 0),
					BackgroundTransparency = 1,
				}, utilityIcons),

				CategoryRow = React.createElement("Frame", {
					Name = "CategoryRow",
					Size = UDim2.new(1, 0, 0, tokens.bottomBarHeight - UTILITY_ROW_HEIGHT),
					Position = UDim2.fromOffset(0, UTILITY_ROW_HEIGHT),
					BackgroundTransparency = 1,
				}, (function()
					local children = {
						Layout = React.createElement("UIListLayout", {
							FillDirection = Enum.FillDirection.Horizontal,
							HorizontalAlignment = Enum.HorizontalAlignment.Center,
							VerticalAlignment = Enum.VerticalAlignment.Center,
							Padding = UDim.new(0, tokens.padding),
						}),
					}
					for key, chip in categoryChips do
						children[key] = chip
					end
					return children
				end)()),
			}),
		}) or nil,

		UndoButton = (not isArenaMode) and hasDeletionHistory and React.createElement(UndoButton, {
			deletionHistory = deletionHistory,
			Position = UDim2.new(
				0,
				tokens.padding,
				1,
				-(tokens.bottomBarHeight + (if detailVisible then DETAIL_HEIGHT else 0) + Platform.safeArea.Bottom + 96 + tokens.padding)
			),
			onUndo = function()
				HUDStore.undoLastDeletion()
			end,
		}) or nil,

		QuestTrackerPanel = (not isArenaMode) and React.createElement(QuestTracker, {
			quests = activeQuests,
			position = UDim2.new(1, -290, 0, TOP_CHROME_HEIGHT + 4),
		}) or nil,

		AchievementNotificationOverlay = achievementData and React.createElement(AchievementNotification, {
			achievementData = achievementData,
			onDismiss = function()
				HUDStore.dismissAchievement()
			end,
		}) or nil,

		BattleLog = React.createElement(BattleLog, {
			messages = battleLogMessages,
			expanded = battleLogExpanded,
			onToggleExpanded = function()
				HUDStore.setState({ battleLogExpanded = not battleLogExpanded })
			end,
		}),

		PoliciesModal = showPoliciesModal and React.createElement(Policies, {
			visible = showPoliciesModal,
			happiness = happiness,
			size = SHEET_SIZE,
			onClose = function()
				HUDStore.togglePoliciesModal()
			end,
		}) or nil,

		AbilityTreeModal = showAbilityTree and React.createElement(AbilityTreePanel, {
			visible = showAbilityTree,
			tooltip = props.tooltip,
			size = SHEET_SIZE,
			onClose = function()
				HUDStore.toggleAbilityTree()
			end,
		}) or nil,

		MenuModal = showMenuModal and React.createElement(Menu, {
			visible = showMenuModal,
			size = SHEET_SIZE,
			onClose = function()
				HUDStore.setMenuModal(false)
			end,
			navigate = props.navigate,
		}) or nil,

		StatsModal = showStatsModal and React.createElement(Stats, {
			visible = showStatsModal,
			size = SHEET_SIZE,
			onClose = function()
				HUDStore.setStatsModal(false)
			end,
			stats = stats,
			population = population,
			armySize = armySize,
			honor = honor,
			glory = glory,
			happiness = happiness,
			economySnapshot = economySnapshot,
		}) or nil,

		TechTreeModal = showTechTreeModal and React.createElement(TechTree, {
			visible = showTechTreeModal,
			playerResources = resources,
			size = SHEET_SIZE,
			onClose = function()
				HUDStore.setTechTreeModal(false)
			end,
			onResearchStarted = function(techId: string)
				HUDStore.startResearch(techId)
			end,
		}) or nil,

		DeleteConfirmationModal = showDeleteConfirmation and buildingToDelete and ConfirmDeleteModal.new({
			buildingName = buildingToDelete.name,
			buildingType = buildingToDelete.type,
			refundInfo = buildingToDelete.refundInfo,
			onConfirm = function()
				HUDStore.confirmDelete()
			end,
			onCancel = function()
				HUDStore.cancelDelete()
			end,
		}) or nil,

		MultiDeleteConfirmationModal = showMultiDeleteConfirmation and #buildingsToDelete > 0 and MultiDeleteModal.new({
			buildings = buildingsToDelete,
			totalRefund = multiDeleteRefund,
			onConfirm = function(selectedBuildings: { any })
				HUDStore.confirmMultiDelete(selectedBuildings)
			end,
			onCancel = function()
				HUDStore.cancelMultiDelete()
			end,
		}) or nil,

		TutorialModal = tutorialModal,
	})
end

return MobileShell
