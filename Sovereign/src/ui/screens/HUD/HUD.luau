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
		showExpandedMeters = false, -- Show expanded meter panel
		commandText = "", -- For admin command input
		economySnapshot = nil, -- Economy dashboard data
		stats = nil, -- Stats for the stats modal
		selectedFormation = "Line", -- Default formation type
	})

	-- Get game event reference
	local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
	self.gameEvent = RemoteEvents:WaitForChild("GameEvent")
	self.getStatsEvent = RemoteEvents:WaitForChild("GetStats")

	self.statsConnection = self.getStatsEvent.OnClientEvent:Connect(function(stats)
		self:setState({ stats = stats })
	end)

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

		-- Store SelectionManager reference for later use
		self.selectionManager = SelectionManager

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
					self.getStatsEvent:FireServer("GetStats")
					self:setState({ showStatsModal = not self.state.showStatsModal })
				end,
			}),

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

							-- Send formation command to server
							self.gameEvent:FireServer("MoveUnitsInFormation", {
								unitIds = unitIds,
								targetPosition = avgPosition,
								formationType = formationType,
							})

							HUDDebug:info(`Arranging {#unitIds} units in {formationType} formation`)
						end
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
	})
end

return HUD
