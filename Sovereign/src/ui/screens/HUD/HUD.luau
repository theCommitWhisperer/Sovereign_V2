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
local Policies = require(script.Parent.Parent.Policies.Policies)
local Menu = require(script.Parent.Parent.Menu.Menu)
local Stats = require(script.Parent.Parent.Stats.Stats)

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
		trainingQueue = {},
		-- New state for UI
		showMenuModal = false,
		showStatsModal = false,
		showPoliciesModal = false,
		selectedCategory = "Castle", -- Castle, Military, Housing, Food, Industry
		armySize = 0,
		honor = 0,
		glory = 0,
		population = 0,
		happiness = 50, -- 0-100, affects revolt meter
		isDeleteMode = false, -- Delete mode for removing buildings/units
	})

	-- Get game event reference
	local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
	self.gameEvent = RemoteEvents:WaitForChild("GameEvent")

	self.connection = self.gameEvent.OnClientEvent:Connect(function(action, data)
		if action == "GameStarted" and data.resources then
			HUDDebug:info("Received resources", { resources = data.resources })
			self:setState({ resources = data.resources })
		elseif action == "UpdateResources" and data.resources then
			HUDDebug:info("Resources updated", { resources = data.resources })
			self:setState({ resources = data.resources })
		elseif action == "StartPlacement" and typeof(data) == "string" then
			HUDDebug:info("Server approved placement", { buildingType = data })
		elseif action == "TrainingQueueUpdate" then
			-- Update training queue display
			if data.buildingId and data.queue then
				HUDDebug:info("Training queue updated", {
					buildingId = data.buildingId,
					queueLength = #data.queue,
				})
				self:setState({ trainingQueue = data.queue })
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
				HUDDebug:warn(`VIKING RAID #${data.raidNumber}! {data.vikingCount} Vikings are attacking!`)
			end
		end
	end)

	-- Listen for selection changes
	task.spawn(function()
		local ClientScripts = player:WaitForChild("PlayerScripts"):WaitForChild("Client")
		local SelectionManager = require(ClientScripts.Selection.SelectionManager)

		SelectionManager.SelectionChanged:Connect(function(selectedUnits)
			self:setState({ selectedUnits = selectedUnits })
		end)
	end)

	-- Listen for building clicks
	self:setupBuildingSelection()

	-- Request queue updates periodically if a building is selected
	task.spawn(function()
		while true do
			task.wait(0.5)
			if self.state.selectedTrainingBuilding then
				self.gameEvent:FireServer("GetTrainingQueue", {
					buildingId = self.state.selectedTrainingBuilding.Name,
				})
			end
		end
	end)
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
									trainingQueue = {},
								})

								-- Request current queue
								self.gameEvent:FireServer("GetTrainingQueue", {
									buildingId = building.Name,
								})
							else
								HUDDebug:info("Building cannot train units")
							end
						end
					else
						HUDDebug:warn("Building check failed", {
							hasBuildingType = buildingType ~= nil,
							ownerMatch = owner == player.UserId,
						})
					end
				else
					HUDDebug:info("No building found")
				end
			else
				HUDDebug:info("Raycast hit nothing")
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

-- Helper function to create category buttons for bottom bar (icon only)
function HUD:createCategoryButton(category: string, icon: string)
	local isSelected = self.state.selectedCategory == category

	-- Set layout order based on category
	local layoutOrder = 1
	if category == "Castle" then
		layoutOrder = 1
	elseif category == "Military" then
		layoutOrder = 2
	elseif category == "Housing" then
		layoutOrder = 3
	elseif category == "Food" then
		layoutOrder = 4
	elseif category == "Industry" then
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
			self:setState({ selectedCategory = category })
		end,
	})
end

function HUD:render()
	HUDDebug:info("Rendering", { resources = self.state.resources })

	local hasUnitsSelected = #self.state.selectedUnits > 0
	local hasTrainingBuildingSelected = self.state.selectedTrainingBuilding ~= nil
	local showBuildingsInContent = not hasUnitsSelected and not hasTrainingBuildingSelected

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
					self:setState({ showStatsModal = not self.state.showStatsModal })
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
				BackgroundColor3 = UIConfig.HUD.MinimapBackground,
				BorderColor3 = UIConfig.HUD.MinimapBorder,
				BorderSizePixel = 1,
			}, {
				Label = React.createElement("TextLabel", {
					Size = UDim2.fromScale(1, 1),
					BackgroundTransparency = 1,
					Text = "MINIMAP",
					Font = Enum.Font.GothamBold,
					TextSize = 16,
					TextColor3 = UIConfig.HUD.PanelTextColor,
				}),
			}),

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

				-- Castle button (🏰)
				CastleButton = self:createCategoryButton("Castle", "🏰"),
				-- Military button (⚔️)
				MilitaryButton = self:createCategoryButton("Military", "⚔️"),
				-- Housing button (🏠)
				HousingButton = self:createCategoryButton("Housing", "🏠"),
				-- Food button (🌾)
				FoodButton = self:createCategoryButton("Food", "🌾"),
				-- Industry button (🔨)
				IndustryButton = self:createCategoryButton("Industry", "🔨"),
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
				-- Content priority: Training Panel > Unit Selection > Building Menu
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
						self:setState({ selectedTrainingBuilding = nil })
					end,
				}) or hasUnitsSelected and React.createElement(UnitSelectionPanel, {
					selectedUnits = self.state.selectedUnits,
					onFormationSelected = function(formationType)
						HUDDebug:info(`Formation selected: {formationType}`)
					end,
				}) or React.createElement(BuildingMenu, {
					resources = self.state.resources,
					selectedCategory = self.state.selectedCategory,
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

		-- Happiness/Revolt Meter (right side, above bottom bar)
		HappinessMeter = React.createElement("Frame", {
			Name = "HappinessMeter",
			Size = UDim2.new(0, UIConfig.HUD.MeterWidth, 0, UIConfig.HUD.MeterHeight),
			Position = UDim2.new(
				1,
				-(UIConfig.HUD.MeterWidth + 10),
				1,
				-(UIConfig.HUD.BottomBarHeight + UIConfig.HUD.MeterHeight + 10)
			),
			BackgroundColor3 = UIConfig.HUD.MeterBackground,
			BorderSizePixel = 1,
			BorderColor3 = UIConfig.HUD.MeterBorder,
			ZIndex = 9,
		}, {
			-- Label
			Label = React.createElement("TextLabel", {
				Size = UDim2.new(1, 0, 0, 25),
				BackgroundTransparency = 1,
				Text = "😊/😡",
				Font = Enum.Font.GothamBold,
				TextSize = 16,
				TextColor3 = UIConfig.HUD.PanelTextColor,
			}),

			-- Happiness bar (green, fills from bottom)
			HappyBar = React.createElement("Frame", {
				Size = UDim2.new(1, -10, self.state.happiness / 100, -30),
				Position = UDim2.new(0, 5, 1, -5),
				AnchorPoint = Vector2.new(0, 1),
				BackgroundColor3 = UIConfig.HUD.MeterHappyColor,
				BorderSizePixel = 0,
			}),

			-- Revolt indicator (red, fills from top when happiness < 50)
			RevoltBar = React.createElement("Frame", {
				Size = UDim2.new(1, -10, math.max(0, (50 - self.state.happiness) / 100), -30),
				Position = UDim2.new(0, 5, 0, 30),
				BackgroundColor3 = UIConfig.HUD.MeterRevoltColor,
				BorderSizePixel = 0,
			}),
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
		}) or nil,

		-- Stats Modal (conditionally rendered)
		StatsModal = self.state.showStatsModal and React.createElement(Stats, {
			visible = self.state.showStatsModal,
			onClose = function()
				self:setState({ showStatsModal = false })
			end,
			-- Pass stats data
			population = self.state.population,
			armySize = self.state.armySize,
			honor = self.state.honor,
			glory = self.state.glory,
			happiness = self.state.happiness,
		}) or nil,
	})
end

return HUD
