--!strict
-- DesktopShell: chrome for the mouse/keyboard layout.
--
-- ---------------------------------------------------------------------------
-- REBUILT, NOT PORTED
-- ---------------------------------------------------------------------------
-- The previous version of this file was a pixel-copy of HUD.luau's old brown
-- PNG chrome (a 300px ImageLabel bottom bar, image-button category tabs at
-- hardcoded pixel positions, a 210px minimap in a hand-drawn ring). The user
-- rejected that look outright. This version keeps only the FEATURE inventory
-- the old file proved out -- which HUDStore fields exist, which panels and
-- modals get mounted, and the same selection-priority order for the
-- contextual panel -- and draws all of it in Theme's flat dark vocabulary
-- instead: Frames with BackgroundTransparency + UIStroke, no ImageLabel
-- chrome, no rbxassetid:// backgrounds anywhere DesktopShell itself draws.
--
-- The legacy per-panel screens under screens/HUD (Policies, Stats, TechTree,
-- TrainingPanel, UnitSelectionPanel, MiniMap, BattleLog, ...) still draw with
-- UIConfig's old palette internally -- migrating THEIR insides to Theme is a
-- separate task from rebuilding the shell that hosts them, so they are
-- mounted here unchanged. Two things this shell used to draw itself have been
-- replaced with new Theme-based components instead of ported: the top status
-- row (screens/HUD/TopBar.luau, an ImageLabel stretched over a fixed PNG) is
-- now panels/DesktopTopBar.luau, and the category tabs + bare-icon build grid
-- (screens/HUD/BuildingMenu.luau) are now panels/DesktopBuildingGrid.luau,
-- which draws from BuildingCatalog instead of raw GameData so every tile can
-- show cost/output/staffing text the old grid never had.
--
-- ---------------------------------------------------------------------------
-- WHY THE BUILDING GRID IS ALWAYS ON SCREEN
-- ---------------------------------------------------------------------------
-- Mobile's drawer (tap a category, a panel opens, one thing visible at a
-- time) exists because thumb-zone screen space is scarce. Desktop has no such
-- constraint, so the design brief calls for "everything visible at once": the
-- building grid for the active category renders continuously in the bottom
-- bar's centre, and a contextual panel (Training/Production/Hero Abilities/
-- Upgrade/Unit Selection -- the same priority order the old contentAreaChild
-- switch used) docks to its right ONLY while one of those is active, rather
-- than replacing the grid outright the way the old single content-area slot
-- did. See `contextualPanel` below for the exact chain, and `showGrid` for
-- the one case (Battle Arena) where the grid is suppressed entirely so the
-- panel can have the whole bar.

local React = require(game.ReplicatedStorage.Packages.react)

local Theme = require(script.Parent.Parent.Theme)
local HUDStore = require(script.Parent.Parent.state.HUDStore)

local DesktopTopBar = require(script.Parent.Parent.panels.DesktopTopBar)
local DesktopBuildingGrid = require(script.Parent.Parent.panels.DesktopBuildingGrid)

local MiniMap = require(script.Parent.Parent.screens.HUD.MiniMap)
local FogOverlay = require(script.Parent.Parent.screens.HUD.FogOverlay)
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
local ViewToggleButton = require(script.Parent.Parent.screens.HUD.ViewToggleButton)
local HeroTouchControls = require(script.Parent.Parent.screens.HUD.HeroTouchControls)

export type Props = {
	tooltip: any?,
	navigate: ((string) -> ())?,
}

-- Bottom bar height. This used to reuse the mobile drawer's 330px on the
-- reasoning that both surfaces host the build menu -- but the drawer is
-- TRANSIENT (opened to pick a building, then dismissed) whereas this bar is
-- permanent. 330px of permanent chrome is a third of a 1080p screen handed over
-- for good, and it read as a black slab across the bottom of the battlefield.
local BOTTOM_BAR_HEIGHT = Theme.Metrics.BottomBarDesktop

-- Width of the contextual panel dock when one of Training/Production/Hero
-- Abilities/Upgrade/Unit Selection is active. No Theme token models "one
-- side panel's width" -- this is a shell-specific layout constant, same
-- convention MobileShell uses for its own DETAIL_HEIGHT/SHEET_SIZE.
local CONTEXT_DOCK_WIDTH = 360

-- Minimap + view-toggle dock, bottom-right, sized to hold ViewToggleButton's
-- stacked two-button cluster (44px tall each + 8px gap on desktop) beside the
-- minimap without either clipping.
local MINIMAP_SIZE = Theme.Metrics.MinimapDesktop
local TOGGLE_SLOT_WIDTH = 150
local DOCK_HEIGHT = 96

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
	local population = HUDStore.useHUDState(function(s)
		return s.population
	end)
	local selectedUnits = HUDStore.useHUDState(function(s)
		return s.selectedUnits
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

	local hasUnitsSelected = #selectedUnits > 0
	local hasTrainingBuildingSelected = selectedTrainingBuilding ~= nil
	local hasProductionBuildingSelected = selectedProductionBuilding ~= nil

	-- Battle Arena mode: no economy, so the build grid is suppressed entirely
	-- (`showGrid` below) and the bottom bar itself only appears once units are
	-- selected, giving the whole bar to formation/stance controls.
	local isArenaMode = gameStartData ~= nil and gameStartData.mode == "BattleArena"
	local showGrid = not isArenaMode

	-- Same priority order the old contentAreaChild switch used. The one
	-- change from the legacy chain: there is no final "else BuildingMenu"
	-- branch, because the grid is no longer this switch's fallback -- it is
	-- its own always-present element (see showGrid above and the bottom bar
	-- layout below).
	local contextualPanel
	if hasTrainingBuildingSelected then
		contextualPanel = React.createElement(TrainingPanel, {
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
		contextualPanel = React.createElement(WorkerAssignmentPanel, {
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
	elseif cameraMode == "King" and showHeroAbilities then
		contextualPanel = React.createElement(HeroAbilitiesPanel, {
			abilities = heroAbilities,
			tooltip = props.tooltip,
			onAbilityUsed = function(abilityId: string)
				HUDStore.useAbility(abilityId)
			end,
		})
	elseif buildingUpgradeInfo then
		contextualPanel = React.createElement(UpgradePanel, {
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
		contextualPanel = React.createElement(UnitSelectionPanel, {
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
	else
		contextualPanel = nil
	end

	local hasContextDock = contextualPanel ~= nil

	local bottomBarChildren: { [string]: any } = {}
	if showGrid then
		bottomBarChildren.GridArea = React.createElement("Frame", {
			Name = "GridArea",
			Size = UDim2.new(1, hasContextDock and -(CONTEXT_DOCK_WIDTH + Theme.Metrics.Gap) or 0, 1, 0),
			BackgroundTransparency = 1,
		}, {
			Padding = React.createElement("UIPadding", {
				PaddingTop = UDim.new(0, Theme.Metrics.Pad),
				PaddingBottom = UDim.new(0, Theme.Metrics.Pad),
				PaddingLeft = UDim.new(0, Theme.Metrics.Pad),
				PaddingRight = UDim.new(0, Theme.Metrics.Pad),
			}),
			Grid = React.createElement(DesktopBuildingGrid, { tooltip = props.tooltip }),
		})
	end
	if hasContextDock then
		bottomBarChildren.ContextDock = React.createElement("Frame", {
			Name = "ContextDock",
			AnchorPoint = if showGrid then Vector2.new(1, 0) else Vector2.new(0, 0),
			Position = if showGrid then UDim2.new(1, 0, 0, 0) else UDim2.new(0, 0, 0, 0),
			Size = if showGrid then UDim2.new(0, CONTEXT_DOCK_WIDTH, 1, 0) else UDim2.new(1, 0, 1, 0),
			BackgroundTransparency = 1,
		}, {
			Padding = React.createElement("UIPadding", {
				PaddingTop = UDim.new(0, Theme.Metrics.Pad),
				PaddingBottom = UDim.new(0, Theme.Metrics.Pad),
				PaddingLeft = UDim.new(0, Theme.Metrics.Pad),
				PaddingRight = UDim.new(0, Theme.Metrics.Pad),
			}),
			Content = contextualPanel,
		})
	end

	-- ===== LORD HEALTH BAR ===== (persistent; fed by "KingHealthUpdate")
	local lordHealthBar = (function()
		local health = kingHealth or 0
		local maxHealth = math.max(kingMaxHealth or 1, 1)
		local fraction = math.clamp(health / maxHealth, 0, 1)
		local barColor = if fraction > 0.5
			then Theme.Color.Success
			elseif fraction > 0.25 then Theme.Color.Warning
			else Theme.Color.Danger
		return React.createElement("Frame", {
			Name = "LordHealthBar",
			Size = UDim2.fromOffset(220, 34),
			Position = UDim2.fromOffset(Theme.Metrics.Pad, Theme.Metrics.ActionBarHeight + Theme.Metrics.Pad),
			BackgroundColor3 = Theme.Color.Surface,
			BackgroundTransparency = Theme.Transparency.Panel,
			ZIndex = 12,
		}, {
			Stroke = React.createElement("UIStroke", Theme.strokeProps()),
			Corner = React.createElement("UICorner", { CornerRadius = Theme.corner() }),
			CrownIcon = React.createElement("TextLabel", {
				Size = UDim2.fromOffset(28, 34),
				BackgroundTransparency = 1,
				Text = "👑",
				TextSize = Theme.TextSize.Heading,
				FontFace = Theme.FontFace.Body,
				ZIndex = 13,
			}),
			BarContainer = React.createElement("Frame", {
				Size = UDim2.new(1, -90, 0, 16),
				Position = UDim2.fromOffset(32, 9),
				BackgroundColor3 = Theme.Color.SurfaceRaised,
				BorderSizePixel = 0,
				ZIndex = 13,
			}, {
				Corner = React.createElement("UICorner", { CornerRadius = Theme.corner(Theme.Metrics.RadiusSmall) }),
				Fill = React.createElement("Frame", {
					Size = UDim2.fromScale(fraction, 1),
					BackgroundColor3 = barColor,
					BorderSizePixel = 0,
					ZIndex = 14,
				}, {
					Corner = React.createElement("UICorner", { CornerRadius = Theme.corner(Theme.Metrics.RadiusSmall) }),
				}),
			}),
			HealthText = React.createElement("TextLabel", {
				Size = UDim2.fromOffset(56, 34),
				Position = UDim2.new(1, -60, 0, 0),
				BackgroundTransparency = 1,
				Text = string.format("%d/%d", math.floor(health), math.floor(maxHealth)),
				TextSize = Theme.TextSize.Small,
				FontFace = Theme.FontFace.Number,
				TextColor3 = Theme.Color.TextPrimary,
				TextXAlignment = Enum.TextXAlignment.Right,
				ZIndex = 13,
			}),
		})
	end)()

	local keepCaptureBanner = keepCapture and (function()
		local capture = keepCapture :: any
		local isAttacker = capture.attacker
		local title = if isAttacker
			then string.format("⚔️ Seizing %s's Keep!", capture.keepOwnerName or "the enemy")
			else "🔥 YOUR KEEP IS BEING CAPTURED!"
		local accent = if isAttacker then Theme.Color.Accent else Theme.Color.Danger
		return React.createElement("Frame", {
			Name = "KeepCaptureBanner",
			Size = UDim2.fromOffset(440, 70),
			Position = UDim2.new(0.5, 0, 0, Theme.Metrics.ActionBarHeight + 60),
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundColor3 = Theme.Color.Surface,
			BackgroundTransparency = Theme.Transparency.Panel,
			ZIndex = 30,
		}, {
			Stroke = React.createElement("UIStroke", { Color = accent, Thickness = 1.5, Transparency = 0.2 }),
			Corner = React.createElement("UICorner", { CornerRadius = Theme.corner() }),
			Title = React.createElement("TextLabel", {
				Size = UDim2.new(1, -100, 0, 26),
				Position = UDim2.fromOffset(Theme.Metrics.Pad, 6),
				BackgroundTransparency = 1,
				Text = title,
				FontFace = Theme.FontFace.BodyBold,
				TextSize = Theme.TextSize.Title,
				TextColor3 = accent,
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 31,
			}),
			Countdown = React.createElement("TextLabel", {
				Size = UDim2.fromOffset(88, 40),
				Position = UDim2.new(1, -96, 0, 4),
				BackgroundTransparency = 1,
				Text = string.format("%ds", capture.secondsRemaining or 0),
				FontFace = Theme.FontFace.Number,
				TextSize = 28,
				TextColor3 = Theme.Color.TextPrimary,
				TextXAlignment = Enum.TextXAlignment.Right,
				ZIndex = 31,
			}),
			BarContainer = React.createElement("Frame", {
				Size = UDim2.new(1, -24, 0, 12),
				Position = UDim2.new(0, 12, 1, -20),
				BackgroundColor3 = Theme.Color.SurfaceRaised,
				BorderSizePixel = 0,
				ZIndex = 31,
			}, {
				Corner = React.createElement("UICorner", { CornerRadius = Theme.corner(Theme.Metrics.RadiusSmall) }),
				Fill = React.createElement("Frame", {
					Size = UDim2.fromScale(math.clamp(capture.fraction or 0, 0, 1), 1),
					BackgroundColor3 = accent,
					BorderSizePixel = 0,
					ZIndex = 32,
				}, {
					Corner = React.createElement("UICorner", { CornerRadius = Theme.corner(Theme.Metrics.RadiusSmall) }),
				}),
			}),
		})
	end)() or nil

	local estateCaptureBar = estateCapture and (function()
		local capture = estateCapture :: any
		local isAttacker = capture.attacker
		local label = if isAttacker then "🚩 Capturing estate..." else "🚩 Estate under attack!"
		local accent = if isAttacker then Theme.Color.Success else Theme.Color.Warning
		return React.createElement("Frame", {
			Name = "EstateCaptureBar",
			Size = UDim2.fromOffset(280, 48),
			Position = UDim2.new(0.5, 0, 0, Theme.Metrics.ActionBarHeight + 138),
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundColor3 = Theme.Color.Surface,
			BackgroundTransparency = Theme.Transparency.Panel,
			ZIndex = 30,
		}, {
			Stroke = React.createElement("UIStroke", Theme.strokeProps()),
			Corner = React.createElement("UICorner", { CornerRadius = Theme.corner() }),
			Label = React.createElement("TextLabel", {
				Size = UDim2.new(1, -70, 0, 20),
				Position = UDim2.fromOffset(10, 4),
				BackgroundTransparency = 1,
				Text = label,
				FontFace = Theme.FontFace.BodyBold,
				TextSize = Theme.TextSize.Heading,
				TextColor3 = accent,
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 31,
			}),
			Percent = React.createElement("TextLabel", {
				Size = UDim2.fromOffset(56, 20),
				Position = UDim2.new(1, -62, 0, 4),
				BackgroundTransparency = 1,
				Text = string.format("%d%%", math.floor((capture.fraction or 0) * 100)),
				FontFace = Theme.FontFace.Number,
				TextSize = Theme.TextSize.Heading,
				TextColor3 = Theme.Color.TextPrimary,
				TextXAlignment = Enum.TextXAlignment.Right,
				ZIndex = 31,
			}),
			BarContainer = React.createElement("Frame", {
				Size = UDim2.new(1, -20, 0, 10),
				Position = UDim2.new(0, 10, 1, -16),
				BackgroundColor3 = Theme.Color.SurfaceRaised,
				BorderSizePixel = 0,
				ZIndex = 31,
			}, {
				Corner = React.createElement("UICorner", { CornerRadius = Theme.corner(Theme.Metrics.RadiusSmall) }),
				Fill = React.createElement("Frame", {
					Size = UDim2.fromScale(math.clamp(capture.fraction or 0, 0, 1), 1),
					BackgroundColor3 = accent,
					BorderSizePixel = 0,
					ZIndex = 32,
				}, {
					Corner = React.createElement("UICorner", { CornerRadius = Theme.corner(Theme.Metrics.RadiusSmall) }),
				}),
			}),
		})
	end)() or nil

	-- Minimap + view-toggle dock, bottom-right, above the bottom bar. Nested
	-- deliberately: ViewToggleButton positions itself with a hardcoded
	-- AnchorPoint(1,0) + `UDim2.new(1, -14, 0, topOffset)`, which this file is
	-- not allowed to edit, so it is given its own narrow slot Frame here and
	-- reads as "beside the minimap" because that slot sits immediately to the
	-- minimap's left inside the same dock, rather than by changing the
	-- button's own anchoring.
	local minimapDock = React.createElement("Frame", {
		Name = "MinimapDock",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -Theme.Metrics.Pad, 1, -(BOTTOM_BAR_HEIGHT + Theme.Metrics.Pad)),
		Size = UDim2.fromOffset(TOGGLE_SLOT_WIDTH + Theme.Metrics.Gap + MINIMAP_SIZE, DOCK_HEIGHT),
		BackgroundTransparency = 1,
		ZIndex = 9,
	}, {
		ToggleSlot = React.createElement("Frame", {
			Size = UDim2.fromOffset(TOGGLE_SLOT_WIDTH, DOCK_HEIGHT),
			BackgroundTransparency = 1,
		}, {
			ViewToggle = React.createElement(ViewToggleButton, { topOffset = Theme.Metrics.Gap }),
		}),
		MiniMapFrame = React.createElement("Frame", {
			Name = "MiniMapFrame",
			Size = UDim2.fromOffset(MINIMAP_SIZE, MINIMAP_SIZE),
			Position = UDim2.new(0, TOGGLE_SLOT_WIDTH + Theme.Metrics.Gap, 0, (DOCK_HEIGHT - MINIMAP_SIZE) / 2),
			BackgroundColor3 = Theme.Color.Surface,
			BackgroundTransparency = Theme.Transparency.Panel,
			ClipsDescendants = true,
			ZIndex = 9,
		}, {
			Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
			Stroke = React.createElement("UIStroke", Theme.strokeProps(true)),
			MiniMap = React.createElement(MiniMap),
		}),
	})

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
			onBuildRequested = function(buildingType: string, isAutoTriggered: boolean?)
				HUDStore.requestTutorialBuild(buildingType, isAutoTriggered)
			end,
		})
	end)()

	return React.createElement("Frame", {
		Name = "DesktopShell",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, {
		TopBar = React.createElement(DesktopTopBar),

		LordHealthBar = lordHealthBar,
		KeepCaptureBanner = keepCaptureBanner,
		EstateCaptureBar = estateCaptureBar,

		FogOfWarIndicator = React.createElement(FogOverlay),
		MinimapDock = minimapDock,
		HeroTouchControls = React.createElement(HeroTouchControls),

		QuestTrackerPanel = not isArenaMode and React.createElement(QuestTracker, {
			quests = activeQuests,
		}) or nil,

		BattleLog = React.createElement(BattleLog, {
			messages = battleLogMessages,
			expanded = battleLogExpanded,
			onToggleExpanded = function()
				HUDStore.setState({ battleLogExpanded = not battleLogExpanded })
			end,
		}),

		BottomBar = React.createElement("Frame", {
			Name = "BottomBar",
			Size = UDim2.new(1, 0, 0, BOTTOM_BAR_HEIGHT),
			Position = UDim2.new(0, 0, 1, 0),
			AnchorPoint = Vector2.new(0, 1),
			BackgroundColor3 = Theme.Color.Surface,
			BackgroundTransparency = Theme.Transparency.Panel,
			BorderSizePixel = 0,
			ZIndex = 10,
			-- Battle Arena: bar appears only with units selected, so players get
			-- formations/stances/selection controls but no build/economy UI.
			Visible = not isArenaMode or hasUnitsSelected,
		}, {
			Stroke = React.createElement("UIStroke", Theme.strokeProps(true)),
			Content = React.createElement("Frame", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
			}, bottomBarChildren),
		}),

		PoliciesModal = showPoliciesModal and React.createElement(Policies, {
			visible = showPoliciesModal,
			happiness = happiness,
			onClose = function()
				HUDStore.togglePoliciesModal()
			end,
		}) or nil,

		AbilityTreeModal = showAbilityTree and React.createElement(AbilityTreePanel, {
			visible = showAbilityTree,
			tooltip = props.tooltip,
			onClose = function()
				HUDStore.toggleAbilityTree()
			end,
		}) or nil,

		MenuModal = showMenuModal and React.createElement(Menu, {
			visible = showMenuModal,
			onClose = function()
				HUDStore.setMenuModal(false)
			end,
			navigate = props.navigate,
		}) or nil,

		StatsModal = showStatsModal and React.createElement(Stats, {
			visible = showStatsModal,
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
			onClose = function()
				HUDStore.setTechTreeModal(false)
			end,
			onResearchStarted = function(techId: string)
				HUDStore.startResearch(techId)
			end,
		}) or nil,

		AchievementNotificationOverlay = achievementData and React.createElement(AchievementNotification, {
			achievementData = achievementData,
			onDismiss = function()
				HUDStore.dismissAchievement()
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

		UndoButton = not isArenaMode and React.createElement(UndoButton, {
			deletionHistory = deletionHistory,
			onUndo = function()
				HUDStore.undoLastDeletion()
			end,
		}) or nil,

		TutorialModal = tutorialModal,
	})
end

return DesktopShell
