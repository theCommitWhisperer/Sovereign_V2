local React = require(game.ReplicatedStorage.Packages.react)
local UIConfig = require(script.Parent.Parent.Parent.UIConfig)
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DebugManager = require(ReplicatedStorage.Shared.DebugManager)
local HUDDebug = DebugManager.createChannel("HUD", false)

local ResourceDisplay = require(script.Parent.ResourceDisplay)
local BuildingMenu = require(script.Parent.BuildingMenu)
local SelectionPanel = require(script.Parent.SelectionPanel)
local TrainingPanel = require(script.Parent.TrainingPanel)
local UnitSelectionPanel = require(script.Parent.UnitSelectionPanel)
local WorkerAssignmentPanel = require(script.Parent.WorkerAssignmentPanel)
local MiniMap = require(script.Parent.MiniMap)
local FogOverlay = require(script.Parent.FogOverlay)
local Policies = require(script.Parent.Parent.Policies.Policies)
local Menu = require(script.Parent.Parent.Menu.Menu)
local Stats = require(script.Parent.Parent.Stats.Stats)
local TutorialModal = require(script.Parent.Parent.Parent.components.TutorialModal)
local HeroAbilitiesPanel = require(script.Parent.HeroAbilitiesPanel)
local UpgradePanel = require(script.Parent.UpgradePanel)
local TechTree = require(script.Parent.TechTree)
local QuestTracker = require(script.Parent.QuestTracker)
local AchievementNotification = require(script.Parent.AchievementNotification)

local player = Players.LocalPlayer

local HUD = React.Component:extend("HUD")

function HUD:init()
	HUDDebug:info("Initializing...")

	self:setState({
		resources = {
			Wood = 0,
			Stone = 0,
			Gold = 0,
			Food = 0,
			Weapons = 0,
			Iron_Bars = 0,
		},
		isPlacingBuilding = false,
		selectedBuilding = nil,
		selectedUnits = {},
		selectedTrainingBuilding = nil,
		selectedProductionBuilding = nil,
		trainingQueue = {},
		-- New state for UI
		showMenuModal = false,
		showStatsModal = false,
		showPoliciesModal = false,
		showTechTreeModal = false,
		showHeroAbilities = false,
		achievementData = nil,
		buildingUpgradeInfo = nil,
		selectedCategory = "Defense", -- Defense, Economy, Housing, Food, Culture
		armySize = 0,
		honor = 0,
		glory = 0,
		population = 0,
		happiness = 50, -- 0-100, affects revolt meter
		isDeleteMode = false, -- Delete mode for removing buildings/units
		showExpandedMeters = false, -- Show expanded meter panel
		commandText = "", -- For admin command input
		economySnapshot = nil, -- Economy dashboard data
		stats = nil, -- Stats for the stats modal
		selectedFormation = "Line", -- Default formation type
		-- Tutorial state
		tutorialEnabled = false, -- Whether full tutorial (Storehouse + Granary) is enabled
		showKeepModal = true, -- Always show Keep modal initially
		tutorialStep = 1, -- Current step (1=Keep, 2=Storehouse, 3=Granary)
		buildingsCompleted = {}, -- Track which required buildings have been built
		tutorialModalHidden = false, -- Temporarily hide modal during placement
		-- Camera mode
		cameraMode = "RTS", -- Current camera mode: "RTS" or "King"
		-- King health
		kingHealth = 100,
		kingMaxHealth = 100,
		-- Wall placement
		currentWallPiece = "Wall Segment",
		isPlacingWall = false,
	})

	-- Get game event reference
	local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
	self.gameEvent = RemoteEvents:WaitForChild("GameEvent")
	self.getStatsEvent = RemoteEvents:WaitForChild("GetStats")

	self.statsConnection = self.getStatsEvent.OnClientEvent:Connect(function(stats)
		self:setState({ stats = stats })
	end)

	-- Request initial quest data
	task.delay(0.5, function()
		self.gameEvent:FireServer("GetQuests")
	end)

	-- Initialize from gameStartData prop if available
	if self.props.gameStartData then
		local data = self.props.gameStartData
		HUDDebug:info("Initializing from gameStartData prop", data)
		if data.resources then
			local tutorialEnabled = if data.showTutorial ~= nil then data.showTutorial else true
			HUDDebug:info("Tutorial setting from prop", { showTutorial = data.showTutorial, tutorialEnabled = tutorialEnabled })
			self:setState({
				resources = data.resources,
				tutorialEnabled = tutorialEnabled,
			})
		end
	end

	self.connection = self.gameEvent.OnClientEvent:Connect(function(action, data)
		if action == "GameStarted" and data.resources then
			HUDDebug:info("Received resources from event", { resources = data.resources })
			-- Set tutorial state based on game settings
			local tutorialEnabled = if data.showTutorial ~= nil then data.showTutorial else true
			HUDDebug:info("Tutorial setting from event", { showTutorial = data.showTutorial, tutorialEnabled = tutorialEnabled })
			self:setState({
				resources = data.resources,
				tutorialEnabled = tutorialEnabled,
			})
		elseif action == "BuildingPlaced" and data.buildingType then
			-- Handle tutorial progression when buildings are placed
			HUDDebug:info("Building placed", { buildingType = data.buildingType })
			self:onBuildingPlaced(data.buildingType)
		elseif action == "UpdateResources" and data.resources then
			HUDDebug:info("Resources updated", { resources = data.resources })
			self:setState({ resources = data.resources })
		elseif action == "StartPlacement" and typeof(data) == "string" then
			HUDDebug:info("Server approved placement", { buildingType = data })
			-- Update HUD state to show wall indicator
			self:setState({
				isPlacingBuilding = true,
				selectedBuilding = data,
			})
		elseif action == "TrainingQueueUpdate" then
			-- Update training queue display
			if data.buildingId and data.queue then
				HUDDebug:info("Training queue updated", {
					buildingId = data.buildingId,
					queueLength = #data.queue,
				})
				self:setState({ trainingQueue = data.queue })
			end
        elseif action == "UpdateHappiness" and data.happiness then
            HUDDebug:info("Happiness updated", { happiness = data.happiness })
            self:setState({ happiness = data.happiness })
        elseif action == "UpdatePopulation" and data.current then
            HUDDebug:info("Population updated", { population = data.current })
            self:setState({ population = data.current })
		elseif action == "EconomyNotification" then
			-- Economy notification (from NotificationManager)
			if data.title and data.message then
				local typePrefix = ""
				if data.type == "critical" then
					typePrefix = "🔴 CRITICAL: "
				elseif data.type == "alert" then
					typePrefix = "🟠 ALERT: "
				elseif data.type == "warning" then
					typePrefix = "🟡 WARNING: "
				elseif data.type == "success" then
					typePrefix = "🟢 SUCCESS: "
				else
					typePrefix = "ℹ️ INFO: "
				end

				HUDDebug:info(`{typePrefix}{data.title}`, { message = data.message })
				-- TODO: Show notification UI banner
				-- For now, just log it
			end
		elseif action == "EconomyDashboardUpdate" then
			-- Economy dashboard snapshot
			if data.snapshot then
				HUDDebug:info("Economy dashboard updated", {
					season = data.snapshot.season,
					weather = data.snapshot.weather,
					economyHealth = data.snapshot.economyHealth,
				})
				self:setState({ economySnapshot = data.snapshot })
			end
		elseif action == "CameraModeChanged" then
			-- Camera mode changed (RTS/King)
			if typeof(data) == "string" then
				HUDDebug:info("Camera mode changed", { mode = data })
				self:setState({ cameraMode = data })
				-- Request hero abilities when entering King mode
				if data == "King" then
					self.gameEvent:FireServer("GetAbilities")
					self:setState({ showHeroAbilities = true })
				else
					self:setState({ showHeroAbilities = false })
				end
			end
		elseif action == "KingHealthUpdate" then
			-- King health changed
			if data.health and data.maxHealth then
				HUDDebug:info("King health updated", { health = data.health, maxHealth = data.maxHealth })
				self:setState({ kingHealth = data.health, kingMaxHealth = data.maxHealth })
			end
		elseif action == "VikingRaid" then
			-- Viking raid notification
			if data.raidNumber and data.vikingCount then
				HUDDebug:info("Viking Raid!", {
					raidNumber = data.raidNumber,
					vikingCount = data.vikingCount,
				})

				-- TODO: Show notification UI
				-- For now, just log it
		elseif action == "AchievementUnlocked" then
			-- Achievement notification
			HUDDebug:info("Achievement Unlocked!", data)
			self:setState({ achievementData = data })
			-- Auto-clear after component handles it
			task.delay(6, function()
				self:setState({ achievementData = nil })
			end)
		elseif action == "BuildingUpgraded" then
			-- Building was upgraded
			HUDDebug:info("Building Upgraded", data)
		elseif action == "ResearchStarted" then
			-- Research started
			HUDDebug:info("Research Started", data)
		elseif action == "ResearchCompleted" then
			-- Research completed
			HUDDebug:info("Research Completed", data)
		elseif action == "QuestCompleted" then
			-- Quest completed
			HUDDebug:info("Quest Completed", data)
			-- Refresh quest list
			self.gameEvent:FireServer("GetQuests")
		elseif action == "QuestProgress" then
			-- Quest progress updated
			HUDDebug:info("Quest Progress", data)
			-- Refresh quest list
			self.gameEvent:FireServer("GetQuests")
		elseif action == "QuestsData" then
			-- Quest data received
			HUDDebug:info("Received quests data", data)
			self:setState({ activeQuests = data.activeQuests or {} })
		elseif action == "AbilitiesData" then
			-- Hero abilities data received
			HUDDebug:info("Received abilities data", data)
			self:setState({ heroAbilities = data.abilities or {} })
		elseif action == "AbilityCooldownUpdate" then
			-- Ability cooldown updated
			HUDDebug:info("Ability cooldown update", data)
			-- Update specific ability cooldown
			if self.state.heroAbilities and data.abilityId then
				local abilities = table.clone(self.state.heroAbilities)
				for _, ability in abilities do
					if ability.id == data.abilityId then
						ability.remainingCooldown = data.remainingCooldown
						ability.isOnCooldown = data.isOnCooldown
						break
					end
				end
				self:setState({ heroAbilities = abilities })
			end
		elseif action == "KingRespawned" then
			-- King respawned
			HUDDebug:info("King Respawned", data)
				HUDDebug:warn(`VIKING RAID #${data.raidNumber}! {data.vikingCount} Vikings are attacking!`)
			end
		end
	end)

	-- Listen for selection changes
	task.spawn(function()
		local ClientScripts = player:WaitForChild("PlayerScripts"):WaitForChild("Client")
		local SelectionManager = require(ClientScripts.Selection.SelectionManager)

		-- Store SelectionManager reference for later use
		self.selectionManager = SelectionManager

		SelectionManager.SelectionChanged:Connect(function(selectedUnits)
			self:setState({ selectedUnits = selectedUnits })
		end)
	end)

	-- Listen for building clicks
	self:setupBuildingSelection()

	-- Listen for wall piece updates from PlacementController via BindableEvent
	local wallPieceEvent = ReplicatedStorage:FindFirstChild("WallPieceChanged")
	if not wallPieceEvent then
		wallPieceEvent = Instance.new("BindableEvent")
		wallPieceEvent.Name = "WallPieceChanged"
		wallPieceEvent.Parent = ReplicatedStorage
	end

	self.wallPieceConnection = wallPieceEvent.Event:Connect(function(data)
		HUDDebug:info("Wall piece state changed", {
			oldPiece = self.state.currentWallPiece,
			newPiece = data.currentPiece,
			isPlacingWalls = data.isPlacingWalls,
		})
		self:setState({
			currentWallPiece = data.currentPiece,
			isPlacingWall = data.isPlacingWalls,
		})
	end)

	-- Store reference to reset function via BindableFunction
	local resetWallPieceFunc = ReplicatedStorage:FindFirstChild("ResetWallPiece")
	if resetWallPieceFunc then
		self.resetWallPieceFunc = resetWallPieceFunc
	end

	-- Request queue updates periodically if a building is selected
	-- Using a reference to track the current building for polling
	self.pollingBuildingId = nil
	task.spawn(function()
		while true do
			task.wait(0.5)
			if self.pollingBuildingId then
				self.gameEvent:FireServer("GetTrainingQueue", {
					buildingId = self.pollingBuildingId,
				})
			end
		end
	end)
end

-- Tutorial: Handle building placement to progress tutorial
function HUD:onBuildingPlaced(buildingType)
	-- Tutorial buildings in order
	local tutorialBuildings = { "Keep", "Storehouse", "Granary" }
	local currentRequiredBuilding = tutorialBuildings[self.state.tutorialStep]

	if buildingType == currentRequiredBuilding then
		HUDDebug:info("Tutorial: Required building placed", { buildingType = buildingType, step = self.state.tutorialStep })

		-- Mark building as completed
		local newCompleted = table.clone(self.state.buildingsCompleted)
		newCompleted[buildingType] = true

		-- Special handling for Keep (step 1)
		if self.state.tutorialStep == 1 then
			-- Keep is done
			if self.state.tutorialEnabled then
				-- Tutorial is enabled, continue to Storehouse
				HUDDebug:info("Tutorial: Keep placed, moving to Storehouse")
				self:setState({
					buildingsCompleted = newCompleted,
					tutorialStep = 2,
					tutorialModalHidden = false,
					showKeepModal = false,
				})
			else
				-- Tutorial disabled, just close the Keep modal
				HUDDebug:info("Tutorial: Keep placed, tutorial disabled - closing modal")
				self:setState({
					buildingsCompleted = newCompleted,
					showKeepModal = false,
					tutorialModalHidden = false,
				})
			end
		-- Check if all tutorial buildings are complete
		elseif self.state.tutorialStep >= #tutorialBuildings then
			-- Tutorial complete! Disable tutorial to hide modal
			HUDDebug:info("Tutorial: Complete!")
			self:setState({
				buildingsCompleted = newCompleted,
				tutorialEnabled = false, -- Disable tutorial to prevent modal from showing
				tutorialModalHidden = false,
				showKeepModal = false,
			})
		else
			-- Move to next step and show modal again
			self:setState({
				buildingsCompleted = newCompleted,
				tutorialStep = self.state.tutorialStep + 1,
				tutorialModalHidden = false,
			})
		end
	end
end

-- Tutorial: Handle when player clicks "Build" button in tutorial modal
function HUD:onTutorialBuildRequested(buildingType, isAutoTriggered)
	HUDDebug:info("Tutorial: Build requested", { buildingType = buildingType, isAutoTriggered = isAutoTriggered })

	-- Only hide modal if not auto-triggered (manual button clicks hide modal)
	-- Auto-triggered steps keep modal visible so player can read instructions while placing
	if not isAutoTriggered then
		HUDDebug:info("Tutorial: Hiding modal (manual trigger)")
		self:setState({ tutorialModalHidden = true })
	else
		HUDDebug:info("Tutorial: Keeping modal visible (auto trigger)")
	end

	-- Trigger building placement (same event as BuildingMenu uses)
	self.gameEvent:FireServer("StartPlacement", buildingType)
end

function HUD:setupBuildingSelection()
	-- Listen for building clicks
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		HUDDebug:info("Input detected", {
			inputType = tostring(input.UserInputType),
			gameProcessed = gameProcessed,
		})

		if gameProcessed then
			HUDDebug:info("Input was game processed, ignoring")
			return
		end

		-- Left click on buildings to select them for training
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			local mousePosition = UserInputService:GetMouseLocation()
			local camera = workspace.CurrentCamera
			local ray = camera:ScreenPointToRay(mousePosition.X, mousePosition.Y)

			local raycastParams = RaycastParams.new()
			raycastParams.FilterType = Enum.RaycastFilterType.Exclude
			local filterList = { player.Character }
			if workspace:FindFirstChild("Terrain") then
				table.insert(filterList, workspace.Terrain)
			end
			raycastParams.FilterDescendantsInstances = filterList

			local result = workspace:Raycast(ray.Origin, ray.Direction * 1000, raycastParams)

			if result and result.Instance then
				HUDDebug:info("Clicked on instance", {
					name = result.Instance.Name,
					class = result.Instance.ClassName,
				})

				-- Check if clicked object is a building (either Model or Part with BuildingType)
				local building = nil

				-- Check if it has a BuildingType attribute (it's a building)
				if result.Instance:GetAttribute("BuildingType") then
					building = result.Instance
					HUDDebug:info("Instance is a building (has BuildingType attribute)")
				-- Or check if it's inside a Model with BuildingType
				elseif result.Instance:IsA("Model") and result.Instance:GetAttribute("BuildingType") then
					building = result.Instance
					HUDDebug:info("Instance is a Model building")
				else
					-- Look for Model ancestor with BuildingType
					local model = result.Instance:FindFirstAncestorOfClass("Model")
					if model and model:GetAttribute("BuildingType") then
						building = model
						HUDDebug:info("Found Model ancestor with BuildingType")
					end
				end

				if building then
					HUDDebug:info("Found building", {
						name = building.Name,
						class = building.ClassName,
					})

					local buildingType = building:GetAttribute("BuildingType")
					local owner = building:GetAttribute("Owner")

					HUDDebug:info("Building attributes", {
						buildingType = buildingType,
						owner = owner,
						playerId = player.UserId,
						ownerMatch = owner == player.UserId,
					})

					if buildingType and owner == player.UserId then
						-- If delete mode is active, delete the building
						if self.state.isDeleteMode then
							HUDDebug:info("Delete mode: Deleting building", {
								buildingType = buildingType,
								buildingName = building.Name,
							})

							-- Send delete request to server
							self.gameEvent:FireServer("DeleteBuilding", {
								buildingId = building.Name,
							})

							-- Turn off delete mode after deletion
							self:setState({ isDeleteMode = false })
						else
							-- Normal mode: Check if building can train units
							local GameData = require(game.ReplicatedStorage.Shared.GameData)
							local buildingInfo = GameData.Buildings[buildingType]

							HUDDebug:info("Building info check", {
								exists = buildingInfo ~= nil,
								canTrain = buildingInfo and buildingInfo.can_train_units ~= nil,
							})

							if buildingInfo and buildingInfo.can_train_units then
								HUDDebug:info("Selected training building", {
									buildingType = buildingType,
									trainableUnits = buildingInfo.can_train_units,
								})

								self:setState({
									selectedTrainingBuilding = building,
									selectedProductionBuilding = React.None,
									trainingQueue = {},
								})

								-- Start polling for this building
								self.pollingBuildingId = building.Name

								-- Request current queue
								self.gameEvent:FireServer("GetTrainingQueue", {
									buildingId = building.Name,
								})
							elseif buildingInfo and buildingInfo.produces_resource then
								HUDDebug:info("Selected production building", {
									buildingType = buildingType,
									produces = buildingInfo.produces_resource,
								})

								self:setState({
									selectedProductionBuilding = building,
									selectedTrainingBuilding = React.None,
									trainingQueue = {},
								})
							else
								HUDDebug:info("Building cannot train units or produce resources")
								-- Clear panels if building can't train or produce
								self.pollingBuildingId = nil
								self:setState({
									selectedTrainingBuilding = React.None,
									selectedProductionBuilding = React.None,
									trainingQueue = {},
								})
							end
						end
					else
						HUDDebug:warn("Building check failed", {
							hasBuildingType = buildingType ~= nil,
							ownerMatch = owner == player.UserId,
						})
						-- Clear panels if building check failed
						self.pollingBuildingId = nil
						self:setState({
							selectedTrainingBuilding = React.None,
							selectedProductionBuilding = React.None,
							trainingQueue = {},
						})
					end
				else
					HUDDebug:info("No building found")
					-- Clear panels when clicking on non-building
					self.pollingBuildingId = nil
					self:setState({
						selectedTrainingBuilding = React.None,
						selectedProductionBuilding = React.None,
						trainingQueue = {},
					})
				end
			else
				HUDDebug:info("Raycast hit nothing")
				-- Clear panels when clicking on nothing
				self.pollingBuildingId = nil
				self:setState({
					selectedTrainingBuilding = React.None,
					selectedProductionBuilding = React.None,
					trainingQueue = {},
				})
			end
		end
	end)
end

function HUD:willUnmount()
	if self.connection then
		self.connection:Disconnect()
	end
end

-- Helper function to create stat boxes for top bar
function HUD:createStatBox(label: string, value: any, icon: string)
	return React.createElement("Frame", {
		Size = UDim2.new(0, UIConfig.HUD.StatBoxWidth, 1, 0),
		BackgroundColor3 = UIConfig.HUD.StatBoxBackground,
		BorderSizePixel = 1,
		BorderColor3 = UIConfig.HUD.StatBoxBorder,
	}, {
		Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 4),
		}),

		Icon = React.createElement("TextLabel", {
			Size = UDim2.new(0, 16, 0, 16),
			BackgroundTransparency = 1,
			Text = icon,
			TextSize = 14,
		}),

		Value = React.createElement("TextLabel", {
			Size = UDim2.new(1, -20, 1, 0),
			BackgroundTransparency = 1,
			Text = tostring(value),
			Font = Enum.Font.GothamBold,
			TextSize = 13,
			TextColor3 = UIConfig.HUD.StatTextColor,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
	})
end

-- Helper function to create expanded meter in the meter panel
function HUD:createExpandedMeter(label: string, icon: string, value: number, maxValue: number, layoutOrder: number)
	local percentage = math.clamp(value / maxValue, 0, 1)

	return React.createElement("Frame", {
		Size = UDim2.new(1, 0, 0, 28),
		BackgroundTransparency = 1,
		LayoutOrder = layoutOrder,
	}, {
		-- Icon
		Icon = React.createElement("TextLabel", {
			Size = UDim2.fromOffset(28, 28),
			Position = UDim2.fromOffset(0, 0),
			BackgroundTransparency = 1,
			Text = icon,
			Font = Enum.Font.GothamBold,
			TextSize = 18,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Center,
		}),

		-- Bar container
		BarContainer = React.createElement("Frame", {
			Size = UDim2.new(1, -65, 0, 20),
			Position = UDim2.fromOffset(32, 4),
			BackgroundColor3 = Color3.fromRGB(40, 40, 40),
			BorderSizePixel = 1,
			BorderColor3 = UIConfig.HUD.MeterBorder,
		}, {
			-- Fill bar
			FillBar = React.createElement("Frame", {
				Size = UDim2.fromScale(percentage, 1),
				BackgroundColor3 = UIConfig.HUD.CategoryButtonSelected, -- Whiskey color
				BorderSizePixel = 0,
			}),
		}),

		-- Value text
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

-- Helper functions for season and weather icons
function HUD:getSeasonIcon(season: string?): string
	if season == "Spring" then
		return "🌸"
	elseif season == "Summer" then
		return "☀️"
	elseif season == "Autumn" then
		return "🍂"
	elseif season == "Winter" then
		return "❄️"
	end
	return "🌸" -- Default to Spring
end

function HUD:getWeatherIcon(weather: string?): string
	if weather == "Clear" then
		return "☀️"
	elseif weather == "Rain" then
		return "🌧️"
	elseif weather == "Storm" then
		return "⛈️"
	elseif weather == "Drought" then
		return "🌵"
	end
	return "☀️" -- Default to Clear
end

-- Helper function to create category buttons for bottom bar (icon only)
function HUD:createCategoryButton(category: string, icon: string)
	local isSelected = self.state.selectedCategory == category

	-- Set layout order based on category
	local layoutOrder = 1
	if category == "Defense" then
		layoutOrder = 1
	elseif category == "Economy" then
		layoutOrder = 2
	elseif category == "Housing" then
		layoutOrder = 3
	elseif category == "Food" then
		layoutOrder = 4
	elseif category == "Culture" then
		layoutOrder = 5
	end

	return React.createElement("TextButton", {
		Size = UDim2.new(1, 0, 0, UIConfig.HUD.CategoryButtonHeight),
		BackgroundColor3 = isSelected and UIConfig.HUD.CategoryButtonSelected or UIConfig.HUD.CategoryButtonBackground,
		BorderSizePixel = 1,
		BorderColor3 = UIConfig.HUD.CategoryButtonBorder,
		Text = icon, -- Icon only, no text
		Font = Enum.Font.GothamBold,
		TextSize = 20, -- Larger icon
		TextColor3 = UIConfig.HUD.PanelTextColor,
		LayoutOrder = layoutOrder,
		[React.Event.MouseButton1Click] = function()
			HUDDebug:info(`Category button clicked: {category}`)
			HUDDebug:info(`Current selectedTrainingBuilding: {tostring(self.state.selectedTrainingBuilding)}`)

			-- Reset wall piece selection when clicking on HUD
			if self.resetWallPieceFunc then
				self.resetWallPieceFunc:Invoke()
			end

			-- Stop polling when switching to building menu
			self.pollingBuildingId = nil
			HUDDebug:info(`Stopped polling, pollingBuildingId set to nil`)
			HUDDebug:info("About to call setState to clear training building")
			self:setState({
				selectedCategory = category,
				-- Clear panels and unit selection when switching to building menu (use React.None to clear)
				selectedTrainingBuilding = React.None,
				selectedProductionBuilding = React.None,
				trainingQueue = {},
				selectedUnits = {},
			})
			HUDDebug:info("setState called successfully")
		end,
	})
end

function HUD:render()
	HUDDebug:info("Rendering", { resources = self.state.resources })

	local hasUnitsSelected = #self.state.selectedUnits > 0
	local hasTrainingBuildingSelected = self.state.selectedTrainingBuilding ~= nil
	local hasProductionBuildingSelected = self.state.selectedProductionBuilding ~= nil

	HUDDebug:info(`Render state check: selectedTrainingBuilding={tostring(self.state.selectedTrainingBuilding)}, hasTrainingBuildingSelected={hasTrainingBuildingSelected}, hasProductionBuildingSelected={hasProductionBuildingSelected}`)
	local showBuildingsInContent = not hasUnitsSelected and not hasTrainingBuildingSelected and not hasProductionBuildingSelected

	-- Category icons
	local CATEGORY_ICONS = {
		Castle = "🏰",
		Military = "⚔️",
		Housing = "🏠",
		Food = "🌾",
		Industry = "🔨",
	}

	return React.createElement("ScreenGui", {
		Name = "HUDGui",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		IgnoreGuiInset = true,
	}, {
		-- ===== TOP BAR =====
		TopBar = React.createElement("Frame", {
			Name = "TopBar",
			Size = UDim2.new(1, 0, 0, UIConfig.HUD.TopBarHeight),
			Position = UDim2.fromScale(0, 0),
			BackgroundColor3 = UIConfig.HUD.TopBarBackground,
			BorderSizePixel = 1,
			BorderColor3 = UIConfig.HUD.TopBarBorder,
			ZIndex = 10,
		}, {
			-- MENU button (far left)
			MenuButton = React.createElement("TextButton", {
				Size = UDim2.new(0, UIConfig.HUD.TopButtonWidth, 0, UIConfig.HUD.TopButtonHeight),
				Position = UDim2.new(0, 5, 0, 5),
				BackgroundColor3 = UIConfig.HUD.TopButtonBackground,
				BorderSizePixel = 1,
				BorderColor3 = UIConfig.HUD.TopButtonBorder,
				Text = "MENU",
				Font = Enum.Font.GothamBold,
				TextSize = 14,
				TextColor3 = UIConfig.HUD.PanelTextColor,
				[React.Event.MouseButton1Click] = function()
					self:setState({ showMenuModal = not self.state.showMenuModal })
				end,
			}),

			-- STATS button (next to MENU)
			StatsButton = React.createElement("TextButton", {
				Size = UDim2.new(0, UIConfig.HUD.TopButtonWidth, 0, UIConfig.HUD.TopButtonHeight),
				Position = UDim2.new(0, UIConfig.HUD.TopButtonWidth + 10, 0, 5),
				BackgroundColor3 = UIConfig.HUD.TopButtonBackground,
				BorderSizePixel = 1,
				BorderColor3 = UIConfig.HUD.TopButtonBorder,
				Text = "STATS",
				Font = Enum.Font.GothamBold,
				TextSize = 14,
				TextColor3 = UIConfig.HUD.PanelTextColor,
				[React.Event.MouseButton1Click] = function()
					self.getStatsEvent:FireServer("GetStats")
					self:setState({ showStatsModal = not self.state.showStatsModal })
				end,
			}),

			-- TECH button (next to STATS)
			TechButton = React.createElement("TextButton", {
				Size = UDim2.new(0, UIConfig.HUD.TopButtonWidth, 0, UIConfig.HUD.TopButtonHeight),
				Position = UDim2.new(0, (UIConfig.HUD.TopButtonWidth + 5) * 2 + 5, 0, 5),
				BackgroundColor3 = UIConfig.HUD.TopButtonBackground,
				BorderSizePixel = 1,
				BorderColor3 = UIConfig.HUD.TopButtonBorder,
				Text = "TECH",
				Font = Enum.Font.GothamBold,
				TextSize = 14,
				TextColor3 = UIConfig.HUD.PanelTextColor,
				[React.Event.MouseButton1Click] = function()
					self:setState({ showTechTreeModal = not self.state.showTechTreeModal })
				end,
			}),

			-- Camera Mode Indicator (next to TECH)
			CameraModeIndicator = React.createElement("Frame", {
				Size = UDim2.new(0, UIConfig.HUD.TopButtonWidth, 0, UIConfig.HUD.TopButtonHeight),
				Position = UDim2.new(0, (UIConfig.HUD.TopButtonWidth + 5) * 3 + 5, 0, 5),
				BackgroundColor3 = self.state.cameraMode == "King" and Color3.fromRGB(90, 60, 40) or UIConfig.HUD.TopButtonBackground,
				BorderSizePixel = 2,
				BorderColor3 = self.state.cameraMode == "King" and UIConfig.HUD.AccentGold or UIConfig.HUD.TopButtonBorder,
			}, {
				Icon = React.createElement("TextLabel", {
					Size = UDim2.new(1, 0, 0.5, 0),
					Position = UDim2.fromScale(0, 0),
					BackgroundTransparency = 1,
					Text = self.state.cameraMode == "King" and "👑" or "🗺️",
					Font = Enum.Font.GothamBold,
					TextSize = 18,
					TextColor3 = Color3.fromRGB(255, 255, 255),
					TextYAlignment = Enum.TextYAlignment.Center,
				}),
				Label = React.createElement("TextLabel", {
					Size = UDim2.new(1, 0, 0.5, 0),
					Position = UDim2.fromScale(0, 0.5),
					BackgroundTransparency = 1,
					Text = self.state.cameraMode == "King" and "KING" or "RTS",
					Font = Enum.Font.GothamBold,
					TextSize = 10,
					TextColor3 = self.state.cameraMode == "King" and UIConfig.HUD.AccentGold or UIConfig.HUD.PanelTextColor,
					TextYAlignment = Enum.TextYAlignment.Top,
				}),
				Hint = React.createElement("TextLabel", {
					Size = UDim2.new(1, 0, 0, 12),
					Position = UDim2.new(0, 0, 1, 2),
					BackgroundTransparency = 1,
					Text = "Tab to toggle",
					Font = Enum.Font.Gotham,
					TextSize = 9,
					TextColor3 = Color3.fromRGB(150, 150, 150),
					TextYAlignment = Enum.TextYAlignment.Top,
				}),
			}),

			-- King Health Bar (only visible in King mode)
			KingHealthBar = self.state.cameraMode == "King" and React.createElement("Frame", {
				Size = UDim2.new(0, UIConfig.HUD.TopButtonWidth + 80, 0, 30),
				Position = UDim2.new(0, (UIConfig.HUD.TopButtonWidth + 5) * 3 + 10, 0, 5),
				BackgroundColor3 = Color3.fromRGB(40, 40, 40),
				BorderSizePixel = 2,
				BorderColor3 = UIConfig.HUD.AccentGold,
			}, {
				-- Health icon
				Icon = React.createElement("TextLabel", {
					Size = UDim2.fromOffset(24, 24),
					Position = UDim2.fromOffset(3, 3),
					BackgroundTransparency = 1,
					Text = "❤️",
					Font = Enum.Font.GothamBold,
					TextSize = 16,
					TextXAlignment = Enum.TextXAlignment.Center,
					TextYAlignment = Enum.TextYAlignment.Center,
				}),

				-- Health bar container
				BarContainer = React.createElement("Frame", {
					Size = UDim2.new(1, -60, 0, 16),
					Position = UDim2.fromOffset(30, 7),
					BackgroundColor3 = Color3.fromRGB(20, 20, 20),
					BorderSizePixel = 1,
					BorderColor3 = Color3.fromRGB(100, 100, 100),
				}, {
					-- Health bar fill (green to red based on percentage)
					HealthBar = React.createElement("Frame", {
						Size = UDim2.fromScale(self.state.kingHealth / self.state.kingMaxHealth, 1),
						BackgroundColor3 = self.state.kingHealth / self.state.kingMaxHealth > 0.5
							and Color3.fromRGB(0, 200, 0)
							or self.state.kingHealth / self.state.kingMaxHealth > 0.25
							and Color3.fromRGB(255, 165, 0)
							or Color3.fromRGB(200, 0, 0),
						BorderSizePixel = 0,
					}),
				}),

				-- Health text (e.g., "100/100")
				HealthText = React.createElement("TextLabel", {
					Size = UDim2.new(1, -35, 1, 0),
					Position = UDim2.fromOffset(30, 0),
					BackgroundTransparency = 1,
					Text = string.format("%d/%d", self.state.kingHealth, self.state.kingMaxHealth),
					Font = Enum.Font.GothamBold,
					TextSize = 11,
					TextColor3 = Color3.fromRGB(255, 255, 255),
					TextXAlignment = Enum.TextXAlignment.Center,
					TextYAlignment = Enum.TextYAlignment.Center,
					TextStrokeTransparency = 0.5,
					TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
				}),
			}) or nil,

			-- Command Input TextBox (below MENU/STATS buttons)
			CommandInput = React.createElement("TextBox", {
				Size = UDim2.new(0, UIConfig.HUD.TopButtonWidth * 2 + 5, 0, 25),
				Position = UDim2.new(0, 5, 0, UIConfig.HUD.TopButtonHeight + 10),
				BackgroundColor3 = Color3.fromRGB(30, 30, 30),
				BorderSizePixel = 1,
				BorderColor3 = UIConfig.HUD.TopButtonBorder,
				PlaceholderText = "Admin command (/help)",
				PlaceholderColor3 = Color3.fromRGB(120, 120, 120),
				Text = self.state.commandText,
				Font = Enum.Font.Code,
				TextSize = 12,
				TextColor3 = Color3.fromRGB(0, 255, 0),
				TextXAlignment = Enum.TextXAlignment.Left,
				ClearTextOnFocus = false,
				[React.Change.Text] = function(rbx)
					self:setState({ commandText = rbx.Text })
				end,
				[React.Event.FocusLost] = function(rbx, enterPressed)
					if enterPressed and self.state.commandText ~= "" then
						-- Send command to server
						local commandText = self.state.commandText
						if commandText:sub(1, 1) == "/" then
							commandText = commandText:sub(2) -- Remove leading /
						end

						HUDDebug:info("Sending admin command", { command = commandText })
						self.gameEvent:FireServer("TestCommand", commandText)

						-- Clear the text box
						self:setState({ commandText = "" })
					end
				end,
			}),

			-- Center stats container (Army, Honor, Glory, Date, Gold, Food, Population)
			CenterStats = React.createElement("Frame", {
				Size = UDim2.new(0, 600, 1, -10),
				Position = UDim2.new(0.5, -300, 0, 5),
				BackgroundTransparency = 1,
			}, {
				Layout = React.createElement("UIListLayout", {
					FillDirection = Enum.FillDirection.Horizontal,
					HorizontalAlignment = Enum.HorizontalAlignment.Center,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					Padding = UDim.new(0, 8),
				}),

				-- Army Size
				ArmyBox = self:createStatBox("Army", self.state.armySize, "👥"),
				-- Honor
				HonorBox = self:createStatBox("Honor", self.state.honor, "🎖️"),
				-- Glory
				GloryBox = self:createStatBox("Glory", self.state.glory, "⭐"),
				-- Date (placeholder)
				DateBox = self:createStatBox("Date", "Y1 M1", "📅"),
				-- Gold
				GoldBox = self:createStatBox("Gold", self.state.resources.Gold, "💰"),
				-- Food
				FoodBox = self:createStatBox("Food", self.state.resources.Food, "🌾"),
				-- Population
				PopBox = self:createStatBox("Pop", self.state.population, "👤"),
				-- Season (if available)
				SeasonBox = self.state.economySnapshot and self:createStatBox(
					"",
					self.state.economySnapshot.season or "Spring",
					self:getSeasonIcon(self.state.economySnapshot.season)
				) or nil,
				-- Weather (if available)
				WeatherBox = self.state.economySnapshot and self:createStatBox(
					"",
					self.state.economySnapshot.weather or "Clear",
					self:getWeatherIcon(self.state.economySnapshot.weather)
				) or nil,
			}),
		}),

		-- ===== BOTTOM BAR ===== (Delete/Policies | Minimap | 5 Categories | Content Area)
		BottomBar = React.createElement("Frame", {
			Name = "BottomBar",
			Size = UDim2.new(1, 0, 0, UIConfig.HUD.BottomBarHeight),
			Position = UDim2.new(0, 0, 1, 0), -- Flush to bottom
			AnchorPoint = Vector2.new(0, 1),
			BackgroundColor3 = UIConfig.HUD.BottomBarBackground,
			BorderSizePixel = 1,
			BorderColor3 = UIConfig.HUD.BottomBarBorder,
			ZIndex = 10,
		}, {
			-- Delete/Policies buttons (stacked on far left)
			UtilityButtons = React.createElement("Frame", {
				Size = UDim2.new(0, UIConfig.HUD.UtilityButtonWidth, 0, UIConfig.HUD.BottomBarHeight),
				Position = UDim2.new(0, 5, 0, 0),
				BackgroundTransparency = 1,
			}, {
				Padding = React.createElement("UIPadding", {
					PaddingTop = UDim.new(0, 15),
					PaddingBottom = UDim.new(0, 15),
				}),

				Layout = React.createElement("UIListLayout", {
					FillDirection = Enum.FillDirection.Vertical,
					Padding = UDim.new(0, 5),
					HorizontalAlignment = Enum.HorizontalAlignment.Center,
					VerticalAlignment = Enum.VerticalAlignment.Top,
				}),

				DeleteButton = React.createElement("TextButton", {
					Size = UDim2.new(1, 0, 0, UIConfig.HUD.UtilityButtonHeight),
					BackgroundColor3 = self.state.isDeleteMode and UIConfig.HUD.CategoryButtonSelected
						or UIConfig.HUD.UtilityButtonBackground,
					BorderSizePixel = 1,
					BorderColor3 = UIConfig.HUD.UtilityButtonBorder,
					Text = "🗑️", -- Icon only
					Font = Enum.Font.GothamBold,
					TextSize = 18,
					TextColor3 = UIConfig.HUD.PanelTextColor,
					[React.Event.MouseButton1Click] = function()
						self:setState({ isDeleteMode = not self.state.isDeleteMode })
						HUDDebug:info("Delete mode toggled", { isDeleteMode = not self.state.isDeleteMode })
					end,
				}),

				PoliciesButton = React.createElement("TextButton", {
					Size = UDim2.new(1, 0, 0, UIConfig.HUD.UtilityButtonHeight),
					BackgroundColor3 = UIConfig.HUD.UtilityButtonBackground,
					BorderSizePixel = 1,
					BorderColor3 = UIConfig.HUD.UtilityButtonBorder,
					Text = "📜", -- Icon only
					Font = Enum.Font.GothamBold,
					TextSize = 18,
					TextColor3 = UIConfig.HUD.PanelTextColor,
					[React.Event.MouseButton1Click] = function()
						self:setState({ showPoliciesModal = not self.state.showPoliciesModal })
					end,
				}),
			}),

			-- Minimap (next to utility buttons)
			MiniMapFrame = React.createElement("Frame", {
				Name = "MiniMapFrame",
				Size = UDim2.new(0, UIConfig.HUD.MinimapSize, 0, UIConfig.HUD.MinimapSize),
				Position = UDim2.new(0, UIConfig.HUD.UtilityButtonWidth + 10, 0, 10), -- 10px from top
				BackgroundColor3 = Color3.fromRGB(0, 0, 0),
				BorderColor3 = UIConfig.HUD.MinimapBorder,
				BorderSizePixel = 2,
			}, {
				MiniMap = React.createElement(MiniMap),
			}),

			-- Fog of War indicator
			FogOfWarIndicator = React.createElement(FogOverlay),

			-- 5 Category buttons (stacked vertically, next to minimap) - Icon only with padding
			CategoryButtons = React.createElement("Frame", {
				Size = UDim2.new(0, UIConfig.HUD.CategoryButtonWidth, 0, UIConfig.HUD.BottomBarHeight),
				Position = UDim2.new(0, UIConfig.HUD.UtilityButtonWidth + UIConfig.HUD.MinimapSize + 15, 0, 0),
				BackgroundTransparency = 1,
			}, {
				UIPadding = React.createElement("UIPadding", {
					PaddingTop = UDim.new(0, 10),
					PaddingBottom = UDim.new(0, 10),
				}),

				Layout = React.createElement("UIListLayout", {
					FillDirection = Enum.FillDirection.Vertical,
					Padding = UDim.new(0, 6),
					HorizontalAlignment = Enum.HorizontalAlignment.Center,
					VerticalAlignment = Enum.VerticalAlignment.Top,
				}),

				-- Defense button (🛡️)
				DefenseButton = self:createCategoryButton("Defense", "🛡️"),
				-- Economy button (💰)
				EconomyButton = self:createCategoryButton("Economy", "💰"),
				-- Housing button (🏠)
				HousingButton = self:createCategoryButton("Housing", "🏠"),
				-- Food button (🌾)
				FoodButton = self:createCategoryButton("Food", "🌾"),
				-- Culture button (⛪)
				CultureButton = self:createCategoryButton("Culture", "⛪"),
			}),

			-- Content Area (shows buildings OR selected units)
			ContentArea = React.createElement("Frame", {
				Size = UDim2.new(
					1,
					-(
							UIConfig.HUD.UtilityButtonWidth
							+ UIConfig.HUD.MinimapSize
							+ UIConfig.HUD.CategoryButtonWidth
							+ 30
						),
					1,
					-10
				),
				Position = UDim2.new(
					0,
					UIConfig.HUD.UtilityButtonWidth + UIConfig.HUD.MinimapSize + UIConfig.HUD.CategoryButtonWidth + 20,
					0,
					5
				),
				BackgroundColor3 = UIConfig.HUD.ContentAreaBackground,
				BorderSizePixel = 1,
				BorderColor3 = UIConfig.HUD.ContentAreaBorder,
			}, {
				-- Content priority: Training Panel > Production Panel > Hero Abilities > Upgrade Panel > Unit Selection > Building Menu
				Content = hasTrainingBuildingSelected and React.createElement(TrainingPanel, {
					selectedBuilding = self.state.selectedTrainingBuilding,
					queue = self.state.trainingQueue,
					onTrainUnit = function(unitType)
						HUDDebug:info(`Training unit: {unitType}`)
						if self.state.selectedTrainingBuilding then
							self.gameEvent:FireServer("StartTraining", {
								buildingId = self.state.selectedTrainingBuilding.Name,
								unitType = unitType,
							})
						end
					end,
					onClose = function()
						HUDDebug:info("Training panel close button clicked")
						-- Stop polling when closing training panel
						self.pollingBuildingId = nil
						HUDDebug:info(`Stopped polling, pollingBuildingId set to nil`)
						self:setState({
							selectedTrainingBuilding = React.None,
							trainingQueue = {},
						})
					end,
				}) or hasProductionBuildingSelected and React.createElement(WorkerAssignmentPanel, {
					selectedBuilding = self.state.selectedProductionBuilding,
					onClose = function()
						HUDDebug:info("Worker assignment panel close button clicked")
						self:setState({
							selectedProductionBuilding = React.None,
						})
					end,
				}) or (self.state.cameraMode == "King" and self.state.showHeroAbilities) and React.createElement(HeroAbilitiesPanel, {
					abilities = self.state.heroAbilities,
					onAbilityUsed = function(abilityId)
						HUDDebug:info(`Using hero ability: {abilityId}`)
						self.gameEvent:FireServer("UseAbility", abilityId)
					end,
				}) or self.state.buildingUpgradeInfo and React.createElement(UpgradePanel, {
					buildingInfo = self.state.buildingUpgradeInfo,
					playerResources = self.state.resources,
					onUpgrade = function()
						HUDDebug:info(`Upgrading building: {self.state.buildingUpgradeInfo.buildingId}`)
						self.gameEvent:FireServer("UpgradeBuilding", self.state.buildingUpgradeInfo.buildingId)
					end,
					onClose = function()
						self:setState({ buildingUpgradeInfo = React.None })
					end,
				}) or hasUnitsSelected and React.createElement(UnitSelectionPanel, {
					selectedUnits = self.state.selectedUnits,
					selectedFormation = self.state.selectedFormation,
					onFormationSelected = function(formationType)
						HUDDebug:info(`Formation selected: {formationType}`)
						self:setState({ selectedFormation = formationType })
						-- Also update SelectionManager
						if self.selectionManager then
							self.selectionManager.setFormationType(formationType)
						end

						-- Immediately arrange units in formation at their current location
						if #self.state.selectedUnits >= 2 then
							local unitIds = {}
							for _, unit in self.state.selectedUnits do
								table.insert(unitIds, unit:GetAttribute("UnitId") or unit.Name)
							end

							-- Calculate average position of selected units
							local avgPosition = Vector3.new(0, 0, 0)
							for _, unit in self.state.selectedUnits do
								if unit.PrimaryPart then
									avgPosition = avgPosition + unit.PrimaryPart.Position
								end
							end
							avgPosition = avgPosition / #self.state.selectedUnits

							-- Offset formation center slightly forward (in camera's facing direction)
							-- This prevents units from colliding with each other when forming up
							local camera = workspace.CurrentCamera
							local cameraLook = camera.CFrame.LookVector
							local horizontalLook = Vector3.new(cameraLook.X, 0, cameraLook.Z).Unit
							local formationOffset = horizontalLook * 8  -- Move formation 8 studs forward from average position
							local targetPosition = avgPosition + formationOffset

							-- Send formation command to server
							self.gameEvent:FireServer("MoveUnitsInFormation", {
								unitIds = unitIds,
								targetPosition = targetPosition,
								formationType = formationType,
							})

							HUDDebug:info(`Arranging {#unitIds} units in {formationType} formation at offset position`)
						end
					end,
				}) or React.createElement(BuildingMenu, {
					tooltip = self.props.tooltip, -- Pass tooltip API down
					resources = self.state.resources,
					selectedCategory = self.state.selectedCategory,
					currentWallPiece = self.state.currentWallPiece,
					isPlacingWall = self.state.isPlacingWall,
					onBuildingSelected = function(buildingName)
						HUDDebug:info("Building selected for placement", { building = buildingName })
						self:setState({
							isPlacingBuilding = true,
							selectedBuilding = buildingName,
						})
						self.gameEvent:FireServer("StartPlacement", buildingName)
					end,
				}),
			}),
		}),

		-- Happiness/Revolt Meter Panel (right side, top of bottom bar)
		MeterPanel = React.createElement("Frame", {
			Name = "MeterPanel",
			Size = UDim2.new(0, 280, 0, self.state.showExpandedMeters and 280 or 50),
			Position = UDim2.new(
				1,
				-290,
				1,
				-UIConfig.HUD.BottomBarHeight - (self.state.showExpandedMeters and 280 or 60)
			),
			BackgroundTransparency = 1,
			ZIndex = 10,
		}, {
			-- Expand/Collapse button (arrow at top, narrower)
			ExpandButton = React.createElement("TextButton", {
				Size = UDim2.new(0, 80, 0, 20),
				Position = UDim2.new(0.5, -40, 0, 0),
				BackgroundColor3 = UIConfig.HUD.UtilityButtonBackground,
				BorderSizePixel = 1,
				BorderColor3 = UIConfig.HUD.MeterBorder,
				Text = self.state.showExpandedMeters and "▼" or "▲",
				Font = Enum.Font.GothamBold,
				TextSize = 14,
				TextColor3 = UIConfig.HUD.PanelTextColor,
				[React.Event.MouseButton1Click] = function()
					self:setState({ showExpandedMeters = not self.state.showExpandedMeters })
				end,
			}),

			-- Main meter background
			MeterBackground = React.createElement("Frame", {
				Size = UDim2.new(1, 0, 1, -10),
				Position = UDim2.fromOffset(0, 20),
				BackgroundColor3 = UIConfig.HUD.MeterBackground,
				BorderSizePixel = 2,
				BorderColor3 = UIConfig.HUD.MeterBorder,
			}, {
				-- Main happiness meter
				HappinessMeter = React.createElement("Frame", {
					Size = UDim2.new(1, -20, 0, 30), -- Use a fixed pixel height (35px) instead of scaling
					Position = UDim2.fromOffset(10, 5),
					BackgroundTransparency = 1,
				}, {
					-- Happy emoji (left)
					HappyEmoji = React.createElement("TextLabel", {
						Size = UDim2.new(0, 35, 0, 35),
						Position = UDim2.fromOffset(0, 0),
						BackgroundTransparency = 1,
						Text = "😊",
						Font = Enum.Font.GothamBold,
						TextSize = 24,
						TextXAlignment = Enum.TextXAlignment.Center,
						TextYAlignment = Enum.TextYAlignment.Center,
					}),

					-- Bar container
					BarContainer = React.createElement("Frame", {
						Size = UDim2.new(1, -80, 1, -6),
						Position = UDim2.fromOffset(40, 3),
						BackgroundColor3 = Color3.fromRGB(40, 40, 40),
						BorderSizePixel = 1,
						BorderColor3 = UIConfig.HUD.MeterBorder,
					}, {
						-- Happiness bar (green, fills from left)
						HappyBar = React.createElement("Frame", {
							Size = UDim2.new(self.state.happiness / 100, 0, 1, 0),
							Position = UDim2.fromOffset(0, 0),
							BackgroundColor3 = UIConfig.HUD.MeterHappyColor,
							BorderSizePixel = 0,
						}),

						-- Revolt indicator (red, fills from right when happiness < 50)
						RevoltBar = React.createElement("Frame", {
							Size = UDim2.new(math.max(0, (50 - self.state.happiness) / 100), 0, 1, 0),
							Position = UDim2.new(1, 0, 0, 0),
							AnchorPoint = Vector2.new(1, 0),
							BackgroundColor3 = UIConfig.HUD.MeterRevoltColor,
							BorderSizePixel = 0,
						}),
					}),

					-- Mad emoji (right)
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

			-- Expanded meters (conditionally rendered)
			ExpandedMeters = self.state.showExpandedMeters
					and React.createElement("Frame", {
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

							-- Food meter
							FoodMeter = self:createExpandedMeter("Food", "🌾", self.state.resources.Food, 500, 1),
							-- Gold meter
							GoldMeter = self:createExpandedMeter("Gold", "💰", self.state.resources.Gold, 1000, 2),
							-- Population / Housing meter
							PopulationMeter = self.state.economySnapshot and self:createExpandedMeter(
								"Population",
								"👥",
								self.state.economySnapshot.population or 0,
								self.state.economySnapshot.housingCapacity or 10,
								3
							) or self:createExpandedMeter("Population", "👥", self.state.population, 100, 3),
							-- Economy Health meter
							EconomyHealthMeter = self.state.economySnapshot and self:createExpandedMeter(
								"Economy",
								"🏰",
								self.state.economySnapshot.economyHealth or 50,
								100,
								4
							) or nil,
							-- Food Consumption Rate meter (visual indicator)
							FoodConsumptionMeter = self.state.economySnapshot and self:createExpandedMeter(
								"Consumption",
								"🍴",
								math.min(self.state.economySnapshot.foodConsumptionRate or 0, 10),
								10,
								5
							) or nil,
							-- Tax Rate meter
							TaxRateMeter = self.state.economySnapshot and self:createExpandedMeter(
								"Tax Rate",
								"💸",
								self.state.economySnapshot.taxRate or 0,
								100,
								6
							) or nil,
						}),
					})
				or nil,
		}),

		-- Policies Modal (conditionally rendered)
		PoliciesModal = self.state.showPoliciesModal and React.createElement(Policies, {
			visible = self.state.showPoliciesModal,
			onClose = function()
				self:setState({ showPoliciesModal = false })
			end,
		}) or nil,

		-- Menu Modal (conditionally rendered)
		MenuModal = self.state.showMenuModal and React.createElement(Menu, {
			visible = self.state.showMenuModal,
			onClose = function()
				self:setState({ showMenuModal = false })
			end,
			navigate = self.props.navigate,
		}) or nil,

		-- Stats Modal (conditionally rendered)
		StatsModal = self.state.showStatsModal
				and React.createElement(Stats, {
					visible = self.state.showStatsModal,
					onClose = function()
						self:setState({ showStatsModal = false })
					end,
					-- Pass stats data
					stats = self.state.stats,
					population = self.state.population,
					armySize = self.state.armySize,
					honor = self.state.honor,
					glory = self.state.glory,
					happiness = self.state.happiness,
					-- Pass economy data
					economySnapshot = self.state.economySnapshot,
				})
			or nil,

		-- Tech Tree Modal (conditionally rendered)
		TechTreeModal = self.state.showTechTreeModal and React.createElement(TechTree, {
			visible = self.state.showTechTreeModal,
			playerResources = self.state.resources,
			onClose = function()
				self:setState({ showTechTreeModal = false })
			end,
			onResearchStarted = function(techId)
				HUDDebug:info(`Starting research: {techId}`)
				self.gameEvent:FireServer("StartResearch", techId)
			end,
		}) or nil,

		-- Quest Tracker (right side panel, always visible)
		QuestTrackerPanel = React.createElement(QuestTracker, {
			quests = self.state.activeQuests or {},
		}),

		-- Achievement Notification (overlay, conditionally rendered)
		AchievementNotificationOverlay = self.state.achievementData and React.createElement(AchievementNotification, {
			achievementData = self.state.achievementData,
			onDismiss = function()
				self:setState({ achievementData = React.None })
			end,
		}) or nil,

		-- Tutorial Modal (required buildings guide)
		-- Step 1 (Keep) always shows, Steps 2-3 only if tutorialEnabled
		TutorialModal = (function()
			-- Determine if modal should be shown
			local isKeepStep = self.state.tutorialStep == 1
			local showKeep = isKeepStep and self.state.showKeepModal
			local showTutorialStep = (not isKeepStep) and self.state.tutorialStep <= 3 and self.state.tutorialEnabled
			local shouldShow = not self.state.tutorialModalHidden and (showKeep or showTutorialStep)

			HUDDebug:info("Tutorial modal render check", {
				tutorialEnabled = self.state.tutorialEnabled,
				showKeepModal = self.state.showKeepModal,
				tutorialModalHidden = self.state.tutorialModalHidden,
				tutorialStep = self.state.tutorialStep,
				shouldShow = shouldShow,
			})

			if shouldShow then
				return React.createElement(TutorialModal, {
					visible = true,
					currentStep = self.state.tutorialStep,
					onBuildRequested = function(buildingType, isAutoTriggered)
						self:onTutorialBuildRequested(buildingType, isAutoTriggered)
					end,
				})
			else
				return nil
			end
		end)(),
	})
end

return HUD
