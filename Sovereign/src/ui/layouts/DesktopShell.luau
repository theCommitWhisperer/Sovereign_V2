--!strict
-- DesktopShell: desktop HUD shell ("direction A" modern dark Peat/Gold).
-- Features floating centered command island dock (880x230px), attached mode switcher tab dock (🔨 Build Mode | ⚔ Fight Mode),
-- sleek rectangular building pill cards (140x56px), compact icon-only stance buttons (36x36px), independent bottom-left minimap wing,
-- vertical gold divider line separating CategoryColumn from MainContent, strict ClipsDescendants preventing overflow into RightColumn.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local React = require(ReplicatedStorage.Packages.react)

local Theme = require(script.Parent.Parent.Theme)
local HUDStore = require(script.Parent.Parent.state.HUDStore)
local ViewMode = require(ReplicatedStorage.Shared.ViewMode)

-- Components
local MiniMap = require(script.Parent.Parent.screens.HUD.MiniMap)
local UndoButton = require(script.Parent.Parent.screens.HUD.UndoButton)
local BattleTicker = require(script.Parent.Parent.components.BattleTicker)
local DesktopTopBar = require(script.Parent.Parent.panels.DesktopTopBar)
local CategoryColumn = require(script.Parent.Parent.panels.CategoryColumn)
local DesktopBuildingGrid = require(script.Parent.Parent.panels.DesktopBuildingGrid)
local HeroFightHUD = require(script.Parent.Parent.panels.HeroFightHUD)
local TutorialModal = require(script.Parent.Parent.components.TutorialModal)
local MedievalCorners = require(script.Parent.Parent.components.MedievalCorners)

-- Modals
local Menu = require(script.Parent.Parent.screens.Menu.Menu)
local Stats = require(script.Parent.Parent.screens.Stats.Stats)
local Policies = require(script.Parent.Parent.screens.Policies.Policies)
local TechTreePanel = require(script.Parent.Parent.screens.HUD.TechTree)
local AbilityTreePanel = require(script.Parent.Parent.screens.HUD.AbilityTreePanel)

-- Panels
local UnitPanel = require(script.Parent.Parent.panels.UnitPanel)

export type Props = {
	tooltip: any?,
	onBuildingSelected: ((string?) -> ())?,
}

local BOTTOM_BAR_WIDTH = 880
local BOTTOM_BAR_HEIGHT = 230
local MINIMAP_DOCK_SIZE = 284
local MINIMAP_SIZE = 280
local RIGHT_COL_WIDTH = 100
local STATUS_MODAL_HEIGHT = 84
local DARK_TEXT = Color3.fromRGB(20, 14, 6)

local function DesktopShell(props: Props)
	local isInfoDrawerOpen, setIsInfoDrawerOpen = React.useState(false)

	-- Subscribe to ViewMode state (RTS vs Hero view)
	local currentViewMode, setCurrentViewMode = React.useState(function()
		return ViewMode.get()
	end)

	React.useEffect(function()
		local disconnect = ViewMode.Changed:connect(function(newMode)
			setCurrentViewMode(newMode)
		end)
		return function()
			disconnect()
		end
	end, {})

	local isArenaMode = currentViewMode == "Hero"

	-- Subscribe to HUDStore state
	local selectedUnits = HUDStore.useHUDState(function(s)
		return s.selectedUnits
	end)
	local selectedBuilding = HUDStore.useHUDState(function(s)
		return s.selectedBuilding
	end)
	local isPlacingBuilding = HUDStore.useHUDState(function(s)
		return s.isPlacingBuilding
	end)
	local selectedStance = HUDStore.useHUDState(function(s)
		return s.selectedStance
	end)
	local selectedFormation = HUDStore.useHUDState(function(s)
		return s.selectedFormation
	end)
	local showMenuModal = HUDStore.useHUDState(function(s)
		return s.showMenuModal
	end)
	local showStatsModal = HUDStore.useHUDState(function(s)
		return s.showStatsModal
	end)
	local showPoliciesModal = HUDStore.useHUDState(function(s)
		return s.showPoliciesModal
	end)
	local showTechTreeModal = HUDStore.useHUDState(function(s)
		return s.showTechTreeModal
	end)
	local showAbilityTree = HUDStore.useHUDState(function(s)
		return s.showAbilityTree
	end)
	local battleLogMessages = HUDStore.useHUDState(function(s)
		return s.battleLogMessages
	end)
	local deletionHistory = HUDStore.useHUDState(function(s)
		return s.deletionHistory
	end)
	local isDeleteMode = HUDStore.useHUDState(function(s)
		return s.isDeleteMode
	end)
	local kingHealth = HUDStore.useHUDState(function(s)
		return s.kingHealth
	end)
	local kingMaxHealth = HUDStore.useHUDState(function(s)
		return s.kingMaxHealth
	end)
	local happiness = HUDStore.useHUDState(function(s)
		return s.happiness
	end)

	-- Tutorial & Keep placement state
	local tutorialStep = HUDStore.useHUDState(function(s)
		return s.tutorialStep
	end)
	local showKeepModal = HUDStore.useHUDState(function(s)
		return s.showKeepModal
	end)
	local tutorialEnabled = HUDStore.useHUDState(function(s)
		return s.tutorialEnabled
	end)
	local tutorialModalHidden = HUDStore.useHUDState(function(s)
		return s.tutorialModalHidden
	end)

	local hasUnitsSelected = #selectedUnits > 0
	local hasUndoHistory = deletionHistory ~= nil and #deletionHistory > 0

	-- Dynamic keybinding lookup for mode toggling (V key / ToggleCameraMode)
	React.useEffect(function()
		local toggleKeyCode = Enum.KeyCode.V
		pcall(function()
			local player = Players.LocalPlayer
			if player then
				local cameraFolder = player.PlayerScripts:FindFirstChild("Camera")
				if cameraFolder and cameraFolder:FindFirstChild("KeybindingsManager") then
					local KBM = require(cameraFolder:FindFirstChild("KeybindingsManager") :: any)
					if KBM and KBM.GetKeybinding then
						toggleKeyCode = KBM.GetKeybinding("ToggleCameraMode") or Enum.KeyCode.V
					end
				end
			end
		end)

		local connection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
			if gameProcessed then
				return
			end
			if input.KeyCode == toggleKeyCode then
				-- Toggle directly between Build (RTS) and Fight (Hero) Mode
				ViewMode.requestToggle()
			elseif input.KeyCode == Enum.KeyCode.M then
				HUDStore.setMenuModal(not showMenuModal)
			elseif input.KeyCode == Enum.KeyCode.N then
				HUDStore.setStatsModal(not showStatsModal)
			elseif input.KeyCode == Enum.KeyCode.P then
				HUDStore.togglePoliciesModal()
			elseif input.KeyCode == Enum.KeyCode.T then
				HUDStore.setTechTreeModal(not showTechTreeModal)
			elseif input.KeyCode == Enum.KeyCode.X then
				HUDStore.toggleDeleteMode()
			elseif input.KeyCode == Enum.KeyCode.Z and UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
				HUDStore.undoLastDeletion()
			end
		end)
		return function()
			connection:Disconnect()
		end
	end, { showMenuModal, showStatsModal, showPoliciesModal, showTechTreeModal, isDeleteMode, isArenaMode })

	-- Keep placement & Tutorial modal logic
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

	-- Contextual bottom panel (units or active building placement)
	local contextualPanel: any = nil
	if hasUnitsSelected then
		contextualPanel = React.createElement(UnitPanel, {
			selectedUnits = selectedUnits,
			selectedStance = selectedStance,
			selectedFormation = selectedFormation,
			onStanceSelected = function(stance)
				HUDStore.selectStance(stance)
			end,
			onFormationSelected = function(formation)
				HUDStore.selectFormation(formation)
			end,
			onCivilianOrder = function(order)
				local player = Players.LocalPlayer
				if not player then
					return
				end
				local remotes = ReplicatedStorage:FindFirstChild("Remotes")
				local orderRemote = remotes and remotes:FindFirstChild("CivilianOrder")
				if orderRemote then
					orderRemote:FireServer(order)
				end
			end,
			compact = false,
		})
	elseif isPlacingBuilding and selectedBuilding then
		contextualPanel = React.createElement("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Theme.Color.Surface,
			BackgroundTransparency = Theme.Transparency.Panel,
			ClipsDescendants = true,
		}, {
			Corner = React.createElement("UICorner", { CornerRadius = Theme.corner() }),
			Stroke = React.createElement("UIStroke", Theme.celticStrokeProps()),
			Title = React.createElement("TextLabel", {
				Size = UDim2.new(1, -20, 0, 30),
				Position = UDim2.fromOffset(10, 10),
				BackgroundTransparency = 1,
				Text = string.format("Placing Building: %s", tostring(selectedBuilding)),
				FontFace = Theme.FontFace.Display,
				TextSize = Theme.TextSize.Title,
				TextColor3 = Theme.Color.Accent,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
			}),
		})
	end

	local hasContextDock = contextualPanel ~= nil

	-- ===== STATUS BAR 1: LORD HEALTH BAR =====
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
			Size = UDim2.new(1, 0, 0, 28),
			BackgroundColor3 = Theme.Color.Surface,
			BackgroundTransparency = Theme.Transparency.Panel,
			LayoutOrder = 1,
		}, {
			Stroke = React.createElement("UIStroke", Theme.celticStrokeProps()),
			Corner = React.createElement("UICorner", { CornerRadius = Theme.corner(Theme.Metrics.RadiusSmall) }),
			CrownIcon = React.createElement("TextLabel", {
				Size = UDim2.fromOffset(24, 28),
				Position = UDim2.fromOffset(6, 0),
				BackgroundTransparency = 1,
				Text = "👑",
				TextSize = 16,
				FontFace = Theme.FontFace.Body,
				ZIndex = 11,
			}),
			BarContainer = React.createElement("Frame", {
				Size = UDim2.new(1, -104, 0, 14),
				Position = UDim2.fromOffset(38, 7),
				BackgroundColor3 = Theme.Color.SurfaceRaised,
				BorderSizePixel = 0,
				ZIndex = 11,
			}, {
				Corner = React.createElement("UICorner", { CornerRadius = Theme.corner(Theme.Metrics.RadiusSmall) }),
				Fill = React.createElement("Frame", {
					Size = UDim2.fromScale(fraction, 1),
					BackgroundColor3 = barColor,
					BorderSizePixel = 0,
					ZIndex = 12,
				}, {
					Corner = React.createElement("UICorner", { CornerRadius = Theme.corner(Theme.Metrics.RadiusSmall) }),
				}),
			}),
			HealthText = React.createElement("TextLabel", {
				Size = UDim2.fromOffset(54, 28),
				Position = UDim2.new(1, -62, 0, 0),
				BackgroundTransparency = 1,
				Text = string.format("%d/%d", math.floor(health), math.floor(maxHealth)),
				TextSize = 12,
				FontFace = Theme.FontFace.Number,
				TextColor3 = Theme.Color.TextPrimary,
				TextXAlignment = Enum.TextXAlignment.Right,
				TextStrokeTransparency = 1,
				ZIndex = 13,
			}),
		})
	end)()

	-- ===== STATUS BAR 2: REALM MORALE BAR =====
	local moraleBar = (function()
		local moraleVal = math.clamp(happiness or 100, 0, 100)
		local fraction = moraleVal / 100
		return React.createElement("Frame", {
			Name = "MoraleBar",
			Size = UDim2.new(1, 0, 0, 28),
			BackgroundColor3 = Theme.Color.Surface,
			BackgroundTransparency = Theme.Transparency.Panel,
			LayoutOrder = 2,
		}, {
			Stroke = React.createElement("UIStroke", Theme.celticStrokeProps()),
			Corner = React.createElement("UICorner", { CornerRadius = Theme.corner(Theme.Metrics.RadiusSmall) }),
			Icon = React.createElement("TextLabel", {
				Size = UDim2.fromOffset(24, 28),
				Position = UDim2.fromOffset(6, 0),
				BackgroundTransparency = 1,
				Text = "👥",
				TextSize = 16,
				FontFace = Theme.FontFace.Body,
				ZIndex = 11,
			}),
			BarContainer = React.createElement("Frame", {
				Size = UDim2.new(1, -104, 0, 14),
				Position = UDim2.fromOffset(38, 7),
				BackgroundColor3 = Theme.Color.SurfaceRaised,
				BorderSizePixel = 0,
				ZIndex = 11,
			}, {
				Corner = React.createElement("UICorner", { CornerRadius = Theme.corner(Theme.Metrics.RadiusSmall) }),
				Fill = React.createElement("Frame", {
					Size = UDim2.fromScale(fraction, 1),
					BackgroundColor3 = Theme.Color.Accent,
					BorderSizePixel = 0,
					ZIndex = 12,
				}, {
					Corner = React.createElement("UICorner", { CornerRadius = Theme.corner(Theme.Metrics.RadiusSmall) }),
				}),
			}),
			StatusText = React.createElement("TextLabel", {
				Size = UDim2.fromOffset(54, 28),
				Position = UDim2.new(1, -62, 0, 0),
				BackgroundTransparency = 1,
				Text = string.format("%d%%", math.floor(moraleVal)),
				TextSize = 12,
				FontFace = Theme.FontFace.Number,
				TextColor3 = Theme.Color.Accent,
				TextXAlignment = Enum.TextXAlignment.Right,
				TextStrokeTransparency = 1,
				ZIndex = 13,
			}),
		})
	end)()

	local arrowYOffset = if isInfoDrawerOpen then -(STATUS_MODAL_HEIGHT + 4) else 0

	-- Square Action Card Helper with Outer Gold Border Stroke (ApplyStrokeMode.Border) & ClipsDescendants
	local function squareActionButton(key: string, icon: string, label: string, active: boolean, onClick: () -> (), order: number)
		return React.createElement("TextButton", {
			Name = key,
			Size = UDim2.fromOffset(40, 40),
			BackgroundColor3 = if active then Theme.Color.Accent else Theme.Color.SurfaceRaised,
			BackgroundTransparency = if active then 0 else Theme.Transparency.Card,
			AutoButtonColor = true,
			Text = "",
			ClipsDescendants = true,
			LayoutOrder = order,
			[React.Event.Activated] = onClick,
		}, {
			Corner = React.createElement("UICorner", { CornerRadius = Theme.corner(Theme.Metrics.RadiusSmall) }),
			Stroke = React.createElement("UIStroke", {
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Color = Theme.Color.Accent,
				Transparency = if active then 0 else 0.25,
				Thickness = if active then 2.5 else 1.8,
			}),
			IconLabel = React.createElement("TextLabel", {
				Size = UDim2.new(1, 0, 0, 20),
				Position = UDim2.new(0, 0, 0, 2),
				BackgroundTransparency = 1,
				Text = icon,
				FontFace = Theme.FontFace.Display,
				TextSize = 16,
				TextColor3 = if active then Theme.Color.OnAccent else Theme.Color.TextPrimary,
			}),
			NameLabel = React.createElement("TextLabel", {
				Size = UDim2.new(1, -2, 0, 14),
				Position = UDim2.new(0, 1, 0, 22),
				BackgroundTransparency = 1,
				Text = label,
				FontFace = Theme.FontFace.BodyBold,
				TextSize = 9,
				TextColor3 = if active then Theme.Color.OnAccent else Theme.Color.TextSecondary,
				TextXAlignment = Enum.TextXAlignment.Center,
				TextTruncate = Enum.TextTruncate.AtEnd,
			}),
		})
	end

	return React.createElement("Frame", {
		Name = "DesktopShell",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, {
		TopBar = React.createElement(DesktopTopBar, { tooltip = props.tooltip }),

		-- ===== SCROLLING BATTLE TICKER (VERY TOP RIGHT OF SCREEN FOR ALL SCREENS) =====
		BattleTicker = React.createElement(BattleTicker, { messages = battleLogMessages }),

		-- ===== CENTER-BOTTOM FIGHT MODE HUD (HERO FIGHT VIEW) =====
		HeroFightHUD = isArenaMode and React.createElement(HeroFightHUD) or nil,

		-- ===== SCREEN-CENTERED ATTACHED MODE SWITCHER TAB DOCK =====
		AttachedModeTabDock = React.createElement("Frame", {
			Name = "AttachedModeTabDock",
			Size = UDim2.fromOffset(260, 28),
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, if not isArenaMode then -(BOTTOM_BAR_HEIGHT + 11) else -63),
			BackgroundColor3 = Theme.Color.Surface,
			BackgroundTransparency = 0.05,
			ZIndex = 45,
		}, {
			Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 6) }),
			Stroke = React.createElement("UIStroke", Theme.celticStrokeProps()),

			-- 🔨 BUILD MODE BUTTON
			BuildBtn = React.createElement("TextButton", {
				Name = "BuildBtn",
				Size = UDim2.new(0.5, -16, 1, -4),
				Position = UDim2.fromOffset(2, 2),
				BackgroundColor3 = if not isArenaMode then Theme.Color.Accent else Theme.Color.SurfaceRaised,
				BackgroundTransparency = if not isArenaMode then 0 else 0.5,
				AutoButtonColor = true,
				Text = "🔨 Build Mode",
				FontFace = Theme.FontFace.BodyBold,
				TextSize = 11,
				TextColor3 = if not isArenaMode then DARK_TEXT else Theme.Color.TextSecondary,
				TextTruncate = Enum.TextTruncate.AtEnd,
				ClipsDescendants = true,
				[React.Event.Activated] = function()
					if isArenaMode then
						ViewMode.requestToggle()
					end
				end,
			}, {
				Corner = React.createElement("UICorner", { CornerRadius = Theme.corner(Theme.Metrics.RadiusSmall) }),
				Stroke = React.createElement("UIStroke", {
					ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
					Color = Theme.Color.Accent,
					Transparency = if not isArenaMode then 0 else 0.35,
					Thickness = 1.8,
				}),
			}),

			-- CENTRAL GOLD HOTKEY SEAL [V] BRIDGING THE TWO MODES
			HotkeySeal = React.createElement("Frame", {
				Name = "HotkeySeal",
				Size = UDim2.fromOffset(26, 20),
				Position = UDim2.new(0.5, 0, 0.5, 3),
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = Theme.Color.SurfaceRaised,
				ZIndex = 46,
			}, {
				Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 4) }),
				Stroke = React.createElement("UIStroke", {
					ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
					Color = Theme.Color.Accent,
					Thickness = 1.5,
				}),
				KeyText = React.createElement("TextLabel", {
					Size = UDim2.fromScale(1, 1),
					BackgroundTransparency = 1,
					Text = "V",
					FontFace = Theme.FontFace.Display,
					TextSize = 11,
					TextColor3 = Theme.Color.Accent,
					TextXAlignment = Enum.TextXAlignment.Center,
					TextYAlignment = Enum.TextYAlignment.Center,
				}),
			}),

			-- ⚔ FIGHT MODE BUTTON
			FightBtn = React.createElement("TextButton", {
				Name = "FightBtn",
				Size = UDim2.new(0.5, -16, 1, -4),
				Position = UDim2.new(0.5, 14, 0, 2),
				BackgroundColor3 = if isArenaMode then Theme.Color.Accent else Theme.Color.SurfaceRaised,
				BackgroundTransparency = if isArenaMode then 0 else 0.5,
				AutoButtonColor = true,
				Text = "⚔ Fight Mode",
				FontFace = Theme.FontFace.BodyBold,
				TextSize = 11,
				TextColor3 = if isArenaMode then DARK_TEXT else Theme.Color.TextSecondary,
				TextTruncate = Enum.TextTruncate.AtEnd,
				ClipsDescendants = true,
				[React.Event.Activated] = function()
					if not isArenaMode then
						ViewMode.requestToggle()
					end
				end,
			}, {
				Corner = React.createElement("UICorner", { CornerRadius = Theme.corner(Theme.Metrics.RadiusSmall) }),
				Stroke = React.createElement("UIStroke", {
					ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
					Color = Theme.Color.Accent,
					Transparency = if isArenaMode then 0 else 0.35,
					Thickness = 1.8,
				}),
			}),
		}),

		-- ===== INTEGRATED MINIMAP DOCK (KEPT VISIBLE ACROSS ALL MODES AT BOTTOM-LEFT) =====
		IntegratedMinimapWing = React.createElement("Frame", {
			Name = "IntegratedMinimapWing",
			Size = UDim2.fromOffset(MINIMAP_DOCK_SIZE, MINIMAP_DOCK_SIZE),
			Position = UDim2.new(0, 12, 1, -12),
			AnchorPoint = Vector2.new(0, 1),
			BackgroundColor3 = Theme.Color.Surface,
			BackgroundTransparency = Theme.Transparency.Panel,
			BorderSizePixel = 0,
			ZIndex = 12,
			Visible = true,
		}, {
			Stroke = React.createElement("UIStroke", Theme.celticStrokeProps()),
			Corners = React.createElement(MedievalCorners, { size = 18, color = Theme.Color.Accent, thickness = 2.5 }),

			-- 280x280 MINIMAP FRAME
			MiniMapFrame = React.createElement("Frame", {
				Name = "MiniMapFrame",
				Size = UDim2.fromOffset(MINIMAP_SIZE, MINIMAP_SIZE),
				Position = UDim2.new(0.5, 0, 0.5, 0),
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = Theme.Color.Surface,
				BackgroundTransparency = Theme.Transparency.Panel,
				ClipsDescendants = true,
				ZIndex = 20,
			}, {
				Corner = React.createElement("UICorner", { CornerRadius = Theme.corner(Theme.Metrics.Radius) }),
				Stroke = React.createElement("UIStroke", Theme.celticStrokeProps()),
				MiniMap = React.createElement(MiniMap),
			}),

			-- DYNAMIC ARROW BUTTON
			ExpandArrowBtn = React.createElement("TextButton", {
				Name = "ExpandArrowBtn",
				Size = UDim2.fromOffset(38, 20),
				Position = UDim2.new(0.5, 0, 0, arrowYOffset),
				AnchorPoint = Vector2.new(0.5, 1),
				BackgroundColor3 = Theme.Color.SurfaceRaised,
				BackgroundTransparency = 0,
				AutoButtonColor = true,
				Text = if isInfoDrawerOpen then "▼" else "▲",
				FontFace = Theme.FontFace.Display,
				TextSize = 13,
				TextColor3 = Theme.Color.Accent,
				TextStrokeTransparency = 1,
				ZIndex = 55,
				[React.Event.Activated] = function()
					setIsInfoDrawerOpen(not isInfoDrawerOpen)
				end,
			}, {
				Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 0) }),
				Stroke = React.createElement("UIStroke", Theme.celticStrokeProps()),
			}),

			-- STATUS BARS MODAL
			InfoDrawerFrame = isInfoDrawerOpen and React.createElement("Frame", {
				Name = "InfoDrawerFrame",
				Size = UDim2.new(1, 0, 0, STATUS_MODAL_HEIGHT),
				Position = UDim2.new(0, 0, 0, -STATUS_MODAL_HEIGHT - 4),
				BackgroundColor3 = Theme.Color.Surface,
				BackgroundTransparency = 0.05,
				ClipsDescendants = true,
				ZIndex = 50,
			}, {
				Corner = React.createElement("UICorner", { CornerRadius = Theme.corner() }),
				Stroke = React.createElement("UIStroke", Theme.celticStrokeProps()),
				Corners = React.createElement(MedievalCorners, { size = 14, color = Theme.Color.Accent, thickness = 2 }),

				ContentContainer = React.createElement("Frame", {
					Size = UDim2.fromScale(1, 1),
					BackgroundTransparency = 1,
					ZIndex = 51,
				}, {
					Padding = React.createElement("UIPadding", {
						PaddingTop = UDim.new(0, 8),
						PaddingBottom = UDim.new(0, 8),
						PaddingLeft = UDim.new(0, 8),
						PaddingRight = UDim.new(0, 8),
					}),
					Layout = React.createElement("UIListLayout", {
						FillDirection = Enum.FillDirection.Vertical,
						Padding = UDim.new(0, 6),
						SortOrder = Enum.SortOrder.LayoutOrder,
					}),
					LordHealthBar = lordHealthBar,
					MoraleBar = moraleBar,
				}),
			}) or nil,
		}),

		-- ===== MAIN FLOATING CENTERED COMMAND ISLAND DOCK (880x230PX, HIDDEN IN FIGHT MODE) =====
		BottomBar = React.createElement("Frame", {
			Name = "BottomBar",
			Size = UDim2.fromOffset(BOTTOM_BAR_WIDTH, BOTTOM_BAR_HEIGHT),
			Position = UDim2.new(0.5, 0, 1, -12),
			AnchorPoint = Vector2.new(0.5, 1),
			BackgroundColor3 = Theme.Color.Surface,
			BackgroundTransparency = Theme.Transparency.Panel,
			BorderSizePixel = 0,
			ZIndex = 10,
			Visible = not isArenaMode, -- HIDDEN IN FIGHT MODE
		}, {
			Stroke = React.createElement("UIStroke", Theme.celticStrokeProps()),
			Corners = React.createElement(MedievalCorners, { size = 18, color = Theme.Color.Accent, thickness = 2.5 }),

			-- CENTER COLUMN: PERSISTENT Category column on left + GOLD DIVIDER LINE + main selection content on right
			CenterColumn = React.createElement("Frame", {
				Name = "CenterColumn",
				Size = UDim2.new(1, -RIGHT_COL_WIDTH, 1, 0),
				Position = UDim2.new(0, 0, 0, 0),
				BackgroundTransparency = 1,
				ClipsDescendants = true,
				ZIndex = 11,
			}, {
				Padding = React.createElement("UIPadding", {
					PaddingTop = UDim.new(0, Theme.Metrics.PadTight + 4),
					PaddingBottom = UDim.new(0, Theme.Metrics.PadTight + 4),
					PaddingLeft = UDim.new(0, Theme.Metrics.PadTight + 4),
					PaddingRight = UDim.new(0, 6),
				}),

				CategoryColumnContainer = React.createElement("Frame", {
					Name = "CategoryColumnContainer",
					Size = UDim2.new(0, 96, 1, 0),
					Position = UDim2.new(0, 0, 0, 0),
					BackgroundTransparency = 1,
				}, {
					CategoryColumn = React.createElement(CategoryColumn),
				}),

				-- SLEEK VERTICAL GOLD DIVIDER LINE SEPARATING CATEGORIES FROM SELECTION PANELS
				VerticalDivider = React.createElement("Frame", {
					Name = "VerticalDivider",
					Size = UDim2.new(0, 1, 1, -8),
					Position = UDim2.new(0, 98, 0, 4),
					BackgroundColor3 = Theme.Color.Accent,
					BackgroundTransparency = 0.4,
					BorderSizePixel = 0,
				}, {
					Corner = React.createElement("UICorner", { CornerRadius = UDim.new(1, 0) }),
				}),

				-- MAIN CONTENT SELECTION CONTAINER (STRICTLY CONTAINED TO PREVENT OVERFLOW INTO RIGHT COLUMN)
				MainContent = React.createElement("Frame", {
					Name = "MainContent",
					Size = UDim2.new(1, -108, 1, 0),
					Position = UDim2.new(0, 108, 0, 0),
					BackgroundTransparency = 1,
					ClipsDescendants = true,
				}, {
					Content = if hasContextDock
						then contextualPanel
						else React.createElement(DesktopBuildingGrid, { tooltip = props.tooltip, gridOnly = true }),
				}),
			}),

			-- ===== RIGHT COLUMN: UNIFORM 2-COLUMN SQUARE ACTION MATRIX =====
			RightColumn = React.createElement("Frame", {
				Name = "RightColumn",
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, 0, 0, 0),
				Size = UDim2.new(0, RIGHT_COL_WIDTH, 1, 0),
				BackgroundTransparency = 1,
				ZIndex = 11,
			}, {
				Padding = React.createElement("UIPadding", {
					PaddingTop = UDim.new(0, 14),
					PaddingBottom = UDim.new(0, 14),
					PaddingLeft = UDim.new(0, 6),
					PaddingRight = UDim.new(0, 6),
				}),
				ActionMatrix = React.createElement("Frame", {
					Name = "ActionMatrix",
					Size = UDim2.new(1, 0, 1, 0),
					BackgroundTransparency = 1,
				}, {
					Layout = React.createElement("UIGridLayout", {
						CellSize = UDim2.fromOffset(40, 40),
						CellPadding = UDim2.fromOffset(6, 6),
						SortOrder = Enum.SortOrder.LayoutOrder,
					}),
					MenuBtn = squareActionButton("Menu", "☰", "Menu", showMenuModal, function()
						HUDStore.setMenuModal(not showMenuModal)
					end, 1),
					StatsBtn = squareActionButton("Stats", "🏰", "Stats", showStatsModal, function()
						HUDStore.setStatsModal(not showStatsModal)
					end, 2),
					PoliciesBtn = squareActionButton("Policies", "📜", "Laws", showPoliciesModal, function()
						HUDStore.togglePoliciesModal()
					end, 3),
					TechBtn = squareActionButton("Tech", "🔬", "Tech", showTechTreeModal, function()
						HUDStore.setTechTreeModal(not showTechTreeModal)
					end, 4),
					AbilitiesBtn = squareActionButton("Abilities", "⚜", "Skills", showAbilityTree, function()
						HUDStore.toggleAbilityTree()
					end, 5),
					DeleteBtn = squareActionButton("Delete", "🗑", "Delete", isDeleteMode, function()
						HUDStore.toggleDeleteMode()
					end, 6),
					UndoBtn = squareActionButton("Undo", "↶", "Undo", hasUndoHistory, function()
						if hasUndoHistory then
							HUDStore.undoLastDeletion()
						end
					end, 7),
				}),
			}),
		}),

		-- ===== MODALS & OVERLAYS =====
		TutorialModal = tutorialModal,

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
		}) or nil,

		StatsModal = showStatsModal and React.createElement(Stats, {
			visible = showStatsModal,
			onClose = function()
				HUDStore.setStatsModal(false)
			end,
		}) or nil,

		TechTreeModal = showTechTreeModal and React.createElement(TechTreePanel, {
			visible = showTechTreeModal,
			onClose = function()
				HUDStore.setTechTreeModal(false)
			end,
		}) or nil,
	})
end

return DesktopShell
