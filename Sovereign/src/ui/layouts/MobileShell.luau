--!strict
-- MobileShell: chrome for the touch layout, rebuilt against Theme.luau /
-- BuildingCatalog.luau instead of the old brown-PNG UIConfig chrome. The
-- previous version of this file was a faithful port of the desktop HUD's
-- look; the user rejected that look outright, so every visual choice below is
-- new. What carries over is only the KNOWLEDGE of which HUDStore fields and
-- panels exist -- the props each still-shared panel needs are unchanged.
--
-- ---------------------------------------------------------------------------
-- THE FIVE BOTTOM-ZONE STATES
-- ---------------------------------------------------------------------------
-- Exactly one "mode" owns the bottom zone at a time, chosen by `mode` below in
-- this priority order (highest first):
--
--   1. Placing   -- isPlacingBuilding: a gold-bordered Confirm/Cancel banner,
--                   full width, replacing the rail entirely.
--   2. Units     -- selectedUnits non-empty: UnitSelectionPanel, full width.
--   3. Building  -- a training or production building is selected: TrainingPanel
--                   (existing component) or the new WorkerPanel, full width.
--   4. Drawer    -- a category is open: BuildDrawer slides up ABOVE the rail
--                   (the rail stays visible -- you need it to close the drawer
--                   or switch categories).
--   5. Idle      -- rail only.
--
-- Modes 1-3 hide the rail; only mode 4 shows rail + drawer together. This is
-- the reading of "exactly one of these renders at a time" used here: the 5
-- items in the brief are UI MODES, and the drawer's mode is defined as "rail
-- plus drawer", not the drawer alone.
--
-- ---------------------------------------------------------------------------
-- KNOWN GAP: PLACING CONFIRM/CANCEL
-- ---------------------------------------------------------------------------
-- Placement confirm is a ground tap handled entirely by PlacementController
-- (src/client), and cancel is Escape/right-click there -- neither route runs
-- through HUDStore today, and `isPlacingBuilding` has never had a UI consumer
-- before this file (nothing previously set it back to false). Cancel/Confirm
-- here only clear the shared HUDStore flags via HUDStore.setState (the same
-- public call the old file already used for battleLogExpanded), which makes
-- the banner disappear and keeps DesktopShell in sync -- but it does NOT stop
-- PlacementController's ghost from following the mouse or tell the server the
-- placement ended. A real fix needs a HUDStore.cancelPlacement() action wired
-- to the "PlacementEnded" remote and a touch-tap handler in
-- PlacementController; both are outside this file's scope (HUDStore.luau is
-- explicitly off-limits here).
--
-- ---------------------------------------------------------------------------
-- KNOWN GAP: SINGLE-BUILDING DELETE
-- ---------------------------------------------------------------------------
-- `showDeleteConfirmation` / `buildingToDelete` have existed in HUDStore since
-- the panel migration but nothing has ever set them to true -- only the
-- world-drag multi-delete path populates its sibling fields. WorkerPanel's
-- Delete button is the first thing to populate them (via HUDStore.setState),
-- which makes the already-wired ConfirmDeleteModal below functional for a
-- single building for the first time.
--
-- ---------------------------------------------------------------------------
-- DROPPED FROM THE OLD FILE
-- ---------------------------------------------------------------------------
-- The old file's compact King-health bar, happiness bar and keep/estate
-- capture banners are not carried over. Happiness now lives in
-- TopStatusStrip's row two; the brief's "everything else HUDStore drives must
-- still be reachable" list does not include kingHealth/keepCapture/
-- estateCapture, and siege/army UI is explicitly a separate pending task
-- ("design the army selection state"). Reintroducing them well means knowing
-- what that task lands on, so they are left out rather than guessed at here.

local React = require(game.ReplicatedStorage.Packages.react)

local Theme = require(script.Parent.Parent.Theme)
local Platform = require(script.Parent.Parent.Platform)
local HUDStore = require(script.Parent.Parent.state.HUDStore)
local BuildingCatalog = require(script.Parent.Parent.BuildingCatalog)

local TopStatusStrip = require(script.Parent.Parent.panels.TopStatusStrip)
local CategoryRail = require(script.Parent.Parent.panels.CategoryRail)
local BuildDrawer = require(script.Parent.Parent.panels.BuildDrawer)
local PlacementBanner = require(script.Parent.Parent.panels.PlacementBanner)
local WorkerPanel = require(script.Parent.Parent.panels.WorkerPanel)
local UtilityRow = require(script.Parent.Parent.panels.UtilityRow)

local FogOverlay = require(script.Parent.Parent.screens.HUD.FogOverlay)
local MiniMap = require(script.Parent.Parent.screens.HUD.MiniMap)
local UnitSelectionPanel = require(script.Parent.Parent.screens.HUD.UnitSelectionPanel)
local TrainingPanel = require(script.Parent.Parent.screens.HUD.TrainingPanel)
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
local ViewToggleButton = require(script.Parent.Parent.screens.HUD.ViewToggleButton)
local HeroTouchControls = require(script.Parent.Parent.screens.HUD.HeroTouchControls)

export type Props = {
	tooltip: any?,
	navigate: ((string) -> ())?,
}

-- Modals become near-fullscreen sheets on mobile. HeroAbilitiesPanel and
-- UpgradePanel don't take a `size` prop (their root is always
-- UDim2.fromScale(1, 1)), so they get this same footprint by being wrapped in
-- a container of this size instead -- see heroAbilitiesSheet/upgradeSheet
-- below. That is also why they are treated as sheets here rather than as a
-- bottom-zone mode: the brief groups Policies/Menu/Stats/TechTree/AbilityTree/
-- HeroAbilities/Upgrade together as "modals" needing this treatment, and the
-- bottom-zone's five states have no slot for either of them.
local SHEET_SIZE = UDim2.fromScale(0.96, 0.94)

local function MobileShell(props: Props)
	local resources = HUDStore.useHUDState(function(s)
		return s.resources
	end)
	local population = HUDStore.useHUDState(function(s)
		return s.population
	end)
	local economySnapshot = HUDStore.useHUDState(function(s)
		return s.economySnapshot
	end)
	local happiness = HUDStore.useHUDState(function(s)
		return s.happiness
	end)
	local armySize = HUDStore.useHUDState(function(s)
		return s.armySize
	end)
	local date = HUDStore.useHUDState(function(s)
		return s.date
	end)
	local gloryLifetime = HUDStore.useHUDState(function(s)
		return s.gloryLifetime
	end)
	-- Not shown in the new top strip (row two only has happiness/army/date/
	-- alerts), but Stats.luau still reads these, so they're still fetched here.
	local honor = HUDStore.useHUDState(function(s)
		return s.honor
	end)
	local glory = HUDStore.useHUDState(function(s)
		return s.glory
	end)
	local activeQuests = HUDStore.useHUDState(function(s)
		return s.activeQuests
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
	local isPlacingBuilding = HUDStore.useHUDState(function(s)
		return s.isPlacingBuilding
	end)
	local selectedBuildingName = HUDStore.useHUDState(function(s)
		return s.selectedBuilding
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

	-- Drawer open/closed is view-only chrome state, same reasoning as the old
	-- file: it isn't game state, so it doesn't belong in HUDStore, and a
	-- remount (e.g. rotating a tablet across the compact breakpoint) correctly
	-- starts closed rather than reopening a stale drawer.
	local drawerOpen, setDrawerOpen = React.useState(false)

	local hasUnitsSelected = #selectedUnits > 0
	local hasTrainingBuildingSelected = selectedTrainingBuilding ~= nil
	local hasProductionBuildingSelected = selectedProductionBuilding ~= nil
	local isPlacing = isPlacingBuilding and selectedBuildingName ~= nil
	local hasHeroAbilitiesActive = cameraMode == "King" and showHeroAbilities
	local hasUpgradeInfo = buildingUpgradeInfo ~= nil
	local isArenaMode = gameStartData ~= nil and gameStartData.mode == "BattleArena"

	-- A higher-priority mode force-closes the drawer, same "one thing open at a
	-- time" rule the old file enforced for its DetailArea.
	React.useEffect(function()
		local forceClose = isPlacing or hasUnitsSelected or hasTrainingBuildingSelected or hasProductionBuildingSelected
		if forceClose and drawerOpen then
			setDrawerOpen(false)
		end
	end, { isPlacing, hasUnitsSelected, hasTrainingBuildingSelected, hasProductionBuildingSelected })

	local function handleCategorySelect(category: string)
		if selectedCategory == category and drawerOpen then
			setDrawerOpen(false)
		else
			HUDStore.selectCategory(category)
			setDrawerOpen(true)
		end
	end

	-- Battle Arena: bottom chrome only appears with units selected (formation/
	-- stance/civilian orders), mirroring DesktopShell's Arena gate -- no build
	-- menu or economy UI in that mode.
	local showBottomChrome = not isArenaMode or hasUnitsSelected

	local detailContent: any = nil
	local showRail = false

	if isPlacing then
		detailContent = React.createElement(PlacementBanner, {
			LayoutOrder = 1,
			buildingName = selectedBuildingName :: string,
			-- Confirm just dismisses the banner: the actual placement is a
			-- ground tap owned by PlacementController, and the server
			-- confirms it back through "BuildingPlaced".
			onConfirm = function()
				HUDStore.setState({ isPlacingBuilding = false, selectedBuilding = HUDStore.None })
			end,
			-- Cancel must go through the store action, which also tears down
			-- PlacementController's ghost. Clearing the flags alone would leave
			-- its `isPlacing` armed, and that blocks all RTS input game-wide.
			onCancel = HUDStore.cancelPlacement,
		})
	elseif hasUnitsSelected then
		detailContent = React.createElement("Frame", {
			Name = "UnitsPanel",
			LayoutOrder = 1,
			Size = UDim2.new(1, 0, 0, Theme.Metrics.DrawerMaxHeight),
			BackgroundColor3 = Theme.Color.SurfaceRaised,
			BackgroundTransparency = Theme.Transparency.Drawer,
			BorderSizePixel = 0,
		}, {
			Corner = React.createElement("UICorner", { CornerRadius = Theme.corner(Theme.Metrics.RadiusCard) }),
			Stroke = React.createElement("UIStroke", Theme.strokeProps()),
			Content = React.createElement(UnitSelectionPanel, {
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
			}),
		})
	elseif hasTrainingBuildingSelected then
		detailContent = React.createElement("Frame", {
			Name = "TrainingPanelContainer",
			LayoutOrder = 1,
			Size = UDim2.new(1, 0, 0, Theme.Metrics.DrawerMaxHeight),
			BackgroundColor3 = Theme.Color.SurfaceRaised,
			BackgroundTransparency = Theme.Transparency.Drawer,
			BorderSizePixel = 0,
		}, {
			Corner = React.createElement("UICorner", { CornerRadius = Theme.corner(Theme.Metrics.RadiusCard) }),
			Stroke = React.createElement("UIStroke", Theme.strokeProps()),
			Content = React.createElement(TrainingPanel, {
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
			}),
		})
	elseif hasProductionBuildingSelected then
		local building = selectedProductionBuilding :: Model
		detailContent = React.createElement(WorkerPanel, {
			LayoutOrder = 1,
			building = building,
			onAddWorker = function()
				HUDStore.assignWorker(building.Name)
			end,
			onRemoveWorker = function()
				HUDStore.unassignWorker(building.Name)
			end,
			onDelete = function()
				-- First writer of these fields anywhere in the codebase -- see the
				-- module comment's "single-building delete" note.
				HUDStore.setState({
					showDeleteConfirmation = true,
					buildingToDelete = {
						name = building.Name,
						type = building:GetAttribute("BuildingType"),
						refundInfo = nil,
					},
				})
			end,
			onClose = function()
				HUDStore.closeProductionPanel()
			end,
		})
	elseif drawerOpen then
		showRail = true
		detailContent = React.createElement(BuildDrawer, {
			LayoutOrder = 1,
			category = selectedCategory,
			resources = resources,
			gloryLifetime = gloryLifetime,
			onSelectBuilding = function(buildingName: string)
				HUDStore.startPlacement(buildingName)
				setDrawerOpen(false)
			end,
		})
	else
		showRail = true
	end

	local bottomZoneChildren: { [string]: any } = {
		Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			Padding = UDim.new(0, Theme.Metrics.Gap),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		Padding = React.createElement("UIPadding", {
			PaddingLeft = UDim.new(0, Theme.Metrics.Pad),
			PaddingRight = UDim.new(0, Theme.Metrics.Pad),
			PaddingBottom = UDim.new(0, Theme.Metrics.Pad),
		}),
	}
	if detailContent then
		bottomZoneChildren.Detail = detailContent
	end
	if showRail then
		bottomZoneChildren.Rail = React.createElement(CategoryRail, {
			LayoutOrder = 2,
			categories = BuildingCatalog.getCategories(),
			activeCategory = drawerOpen and selectedCategory or nil,
			onSelect = handleCategorySelect,
		})
	end

	-- Utility icons docked top-left, below the display-only strip -- see the
	-- module comment on why top-left rather than the bottom zone.
	local utilityTop = Platform.safeArea.Top + Theme.Metrics.TopSafeZone + Theme.Metrics.Gap
	local hasDeletionHistory = #deletionHistory > 0

	local utilityItems = {
		{
			key = "Delete",
			icon = "🗑",
			active = isDeleteMode,
			onClick = function()
				HUDStore.toggleDeleteMode()
			end,
		},
		{
			key = "Policies",
			icon = "📜",
			active = showPoliciesModal,
			onClick = function()
				HUDStore.togglePoliciesModal()
			end,
		},
		{
			key = "AbilityTree",
			icon = "⚜",
			active = showAbilityTree,
			onClick = function()
				HUDStore.toggleAbilityTree()
			end,
		},
		{
			key = "TechTree",
			icon = "🔬",
			active = showTechTreeModal,
			onClick = function()
				HUDStore.setTechTreeModal(not showTechTreeModal)
			end,
		},
		{
			key = "Menu",
			icon = "☰",
			active = showMenuModal,
			onClick = function()
				HUDStore.setMenuModal(not showMenuModal)
			end,
		},
		{
			key = "Stats",
			icon = "🏰",
			active = showStatsModal,
			onClick = function()
				HUDStore.setStatsModal(not showStatsModal)
			end,
		},
	}

	-- Minimap hides while directly controlling the King: HeroTouchControls then
	-- claims the same screen region and the map isn't actionable mid-combat.
	local showMiniMap = not isArenaMode and cameraMode ~= "King"
	local minimapTop = Platform.safeArea.Top + Theme.Metrics.TopSafeZone + Theme.Metrics.Gap

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

	local populationCap = (economySnapshot and economySnapshot.housingCapacity) or population

	return React.createElement("Frame", {
		Name = "MobileShell",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, {
		-- Display-only: no [React.Event.*] handler anywhere inside TopStatusStrip.
		TopStrip = (not isArenaMode) and React.createElement("Frame", {
			Name = "TopStrip",
			Size = UDim2.new(1, 0, 0, Theme.Metrics.TopSafeZone),
			Position = UDim2.fromOffset(0, Platform.safeArea.Top),
			BackgroundTransparency = 1,
		}, {
			Strip = React.createElement(TopStatusStrip, {
				resources = resources,
				population = population,
				populationCap = populationCap,
				happiness = happiness,
				armySize = armySize,
				date = date,
				-- HUDStore has no dedicated "alerts" field; active quest count is
				-- the closest existing proxy for "things wanting attention".
				alertCount = #activeQuests,
			}),
		}) or nil,

		FogOfWarIndicator = (not isArenaMode) and React.createElement(FogOverlay) or nil,

		UtilityRow = (not isArenaMode) and React.createElement("Frame", {
			Name = "UtilityRowSlot",
			Position = UDim2.fromOffset(Theme.Metrics.Pad, utilityTop),
			Size = UDim2.new(0, 0, 0, Theme.Metrics.TouchTarget),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
		}, {
			Row = React.createElement(UtilityRow, { items = utilityItems }),
		}) or nil,

		UndoButton = (not isArenaMode) and hasDeletionHistory and React.createElement(UndoButton, {
			deletionHistory = deletionHistory,
			Position = UDim2.fromOffset(Theme.Metrics.Pad, utilityTop + Theme.Metrics.TouchTarget + Theme.Metrics.Gap),
			onUndo = function()
				HUDStore.undoLastDeletion()
			end,
		}) or nil,

		ViewToggle = React.createElement(ViewToggleButton, {
			topOffset = minimapTop + Theme.Metrics.MinimapMobile + Theme.Metrics.Gap,
		}),
		HeroTouchControls = React.createElement(HeroTouchControls),

		MiniMapCluster = showMiniMap and React.createElement("Frame", {
			Name = "MiniMapCluster",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -Theme.Metrics.Pad, 0, minimapTop),
			Size = UDim2.fromOffset(Theme.Metrics.MinimapMobile, Theme.Metrics.MinimapMobile),
			BackgroundColor3 = Theme.Color.Surface,
			BackgroundTransparency = Theme.Transparency.Panel,
			ClipsDescendants = true,
		}, {
			Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
			Stroke = React.createElement("UIStroke", Theme.strokeProps()),
			MiniMap = React.createElement(MiniMap),
		}) or nil,

		BottomZone = showBottomChrome and React.createElement("Frame", {
			Name = "BottomZone",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 0, 1, -Platform.safeArea.Bottom),
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
		}, bottomZoneChildren) or nil,

		QuestTrackerPanel = (not isArenaMode) and React.createElement(QuestTracker, {
			quests = activeQuests,
			position = UDim2.new(
				1,
				-290,
				0,
				minimapTop + Theme.Metrics.MinimapMobile + Theme.Metrics.Gap + Theme.Metrics.TouchTarget * 2 + Theme.Metrics.GapLoose
			),
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

		-- HeroAbilitiesPanel/UpgradePanel ignore any `size` prop and always fill
		-- their parent (Size = UDim2.fromScale(1, 1)), so the sheet footprint
		-- comes from THIS wrapper rather than from the panel itself.
		HeroAbilitiesSheet = hasHeroAbilitiesActive and React.createElement("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, 0),
			Size = SHEET_SIZE,
			BackgroundTransparency = 1,
		}, {
			Content = React.createElement(HeroAbilitiesPanel, {
				abilities = heroAbilities,
				tooltip = props.tooltip,
				onAbilityUsed = function(abilityId: string)
					HUDStore.useAbility(abilityId)
				end,
			}),
		}) or nil,

		UpgradeSheet = hasUpgradeInfo and React.createElement("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, 0),
			Size = SHEET_SIZE,
			BackgroundTransparency = 1,
		}, {
			-- buildingInfo/building prop-name mismatch (UpgradePanel reads
			-- `props.building`) is pre-existing -- buildingUpgradeInfo is never
			-- populated server-side today, per HUDStore's own comment, so this
			-- path has never rendered content. Kept byte-identical to the old
			-- wiring rather than "fixed" here, since UpgradePanel.luau is outside
			-- this file's scope.
			Content = React.createElement(UpgradePanel, {
				buildingInfo = buildingUpgradeInfo,
				playerResources = resources,
				onUpgrade = function()
					HUDStore.upgradeBuilding(buildingUpgradeInfo.buildingId)
				end,
				onClose = function()
					HUDStore.closeUpgradePanel()
				end,
			}),
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
