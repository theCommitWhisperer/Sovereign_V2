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
local ConfirmDeleteModal = require(script.Parent.ConfirmDeleteModal)
local MultiDeleteModal = require(script.Parent.MultiDeleteModal)
local IconButton = require(script.Parent.Parent.Parent.components.IconButton)
local TopBar = require(script.Parent.TopBar)
local UndoButton = require(script.Parent.UndoButton)
local BattleLog = require(script.Parent.BattleLog)

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
		selectedCategory = "Defense", -- Defense, Military, Industry, Food, Housing
		armySize = 0,
		honor = 0,
		glory = 0,
		population = 0,
		happiness = 50, -- 0-100, affects revolt meter
		weather = "Clear", -- Current weather condition
		date = "Y1 M1", -- Current game date
		isDeleteMode = false, -- Delete mode for removing buildings/units
		showExpandedMeters = false, -- Show expanded meter panel
		commandText = "", -- For admin command input
		economySnapshot = nil, -- Economy dashboard data
		stats = nil, -- Stats for the stats modal
		selectedFormation = "Line", -- Default formation type
		selectedStance = "March", -- Current stance for selected units
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
		-- Delete confirmation
		showDeleteConfirmation = false,
		buildingToDelete = nil,
		-- Multi-delete confirmation
		showMultiDeleteConfirmation = false,
		buildingsToDelete = {},
		-- Undo deletion history (last 5 deletions)
		deletionHistory = {},
		-- Battle log messages
		battleLogMessages = {},
		battleLogExpanded = false,
		-- Peace time countdown (seconds remaining, 0 = expired / not active)
		peaceTimeRemaining = 0,
		-- Active victory condition mode from lobby settings
		victoryCondition = "Score",
	})

	-- Get game event reference with timeout to prevent infinite hang
	local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents", 10)
	if not RemoteEvents then
		warn("⚠️ [HUD] Failed to find RemoteEvents folder after 10 seconds")
		return
	end
	self.gameEvent = RemoteEvents:WaitForChild("GameEvent", 10)
	self.getStatsEvent = RemoteEvents:WaitForChild("GetStats", 10)

	if not self.gameEvent or not self.getStatsEvent then
		warn("⚠️ [HUD] Failed to find required RemoteEvents (GameEvent or GetStats)")
		return
	end

	-- Create/get delete mode event for visual feedback
	self.deleteModeEvent = ReplicatedStorage:FindFirstChild("DeleteModeChanged")
	if not self.deleteModeEvent then
		self.deleteModeEvent = Instance.new("BindableEvent")
		self.deleteModeEvent.Name = "DeleteModeChanged"
		self.deleteModeEvent.Parent = ReplicatedStorage
	end

	self.statsConnection = self.getStatsEvent.OnClientEvent:Connect(function(stats)
		self:setState({ stats = stats })
	end)

	-- Listen for multi-delete requests from drag selection
	local multiDeleteEvent = ReplicatedStorage:FindFirstChild("MultiDeleteRequested")
	if not multiDeleteEvent then
		multiDeleteEvent = Instance.new("BindableEvent")
		multiDeleteEvent.Name = "MultiDeleteRequested"
		multiDeleteEvent.Parent = ReplicatedStorage
	end

	multiDeleteEvent.Event:Connect(function(buildings: { Model })
		HUDDebug:info("Multi-delete requested", { count = #buildings })

		-- Calculate total refund
		local GameData = require(game.ReplicatedStorage.Shared.GameData)
		local totalRefund = {}
		local buildingInfoList = {}

		for _, building in buildings do
			local buildingType = building:GetAttribute("BuildingType")
			local isWall = building:FindFirstChild("PlacedPiece") ~= nil

			-- Determine actual type
			local actualType = buildingType
			if isWall and not buildingType then
				-- For walls without BuildingType attribute, use a generic name
				actualType = "Stone_Wall"
			end

			if actualType or isWall then
				-- Add to building list
				table.insert(buildingInfoList, {
					name = building.Name,
					type = actualType or "Stone_Wall",
					model = building,
					isWall = isWall,
				})

				-- Calculate refund (only for buildings, not walls)
				if buildingType and not isWall then
					local buildingInfo = GameData.Buildings[buildingType]
					if buildingInfo and buildingInfo.cost then
						for resourceType, cost in pairs(buildingInfo.cost) do
							local refund = math.floor(cost * 0.5)
							if refund > 0 then
								totalRefund[resourceType] = (totalRefund[resourceType] or 0) + refund
							end
						end
					end
				end
			end
		end

		-- Format refund string
		local refundText = nil
		if next(totalRefund) then
			local refundParts = {}
			for resourceType, amount in pairs(totalRefund) do
				table.insert(refundParts, string.format("%d %s", amount, resourceType))
			end
			refundText = table.concat(refundParts, ", ")
		end

		-- Show multi-delete confirmation
		self:setState({
			showMultiDeleteConfirmation = true,
			buildingsToDelete = buildingInfoList,
			multiDeleteRefund = refundText,
		})
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
			HUDDebug:info(
				"Tutorial setting from prop",
				{ showTutorial = data.showTutorial, tutorialEnabled = tutorialEnabled }
			)
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
			HUDDebug:info(
				"Tutorial setting from event",
				{ showTutorial = data.showTutorial, tutorialEnabled = tutorialEnabled }
			)
			local peaceTimeSecs = data.peaceTimeSeconds or 0
			self:setState({
				resources = data.resources,
				tutorialEnabled = tutorialEnabled,
				peaceTimeRemaining = peaceTimeSecs,
				victoryCondition = data.victoryCondition or "Score",
			})
			-- Start client-side countdown if peace time is active
			if peaceTimeSecs > 0 then
				task.spawn(function()
					local remaining = peaceTimeSecs
					while remaining > 0 do
						task.wait(1)
						remaining -= 1
						self:setState({ peaceTimeRemaining = remaining })
					end
				end)
			end
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
				self:setState({
					economySnapshot = data.snapshot,
					weather = data.snapshot.weather, -- Update weather in top bar
				})
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
			-- Reflect the actual stance of the selection in the highlight
			local firstStance = nil
			if selectedUnits[1] then
				firstStance = selectedUnits[1]:GetAttribute("Stance")
			end
			self:setState({
				selectedUnits = selectedUnits,
				selectedStance = firstStance or "March",
			})
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
		HUDDebug:info(
			"Tutorial: Required building placed",
			{ buildingType = buildingType, step = self.state.tutorialStep }
		)

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
		-- Ctrl+U to undo deletion (Ctrl+Z is intercepted by Roblox Studio)
		-- Check if U key is pressed while Ctrl is held down
		if input.KeyCode == Enum.KeyCode.U and input.UserInputType == Enum.UserInputType.Keyboard then
			if
				UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
				or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
			then
				self:undoLastDeletion()
				return
			end
		end

		-- Also check if Ctrl is pressed while U is already held down
		if
			(input.KeyCode == Enum.KeyCode.LeftControl or input.KeyCode == Enum.KeyCode.RightControl)
			and input.UserInputType == Enum.UserInputType.Keyboard
		then
			if UserInputService:IsKeyDown(Enum.KeyCode.U) then
				self:undoLastDeletion()
				return
			end
		end

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
			HUDDebug:info("MouseButton1 click at", { x = mousePosition.X, y = mousePosition.Y })

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
			HUDDebug:info(
				"Raycast result",
				{ hit = result ~= nil, instance = result and result.Instance.Name or "none" }
			)

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
					local owner = building:GetAttribute("OwnerId")

					HUDDebug:info("Building attributes", {
						buildingType = buildingType,
						owner = owner,
						playerId = player.UserId,
						ownerMatch = owner == player.UserId,
					})

					if buildingType and owner == player.UserId then
						-- If delete mode is active, let DeletionInputHandler handle it (don't process here)
						if self.state.isDeleteMode then
							HUDDebug:info("Delete mode active - DeletionInputHandler will handle this click")
							-- Don't process the click in HUD, DeletionInputHandler will handle deletion
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

		-- ESC key to cancel delete mode
		if input.KeyCode == Enum.KeyCode.Escape and self.state.isDeleteMode then
			HUDDebug:info("ESC pressed - turning off delete mode")
			self:setState({ isDeleteMode = false })
			if self.deleteModeEvent then
				self.deleteModeEvent:Fire(false)
			end
		end

		-- Right-click to cancel delete mode
		if input.UserInputType == Enum.UserInputType.MouseButton2 and self.state.isDeleteMode then
			HUDDebug:info("Right-click pressed - turning off delete mode")
			self:setState({ isDeleteMode = false })
			if self.deleteModeEvent then
				self.deleteModeEvent:Fire(false)
			end
		end
	end)
end

-- Undo deletion system
function HUD:addToDeletionHistory(buildingDataOrBatch)
	local history = table.clone(self.state.deletionHistory)

	-- Check if it's a batch (array) or single item
	local isBatch = buildingDataOrBatch[1] ~= nil and type(buildingDataOrBatch[1]) == "table"

	if isBatch then
		-- Store the batch as a single history entry
		local batch = {}
		for _, buildingData in buildingDataOrBatch do
			table.insert(batch, {
				buildingType = buildingData.type,
				buildingName = buildingData.name,
				position = buildingData.position,
				rotation = buildingData.rotation,
				isWall = buildingData.isWall,
			})
		end
		table.insert(history, {
			batch = batch,
			timestamp = os.time(),
		})
		HUDDebug:info("Added batch to deletion history", { count = #batch, historySize = #history })
	else
		-- Single item
		table.insert(history, {
			buildingType = buildingDataOrBatch.type,
			buildingName = buildingDataOrBatch.name,
			position = buildingDataOrBatch.position,
			rotation = buildingDataOrBatch.rotation,
			isWall = buildingDataOrBatch.isWall,
			timestamp = os.time(),
		})
		HUDDebug:info("Added to deletion history", { type = buildingDataOrBatch.type, historySize = #history })
	end

	-- Keep only last 5
	while #history > 5 do
		table.remove(history, 1)
	end

	self:setState({ deletionHistory = history })
end

function HUD:undoLastDeletion()
	local history = self.state.deletionHistory
	if #history == 0 then
		HUDDebug:warn("No deletions to undo")
		-- print("[UNDO] No deletions in history to undo")
		return
	end

	local lastDeletion = history[#history]
	HUDDebug:info("Undoing deletion", lastDeletion)

	-- Check if it's a batch
	if lastDeletion.batch then
		-- Restore batch of items
		local RemoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")
		local placePathEvent = RemoteEvents and RemoteEvents:FindFirstChild("PlaceWallPath")

		for _, item in lastDeletion.batch do
			if item.isWall then
				-- Restore wall piece
				if placePathEvent then
					-- Convert rotation from degrees (Orientation.Y) to radians
					local yRotationDegrees = item.rotation and item.rotation.Y or 0
					local yRotationRadians = math.rad(yRotationDegrees)
					placePathEvent:FireServer({
						{
							type = item.buildingType,
							position = item.position,
							rotation = yRotationRadians,
						},
					})
				end
			else
				-- Restore regular building
				self.gameEvent:FireServer("UndoDeletion", {
					buildingType = item.buildingType,
					position = item.position,
					rotation = item.rotation,
				})
			end
		end
		HUDDebug:info("Batch restoration sent", { count = #lastDeletion.batch })
	elseif lastDeletion.isWall then
		-- Restore single wall piece
		local RemoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")
		local placePathEvent = RemoteEvents and RemoteEvents:FindFirstChild("PlaceWallPath")

		if placePathEvent then
			-- Convert rotation from degrees (Orientation.Y) to radians
			local yRotationDegrees = lastDeletion.rotation and lastDeletion.rotation.Y or 0
			local yRotationRadians = math.rad(yRotationDegrees)
			placePathEvent:FireServer({
				{
					type = lastDeletion.buildingType,
					position = lastDeletion.position,
					rotation = yRotationRadians,
				},
			})
			HUDDebug:info("Wall piece restoration sent", { type = lastDeletion.buildingType })
		else
			warn("[UNDO] PlaceWallPath event not found!")
		end
	else
		-- Restore single regular building
		self.gameEvent:FireServer("UndoDeletion", {
			buildingType = lastDeletion.buildingType,
			position = lastDeletion.position,
			rotation = lastDeletion.rotation,
		})
	end

	-- Remove from history
	local newHistory = table.clone(history)
	table.remove(newHistory)
	self:setState({ deletionHistory = newHistory })

	HUDDebug:info("Undo complete, new history size:", #newHistory)
end

function HUD:willUnmount()
	if self.connection then
		self.connection:Disconnect()
	end
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

-- Helper function for season icons
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

-- Helper function to create category buttons for bottom bar (icon only)
function HUD:createCategoryButton(category: string, icon: string)
	local isSelected = self.state.selectedCategory == category

	-- Get the custom button image and position for this category
	local buttonImage = UIConfig.HUD.CategoryButtonImages[category] or "rbxassetid://105781657626004"
	local position = UIConfig.HUD.CategoryButtonPositions[category] or { X = 452, Y = 38 }

	-- Keep button hitbox constant to prevent blocking adjacent buttons
	local buttonSize = UDim2.fromOffset(UIConfig.HUD.CategoryButtonWidth, UIConfig.HUD.CategoryButtonHeight)
	local adjustedPosition = UDim2.fromOffset(position.X, position.Y)

	-- Visual scale for appearance only (1.5x when selected, hitbox stays 57x57)
	local visualScale = isSelected and 1.5 or 1.0

	return React.createElement(IconButton, {
		Size = buttonSize,
		Position = adjustedPosition,
		ButtonImage = buttonImage,
		ImageColor3 = Color3.fromRGB(255, 255, 255),
		ShowGlow = false,
		VisualScale = visualScale, -- Scale visual only, not hitbox
		ZIndex = isSelected and 20 or 11, -- Selected button on top of others
		OnClick = function()
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

	HUDDebug:info(
		`Render state check: selectedTrainingBuilding={tostring(self.state.selectedTrainingBuilding)}, hasTrainingBuildingSelected={hasTrainingBuildingSelected}, hasProductionBuildingSelected={hasProductionBuildingSelected}`
	)
	local showBuildingsInContent = not hasUnitsSelected
		and not hasTrainingBuildingSelected
		and not hasProductionBuildingSelected

	-- Category icons
	local CATEGORY_ICONS = {
		Castle = "🏰",
		Military = "⚔️",
		Housing = "🏠",
		Food = "🌾",
		Industry = "🔨",
	}

	-- Battle Arena mode: no economy — hide resource bars, build menus, meters,
	-- quests, and undo. BattleLog and notifications stay (combat-relevant).
	local isArenaMode = self.props.gameStartData ~= nil
		and self.props.gameStartData.mode == "BattleArena"

	return React.createElement("ScreenGui", {
		Name = "HUDGui",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		IgnoreGuiInset = true,
	}, {
		-- ===== TOP BAR =====
		TopBar = not isArenaMode and React.createElement(TopBar, {
			resources = self.state.resources,
			honor = self.state.honor,
			glory = self.state.glory,
			population = self.state.population,
			date = self.state.date,
			weather = self.state.weather,
			peaceTimeRemaining = self.state.peaceTimeRemaining,
			victoryCondition = self.state.victoryCondition,
		}) or nil,

		-- ===== BOTTOM BAR ===== (Delete/Policies | Minimap | 5 Categories | Content Area)
		BottomBar = React.createElement("Frame", {
			Name = "BottomBar",
			Size = UDim2.new(0, 1400, 0, UIConfig.HUD.BottomBarHeight), -- Fixed width to contain both images
			Position = UDim2.new(0, 0, 1, 0), -- Flush to bottom left
			AnchorPoint = Vector2.new(0, 1),
			BackgroundTransparency = 1, -- Transparent to show background images
			BorderSizePixel = 0,
			ZIndex = 10,
			-- Battle Arena: bar appears only with units selected, so players get
			-- formations/stances/selection controls but no build/economy UI
			Visible = not isArenaMode or hasUnitsSelected,
		}, {

			MainBackground = React.createElement("ImageLabel", {
				Name = "MainBackground",
				Size = UDim2.new(0, 800, 0, UIConfig.HUD.BottomBarHeight), -- Fixed width for left section
				Position = UDim2.new(0, 0, 0, 0), -- Start at left edge
				BackgroundTransparency = 1,
				Image = "rbxassetid://102075136386279",
				BorderSizePixel = 0,
				ZIndex = 10,
			}),

			-- Delete/Policies buttons (stacked on far left)
			UtilityButtons = React.createElement("Frame", {
				Size = UDim2.new(0, UIConfig.HUD.UtilityButtonWidth, 0, UIConfig.HUD.BottomBarHeight),
				Position = UDim2.new(0, 68, 0.26, 0), -- 20% right (160px from 800px), 20% down from top
				BackgroundTransparency = 1,
				ZIndex = 11, -- Above background images
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
					ImageColor3 = self.state.isDeleteMode and UIConfig.HUD.CategoryButtonSelected
						or UIConfig.HUD.UtilityButtonBackground,
					OnClick = function()
						local newDeleteMode = not self.state.isDeleteMode
						self:setState({ isDeleteMode = newDeleteMode })
						HUDDebug:info("Delete mode toggled", { isDeleteMode = newDeleteMode })

						-- When entering delete mode, cancel any active placement
						if newDeleteMode then
							-- Cancel wall placement
							self.gameEvent:FireServer("PlacementEnded")
							HUDDebug:info("Cancelled active placement modes")
						end

						-- Fire event for visual feedback controller
						if self.deleteModeEvent then
							self.deleteModeEvent:Fire(newDeleteMode)
						end
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
						self:setState({ showPoliciesModal = not self.state.showPoliciesModal })
					end,
				}),
			}),

			-- Minimap (next to utility buttons)
			MiniMapFrame = React.createElement("Frame", {
				Name = "MiniMapFrame",
				Size = UDim2.new(0, UIConfig.HUD.MinimapSize, 0, UIConfig.HUD.MinimapSize),
				Position = UDim2.new(0, 185, 0, 40), -- 10px from topPosition = UDim2.new(0, 160, 0.2, 0),
				BackgroundColor3 = Color3.fromRGB(0, 0, 0),
				BorderColor3 = UIConfig.HUD.MinimapBorder,
				BorderSizePixel = 2,
				ClipsDescendants = true, -- Clip contents to circular shape
				ZIndex = 9, -- Behind background images
			}, {
				Corner = React.createElement("UICorner", {
					CornerRadius = UDim.new(0.5, 0), -- Make it circular (50% radius)
				}),
				MiniMap = React.createElement(MiniMap),
			}),

			-- Fog of War indicator
			FogOfWarIndicator = React.createElement(FogOverlay),

			-- Category buttons (individually positioned)
			DefenseButton = self:createCategoryButton("Defense", "🛡️"),
			MilitaryButton = self:createCategoryButton("Military", "⚔️"),
			IndustryButton = self:createCategoryButton("Industry", "💰"),
			HousingButton = self:createCategoryButton("Housing", "🏠"),
			FoodButton = self:createCategoryButton("Food", "🌾"),

			-- Content Area (shows buildings OR selected units)
			ContentArea = React.createElement("Frame", {
				Size = UDim2.new(0.35, 215, 0, 10),
				Position = UDim2.new(0, 540, 0, 45),
				BackgroundTransparency = 1, -- Transparent to show background image
				BorderSizePixel = 0,
				ZIndex = 11, -- Above background images
			}, {
				-- Content priority: Training Panel > Production Panel > Hero Abilities > Upgrade Panel > Unit Selection > Building Menu
				Content = hasTrainingBuildingSelected
						and React.createElement(TrainingPanel, {
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
						})
					or hasProductionBuildingSelected and React.createElement(WorkerAssignmentPanel, {
						selectedBuilding = self.state.selectedProductionBuilding,
						onClose = function()
							HUDDebug:info("Worker assignment panel close button clicked")
							self:setState({
								selectedProductionBuilding = React.None,
							})
						end,
					})
					or (self.state.cameraMode == "King" and self.state.showHeroAbilities) and React.createElement(
						HeroAbilitiesPanel,
						{
							abilities = self.state.heroAbilities,
							onAbilityUsed = function(abilityId)
								HUDDebug:info(`Using hero ability: {abilityId}`)
								self.gameEvent:FireServer("UseAbility", abilityId)
							end,
						}
					)
					or self.state.buildingUpgradeInfo and React.createElement(UpgradePanel, {
						buildingInfo = self.state.buildingUpgradeInfo,
						playerResources = self.state.resources,
						onUpgrade = function()
							HUDDebug:info(`Upgrading building: {self.state.buildingUpgradeInfo.buildingId}`)
							self.gameEvent:FireServer("UpgradeBuilding", self.state.buildingUpgradeInfo.buildingId)
						end,
						onClose = function()
							self:setState({ buildingUpgradeInfo = React.None })
						end,
					})
					or hasUnitsSelected
						and React.createElement(UnitSelectionPanel, {
							selectedUnits = self.state.selectedUnits,
							selectedFormation = self.state.selectedFormation,
							selectedStance = self.state.selectedStance,
							onStanceSelected = function(stanceName)
								HUDDebug:info(`Stance selected: {stanceName}`)
								self:setState({ selectedStance = stanceName })
								local unitIds = {}
								for _, unit in self.state.selectedUnits do
									table.insert(unitIds, unit:GetAttribute("UnitId") or unit.Name)
								end
								if #unitIds > 0 then
									self.gameEvent:FireServer("SetStance", {
										UnitIDs = unitIds,
										Stance = stanceName,
									})
								end
							end,
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
									local formationOffset = horizontalLook * 8 -- Move formation 8 studs forward from average position
									local targetPosition = avgPosition + formationOffset

									-- Send formation command to server
									self.gameEvent:FireServer("MoveUnitsInFormation", {
										unitIds = unitIds,
										targetPosition = targetPosition,
										formationType = formationType,
									})

									HUDDebug:info(
										`Arranging {#unitIds} units in {formationType} formation at offset position`
									)
								end
							end,
						})
					or React.createElement(BuildingMenu, {
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
				-1300,
				1,
				-UIConfig.HUD.BottomBarHeight - (self.state.showExpandedMeters and 280 or 60)
			),
			BackgroundTransparency = 1,
			ZIndex = 10,
			Visible = not isArenaMode, -- Battle Arena: no happiness/revolt meters
		}, {
			-- Expand/Collapse button (arrow at top, narrower)
			ExpandButton = React.createElement(IconButton, {
				Size = UDim2.new(0, 80, 0, 20),
				Position = UDim2.new(0.5, -40, 0, 0),
				Icon = self.state.showExpandedMeters and "▼" or "▲",
				IconSize = 14,
				IconColor = UIConfig.HUD.PanelTextColor,
				ImageColor3 = UIConfig.HUD.UtilityButtonBackground,
				OnClick = function()
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

		-- Quest Tracker (right side panel; hidden in Battle Arena)
		QuestTrackerPanel = not isArenaMode and React.createElement(QuestTracker, {
			quests = self.state.activeQuests or {},
		}) or nil,

		-- Achievement Notification (overlay, conditionally rendered)
		AchievementNotificationOverlay = self.state.achievementData and React.createElement(AchievementNotification, {
			achievementData = self.state.achievementData,
			onDismiss = function()
				self:setState({ achievementData = React.None })
			end,
		}) or nil,

		-- Delete Confirmation Modal
		DeleteConfirmationModal = self.state.showDeleteConfirmation
				and self.state.buildingToDelete
				and ConfirmDeleteModal.new({
					buildingName = self.state.buildingToDelete.name,
					buildingType = self.state.buildingToDelete.type,
					refundInfo = self.state.buildingToDelete.refundInfo,
					onConfirm = function()
						-- Perform the deletion
						self.gameEvent:FireServer("DeleteBuilding", {
							buildingId = self.state.buildingToDelete.name,
						})

						-- Clear confirmation state but keep delete mode active
						self:setState({
							showDeleteConfirmation = false,
							buildingToDelete = React.None,
						})
						-- Delete mode stays active so player can keep deleting
					end,
					onCancel = function()
						-- Just close the dialog, keep delete mode active
						self:setState({
							showDeleteConfirmation = false,
							buildingToDelete = React.None,
						})
					end,
				})
			or nil,

		-- Multi-Delete Confirmation Modal
		MultiDeleteConfirmationModal = self.state.showMultiDeleteConfirmation
				and #self.state.buildingsToDelete > 0
				and MultiDeleteModal.new({
					buildings = self.state.buildingsToDelete,
					totalRefund = self.state.multiDeleteRefund,
					onConfirm = function(selectedBuildings)
						-- print(string.format("[HUD] Multi-delete confirmed with %d buildings", #selectedBuildings))

						-- Get RemoveWallPiece event for walls
						local RemoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")
						local removePieceEvent = RemoteEvents and RemoteEvents:FindFirstChild("RemoveWallPiece")

						-- Track deletions for undo (do this BEFORE deleting)
						local deletionBatch = {}
						for _, buildingInfo in selectedBuildings do
							local wallPieceType = nil
							if buildingInfo.isWall then
								-- Extract wall piece type from name (e.g., "Straight_1234.56" -> "Straight")
								wallPieceType = buildingInfo.name:match("^([^_]+)")
							end

							local buildingData = {
								type = wallPieceType or buildingInfo.type,
								name = buildingInfo.name,
								position = buildingInfo.model.PrimaryPart and buildingInfo.model.PrimaryPart.Position
									or Vector3.new(0, 0, 0),
								rotation = buildingInfo.model.PrimaryPart
										and buildingInfo.model.PrimaryPart.Orientation
									or Vector3.new(0, 0, 0),
								isWall = buildingInfo.isWall or false,
							}
							table.insert(deletionBatch, buildingData)
						end

						-- Add entire batch as one history entry
						if #deletionBatch > 0 then
							task.defer(function()
								self:addToDeletionHistory(deletionBatch)
							end)
						end

						-- Delete buildings
						for _, buildingInfo in selectedBuildings do
							-- print(
							-- 	string.format(
							-- 		"[HUD] Deleting: %s (isWall: %s)",
							-- 		buildingInfo.name,
							-- 		tostring(buildingInfo.isWall)
							-- 	)
							-- )
							if buildingInfo.isWall then
								-- Delete wall piece
								if removePieceEvent then
									-- print("[HUD] Firing RemoveWallPiece for wall:", buildingInfo.name)
									removePieceEvent:FireServer(buildingInfo.model)
								else
									warn("[HUD] RemoveWallPiece event not found!")
								end
							else
								-- Delete building
								-- print("[HUD] Firing DeleteBuilding for building:", buildingInfo.name)
								self.gameEvent:FireServer("DeleteBuilding", { buildingId = buildingInfo.name })
							end
						end
						self:setState({
							showMultiDeleteConfirmation = false,
							buildingsToDelete = {},
							multiDeleteRefund = React.None,
						})
					end,
					onCancel = function()
						self:setState({
							showMultiDeleteConfirmation = false,
							buildingsToDelete = {},
							multiDeleteRefund = React.None,
						})
					end,
				})
			or nil,

		-- Undo Button (bottom-right, above minimap; hidden in Battle Arena)
		UndoButton = not isArenaMode and React.createElement(UndoButton, {
			history = self.state.deletionHistory,
			onUndo = function()
				if #self.state.deletionHistory > 0 then
					local lastDeletion = self.state.deletionHistory[#self.state.deletionHistory]

					-- Send undo request to server
					self.gameEvent:FireServer("UndoDeletion", lastDeletion)

					-- Remove from history
					local newHistory = {}
					for i = 1, #self.state.deletionHistory - 1 do
						table.insert(newHistory, self.state.deletionHistory[i])
					end
					self:setState({ deletionHistory = newHistory })
				end
			end,
		}),

		-- Battle Log (bottom-right, above undo button)
		BattleLog = React.createElement(BattleLog, {
			messages = self.state.battleLogMessages,
			expanded = self.state.battleLogExpanded,
			onToggleExpanded = function()
				self:setState({ battleLogExpanded = not self.state.battleLogExpanded })
			end,
		}),

		-- Tutorial Modal (required buildings guide)
		-- Step 1 (Keep) always shows, Steps 2-3 only if tutorialEnabled
		TutorialModal = (function()
			-- Battle Arena: no buildings, no Keep — never show the tutorial modal
			if isArenaMode then
				return nil
			end
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
