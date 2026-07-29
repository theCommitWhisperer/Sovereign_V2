--!strict
-- DesktopShell: chrome for the mouse/keyboard layout. Positions panels; owns no
-- game state itself (HUDStore does). Per docs/EconomyRedesign.md section 8,
-- this is required to be VISUAL PARITY with HUD.luau's former desktop layout,
-- not a redesign -- every position/size below is copied from HUD.luau's
-- render() (top bar, bottom bar, minimap frame, category button positions,
-- content area, meter panel, modals) rather than re-derived.
--
-- HUD.luau has been deleted; this + MobileShell are now the only "hud" route.

local React = require(game.ReplicatedStorage.Packages.react)

local UIConfig = require(script.Parent.Parent.UIConfig)
local HUDStore = require(script.Parent.Parent.state.HUDStore)

local TopBar = require(script.Parent.Parent.screens.HUD.TopBar)
local MiniMap = require(script.Parent.Parent.screens.HUD.MiniMap)
local FogOverlay = require(script.Parent.Parent.screens.HUD.FogOverlay)
local BuildingMenu = require(script.Parent.Parent.screens.HUD.BuildingMenu)
local SelectionPanel = require(script.Parent.Parent.screens.HUD.SelectionPanel)
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

export type Props = {
	tooltip: any?,
	navigate: ((string) -> ())?,
}

-- Same six tabs and pixel positions as HUD.luau's createCategoryButton /
-- UIConfig.HUD.CategoryButtonPositions. Desktop tabs are image buttons (see
-- UIConfig.HUD.CategoryButtonImages) -- no text icons needed here, unlike
-- MobileShell's chips.
local CATEGORIES = { "Defense", "Military", "Industry", "Food", "Housing", "Prestige" }

-- Ported from HUD:createExpandedMeter -- one row of the expanded meter panel.
local function createExpandedMeter(label: string, icon: string, value: number, maxValue: number, layoutOrder: number)
	local percentage = math.clamp(value / maxValue, 0, 1)
	return React.createElement("Frame", {
		Size = UDim2.new(1, 0, 0, 28),
		BackgroundTransparency = 1,
		LayoutOrder = layoutOrder,
	}, {
		Icon = React.createElement("TextLabel", {
			Size = UDim2.fromOffset(28, 28),
			BackgroundTransparency = 1,
			Text = icon,
			Font = Enum.Font.GothamBold,
			TextSize = 18,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Center,
		}),
		BarContainer = React.createElement("Frame", {
			Size = UDim2.new(1, -65, 0, 20),
			Position = UDim2.fromOffset(32, 4),
			BackgroundColor3 = Color3.fromRGB(40, 40, 40),
			BorderSizePixel = 1,
			BorderColor3 = UIConfig.HUD.MeterBorder,
		}, {
			FillBar = React.createElement("Frame", {
				Size = UDim2.fromScale(percentage, 1),
				BackgroundColor3 = UIConfig.HUD.CategoryButtonSelected,
				BorderSizePixel = 0,
			}),
		}),
		ValueText = React.createElement("TextLabel", {
			Size = UDim2.fromOffset(30, 28),
			Position = UDim2.new(1, -30, 0, 0),
			BackgroundTransparency = 1,
			Text = tostring(value),
			Font = Enum.Font.GothamBold,
			TextSize = 12,
			TextColor3 = UIConfig.HUD.PanelTextColor,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextYAlignment = Enum.TextYAlignment.Center,
		}),
	})
end

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

	local showExpandedMeters, setShowExpandedMeters = React.useState(false)

	local hasUnitsSelected = #selectedUnits > 0
	local hasTrainingBuildingSelected = selectedTrainingBuilding ~= nil
	local hasProductionBuildingSelected = selectedProductionBuilding ~= nil

	-- Battle Arena mode: no economy -- hide resource bars, build menus, meters,
	-- quests, and undo. BattleLog and notifications stay (combat-relevant).
	local isArenaMode = gameStartData ~= nil and gameStartData.mode == "BattleArena"

	local categoryButtons = {}
	for _, category in CATEGORIES do
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
				HUDStore.selectCategory(category)
			end,
		})
	end

	-- Content priority, identical order to HUD.luau's render():
	-- Training > Production > Hero Abilities > Upgrade > Unit Selection > Building Menu
	local contentAreaChild
	if hasTrainingBuildingSelected then
		contentAreaChild = React.createElement(TrainingPanel, {
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
		contentAreaChild = React.createElement(WorkerAssignmentPanel, {
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
		contentAreaChild = React.createElement(HeroAbilitiesPanel, {
			abilities = heroAbilities,
			tooltip = props.tooltip,
			onAbilityUsed = function(abilityId: string)
				HUDStore.useAbility(abilityId)
			end,
		})
	elseif buildingUpgradeInfo then
		contentAreaChild = React.createElement(UpgradePanel, {
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
		contentAreaChild = React.createElement(UnitSelectionPanel, {
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
		contentAreaChild = React.createElement(BuildingMenu, {
			tooltip = props.tooltip,
			resources = resources,
			gloryLifetime = gloryLifetime,
			selectedCategory = selectedCategory,
			currentWallPiece = currentWallPiece,
			isPlacingWall = isPlacingWall,
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

		UtilityButtons = React.createElement("Frame", {
			Size = UDim2.new(0, UIConfig.HUD.UtilityButtonWidth, 0, UIConfig.HUD.BottomBarHeight),
			Position = UDim2.new(0, 68, 0.26, 0),
			BackgroundTransparency = 1,
			ZIndex = 11,
		}, {
			Padding = React.createElement("UIPadding", {
				PaddingTop = UDim.new(0, 0),
				PaddingBottom = UDim.new(0, 10),
			}),
			Layout = React.createElement("UIListLayout", {
				FillDirection = Enum.FillDirection.Vertical,
				Padding = UDim.new(0, 35),
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Top,
			}),

			DeleteButton = React.createElement(IconButton, {
				Name = "DeleteButton",
				Size = UDim2.new(1, 0, 0, UIConfig.HUD.UtilityButtonHeight),
				Icon = "🗑️",
				IconSize = 15,
				IconColor = UIConfig.HUD.PanelTextColor,
				ImageColor3 = isDeleteMode and UIConfig.HUD.CategoryButtonSelected or UIConfig.HUD.UtilityButtonBackground,
				OnClick = function()
					HUDStore.toggleDeleteMode()
				end,
			}),

			PoliciesButton = React.createElement(IconButton, {
				Name = "PoliciesButton",
				Size = UDim2.new(1, 0, 0, UIConfig.HUD.UtilityButtonHeight),
				Icon = "📜",
				IconSize = 20,
				IconColor = UIConfig.HUD.PanelTextColor,
				ImageColor3 = UIConfig.HUD.UtilityButtonBackground,
				OnClick = function()
					HUDStore.togglePoliciesModal()
				end,
			}),

			AbilityTreeButton = React.createElement(IconButton, {
				Name = "AbilityTreeButton",
				Size = UDim2.new(1, 0, 0, UIConfig.HUD.UtilityButtonHeight),
				Icon = "⚜️",
				IconSize = 20,
				IconColor = UIConfig.HUD.PanelTextColor,
				ImageColor3 = showAbilityTree and UIConfig.HUD.CategoryButtonSelected
					or UIConfig.HUD.UtilityButtonBackground,
				LayoutOrder = 3,
				OnClick = function()
					HUDStore.toggleAbilityTree()
				end,
			}),
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

		FogOfWarIndicator = React.createElement(FogOverlay),

		-- RTS <-> Hero view switch, and hero touch combat cluster. Mounted
		-- unconditionally, same as HUD.luau: ViewToggleButton is the only way to
		-- reach hero view without a keyboard, and HeroTouchControls renders nil on
		-- its own unless the device is touch-capable AND in hero view.
		ViewToggle = React.createElement(require(script.Parent.Parent.screens.HUD.ViewToggleButton)),
		HeroTouchControls = React.createElement(require(script.Parent.Parent.screens.HUD.HeroTouchControls)),

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

	-- ===== LORD HEALTH BAR ===== (persistent; fed by "KingHealthUpdate")
	local lordHealthBar = (function()
		local health = kingHealth or 0
		local maxHealth = math.max(kingMaxHealth or 1, 1)
		local fraction = math.clamp(health / maxHealth, 0, 1)
		local barColor = if fraction > 0.5
			then Color3.fromRGB(90, 170, 80)
			elseif fraction > 0.25 then Color3.fromRGB(210, 160, 60)
			else Color3.fromRGB(190, 60, 50)
		return React.createElement("Frame", {
			Name = "LordHealthBar",
			Size = UDim2.fromOffset(210, 34),
			Position = UDim2.fromOffset(12, 12),
			BackgroundColor3 = UIConfig.HUD.MeterBackground,
			BackgroundTransparency = 0.2,
			BorderSizePixel = 2,
			BorderColor3 = UIConfig.HUD.MeterBorder,
			ZIndex = 12,
		}, {
			CrownIcon = React.createElement("TextLabel", {
				Size = UDim2.fromOffset(28, 34),
				BackgroundTransparency = 1,
				Text = "👑",
				TextSize = 18,
				Font = Enum.Font.GothamBold,
				ZIndex = 13,
			}),
			BarContainer = React.createElement("Frame", {
				Size = UDim2.new(1, -90, 0, 16),
				Position = UDim2.fromOffset(32, 9),
				BackgroundColor3 = Color3.fromRGB(40, 40, 40),
				BorderSizePixel = 1,
				BorderColor3 = UIConfig.HUD.MeterBorder,
				ZIndex = 13,
			}, {
				Fill = React.createElement("Frame", {
					Size = UDim2.fromScale(fraction, 1),
					BackgroundColor3 = barColor,
					BorderSizePixel = 0,
					ZIndex = 14,
				}),
			}),
			HealthText = React.createElement("TextLabel", {
				Size = UDim2.fromOffset(52, 34),
				Position = UDim2.new(1, -56, 0, 0),
				BackgroundTransparency = 1,
				Text = string.format("%d/%d", math.floor(health), math.floor(maxHealth)),
				TextSize = 12,
				Font = Enum.Font.GothamBold,
				TextColor3 = UIConfig.HUD.PanelTextColor,
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
		local accent = if isAttacker then Color3.fromRGB(214, 178, 94) else Color3.fromRGB(190, 60, 50)
		return React.createElement("Frame", {
			Name = "KeepCaptureBanner",
			Size = UDim2.fromOffset(440, 70),
			Position = UDim2.new(0.5, 0, 0, 108),
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundColor3 = Color3.fromRGB(30, 20, 18),
			BackgroundTransparency = 0.15,
			BorderSizePixel = 2,
			BorderColor3 = accent,
			ZIndex = 30,
		}, {
			Title = React.createElement("TextLabel", {
				Size = UDim2.new(1, -100, 0, 26),
				Position = UDim2.fromOffset(12, 6),
				BackgroundTransparency = 1,
				Text = title,
				Font = Enum.Font.GothamBold,
				TextSize = 18,
				TextColor3 = accent,
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 31,
			}),
			Countdown = React.createElement("TextLabel", {
				Size = UDim2.fromOffset(88, 40),
				Position = UDim2.new(1, -96, 0, 4),
				BackgroundTransparency = 1,
				Text = string.format("%ds", capture.secondsRemaining or 0),
				Font = Enum.Font.GothamBold,
				TextSize = 30,
				TextColor3 = Color3.fromRGB(255, 255, 255),
				TextXAlignment = Enum.TextXAlignment.Right,
				ZIndex = 31,
			}),
			BarContainer = React.createElement("Frame", {
				Size = UDim2.new(1, -24, 0, 12),
				Position = UDim2.new(0, 12, 1, -20),
				BackgroundColor3 = Color3.fromRGB(40, 40, 40),
				BorderSizePixel = 1,
				BorderColor3 = UIConfig.HUD.MeterBorder,
				ZIndex = 31,
			}, {
				Fill = React.createElement("Frame", {
					Size = UDim2.fromScale(math.clamp(capture.fraction or 0, 0, 1), 1),
					BackgroundColor3 = accent,
					BorderSizePixel = 0,
					ZIndex = 32,
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
			Size = UDim2.fromOffset(280, 48),
			Position = UDim2.new(0.5, 0, 0, 186),
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundColor3 = Color3.fromRGB(30, 25, 20),
			BackgroundTransparency = 0.25,
			BorderSizePixel = 2,
			BorderColor3 = UIConfig.HUD.MeterBorder,
			ZIndex = 30,
		}, {
			Label = React.createElement("TextLabel", {
				Size = UDim2.new(1, -70, 0, 20),
				Position = UDim2.fromOffset(10, 4),
				BackgroundTransparency = 1,
				Text = label,
				Font = Enum.Font.GothamBold,
				TextSize = 15,
				TextColor3 = accent,
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 31,
			}),
			Percent = React.createElement("TextLabel", {
				Size = UDim2.fromOffset(56, 20),
				Position = UDim2.new(1, -62, 0, 4),
				BackgroundTransparency = 1,
				Text = string.format("%d%%", math.floor((capture.fraction or 0) * 100)),
				Font = Enum.Font.GothamBold,
				TextSize = 15,
				TextColor3 = Color3.fromRGB(255, 255, 255),
				TextXAlignment = Enum.TextXAlignment.Right,
				ZIndex = 31,
			}),
			BarContainer = React.createElement("Frame", {
				Size = UDim2.new(1, -20, 0, 10),
				Position = UDim2.new(0, 10, 1, -16),
				BackgroundColor3 = Color3.fromRGB(40, 40, 40),
				BorderSizePixel = 1,
				BorderColor3 = UIConfig.HUD.MeterBorder,
				ZIndex = 31,
			}, {
				Fill = React.createElement("Frame", {
					Size = UDim2.fromScale(math.clamp(capture.fraction or 0, 0, 1), 1),
					BackgroundColor3 = accent,
					BorderSizePixel = 0,
					ZIndex = 32,
				}),
			}),
		})
	end)() or nil

	local meterPanel = React.createElement("Frame", {
		Name = "MeterPanel",
		Size = UDim2.new(0, 280, 0, showExpandedMeters and 280 or 50),
		Position = UDim2.new(1, -1300, 1, -UIConfig.HUD.BottomBarHeight - (showExpandedMeters and 280 or 60)),
		BackgroundTransparency = 1,
		ZIndex = 10,
		Visible = not isArenaMode,
	}, {
		ExpandButton = React.createElement(IconButton, {
			Size = UDim2.new(0, 80, 0, 20),
			Position = UDim2.new(0.5, -40, 0, 0),
			Icon = showExpandedMeters and "▼" or "▲",
			IconSize = 14,
			IconColor = UIConfig.HUD.PanelTextColor,
			ImageColor3 = UIConfig.HUD.UtilityButtonBackground,
			OnClick = function()
				setShowExpandedMeters(not showExpandedMeters)
			end,
		}),

		MeterBackground = React.createElement("Frame", {
			Size = UDim2.new(1, 0, 1, -10),
			Position = UDim2.fromOffset(0, 20),
			BackgroundColor3 = UIConfig.HUD.MeterBackground,
			BorderSizePixel = 2,
			BorderColor3 = UIConfig.HUD.MeterBorder,
		}, {
			HappinessMeter = React.createElement("Frame", {
				Size = UDim2.new(1, -20, 0, 30),
				Position = UDim2.fromOffset(10, 5),
				BackgroundTransparency = 1,
			}, {
				HappyEmoji = React.createElement("TextLabel", {
					Size = UDim2.new(0, 35, 0, 35),
					BackgroundTransparency = 1,
					Text = "😊",
					Font = Enum.Font.GothamBold,
					TextSize = 24,
					TextXAlignment = Enum.TextXAlignment.Center,
					TextYAlignment = Enum.TextYAlignment.Center,
				}),
				BarContainer = React.createElement("Frame", {
					Size = UDim2.new(1, -80, 1, -6),
					Position = UDim2.fromOffset(40, 3),
					BackgroundColor3 = Color3.fromRGB(40, 40, 40),
					BorderSizePixel = 1,
					BorderColor3 = UIConfig.HUD.MeterBorder,
				}, {
					HappyBar = React.createElement("Frame", {
						Size = UDim2.new(happiness / 100, 0, 1, 0),
						BackgroundColor3 = UIConfig.HUD.MeterHappyColor,
						BorderSizePixel = 0,
					}),
					RevoltBar = React.createElement("Frame", {
						Size = UDim2.new(math.max(0, (50 - happiness) / 100), 0, 1, 0),
						Position = UDim2.new(1, 0, 0, 0),
						AnchorPoint = Vector2.new(1, 0),
						BackgroundColor3 = UIConfig.HUD.MeterRevoltColor,
						BorderSizePixel = 0,
					}),
				}),
				MadEmoji = React.createElement("TextLabel", {
					Size = UDim2.new(0, 35, 0, 35),
					Position = UDim2.new(1, -35, 0, 0),
					BackgroundTransparency = 1,
					Text = "😡",
					Font = Enum.Font.GothamBold,
					TextSize = 24,
					TextXAlignment = Enum.TextXAlignment.Center,
					TextYAlignment = Enum.TextYAlignment.Center,
				}),
			}),
		}),

		ExpandedMeters = showExpandedMeters and React.createElement("Frame", {
			Size = UDim2.new(1, 0, 1, -65),
			Position = UDim2.fromOffset(0, 65),
			BackgroundColor3 = UIConfig.HUD.MeterBackground,
			BorderSizePixel = 2,
			BorderColor3 = UIConfig.HUD.MeterBorder,
		}, {
			ContentFrame = React.createElement("Frame", {
				Size = UDim2.new(1, -20, 1, -10),
				Position = UDim2.fromOffset(10, 5),
				BackgroundTransparency = 1,
			}, {
				Layout = React.createElement("UIListLayout", {
					FillDirection = Enum.FillDirection.Vertical,
					Padding = UDim.new(0, 6),
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
				FoodMeter = createExpandedMeter("Food", "🌾", resources.Food or 0, 500, 1),
				GoldMeter = createExpandedMeter("Gold", "💰", resources.Gold or 0, 1000, 2),
				PopulationMeter = economySnapshot
						and createExpandedMeter(
							"Population",
							"👥",
							economySnapshot.population or 0,
							economySnapshot.housingCapacity or 10,
							3
						)
					or createExpandedMeter("Population", "👥", population, 100, 3),
				EconomyHealthMeter = economySnapshot
						and createExpandedMeter("Economy", "🏰", economySnapshot.economyHealth or 50, 100, 4)
					or nil,
				FoodConsumptionMeter = economySnapshot
						and createExpandedMeter(
							"Consumption",
							"🍴",
							math.min(economySnapshot.foodConsumptionRate or 0, 10),
							10,
							5
						)
					or nil,
				TaxRateMeter = economySnapshot
						and createExpandedMeter("Tax Rate", "💸", economySnapshot.taxRate or 0, 100, 6)
					or nil,
			}),
		}) or nil,
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
		TopBar = not isArenaMode and React.createElement(TopBar, {
			resources = resources,
			honor = honor,
			glory = glory,
			population = population,
			date = date,
			weather = weather,
			peaceTimeRemaining = peaceTimeRemaining,
			victoryCondition = victoryCondition,
		}) or nil,

		LordHealthBar = lordHealthBar,
		KeepCaptureBanner = keepCaptureBanner,
		EstateCaptureBar = estateCaptureBar,

		BottomBar = React.createElement("Frame", {
			Name = "BottomBar",
			Size = UDim2.new(0, 1400, 0, UIConfig.HUD.BottomBarHeight),
			Position = UDim2.new(0, 0, 1, 0),
			AnchorPoint = Vector2.new(0, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 10,
			-- Battle Arena: bar appears only with units selected, so players get
			-- formations/stances/selection controls but no build/economy UI.
			Visible = not isArenaMode or hasUnitsSelected,
		}, bottomBarChildren),

		MeterPanel = meterPanel,

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

		QuestTrackerPanel = not isArenaMode and React.createElement(QuestTracker, {
			quests = activeQuests,
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

		BattleLog = React.createElement(BattleLog, {
			messages = battleLogMessages,
			expanded = battleLogExpanded,
			onToggleExpanded = function()
				HUDStore.setState({ battleLogExpanded = not battleLogExpanded })
			end,
		}),

		TutorialModal = tutorialModal,
	})
end

return DesktopShell
