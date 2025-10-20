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
				print(`⚠️ VIKING RAID #{data.raidNumber}! {data.vikingCount} Vikings are attacking!`)
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
						-- Check if building can train units
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

function HUD:render()
	HUDDebug:info("Rendering", { resources = self.state.resources })

	return React.createElement("ScreenGui", {
		Name = "HUDGui",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		IgnoreGuiInset = true,
	}, {
		-- Top Bar for Resources
		TopBar = React.createElement("Frame", {
			Name = "TopBar",
			Size = UDim2.new(1, 0, 0, 60),
			Position = UDim2.fromScale(0, 0),
			BackgroundColor3 = Color3.fromRGB(40, 40, 45),
			BorderSizePixel = 0,
		}, {
			ResourceDisplay = React.createElement(ResourceDisplay, {
				resources = self.state.resources,
			}),
		}),

		-- Bottom Bar with Building Menu
		BottomBar = React.createElement("Frame", {
			Name = "BottomBar",
			Size = UDim2.new(1, 0, 0, 200),
			Position = UDim2.new(0, 0, 1, 0),
			AnchorPoint = Vector2.new(0, 1),
			BackgroundColor3 = Color3.fromRGB(40, 40, 45),
			BorderSizePixel = 0,
		}, {
			Padding = React.createElement("UIPadding", {
				PaddingTop = UDim.new(0, 10),
				PaddingBottom = UDim.new(0, 10),
				PaddingLeft = UDim.new(0, 10),
				PaddingRight = UDim.new(0, 10),
			}),

			BuildingMenu = React.createElement(BuildingMenu, {
				resources = self.state.resources,
				onBuildingSelected = function(buildingName)
					print("[HUD] Building selected:", buildingName)
					self:setState({
						isPlacingBuilding = true,
						selectedBuilding = buildingName,
					})

					-- Request placement from server
					self.gameEvent:FireServer("StartPlacement", buildingName)
				end,
			}),
		}),

		-- Selection Panel (bottom left)
		SelectionPanel = React.createElement(SelectionPanel, {
			selectedUnits = self.state.selectedUnits,
		}),

		-- Training Panel (left side)
		TrainingPanel = React.createElement(TrainingPanel, {
			selectedBuilding = self.state.selectedTrainingBuilding,
			queue = self.state.trainingQueue,
			onTrainUnit = function(unitType)
				print(`[HUD] Training unit: {unitType}`)
				if self.state.selectedTrainingBuilding then
					self.gameEvent:FireServer("StartTraining", {
						buildingId = self.state.selectedTrainingBuilding.Name,
						unitType = unitType,
					})
				end
			end,
		}),

		-- Mini-map Placeholder (bottom right)
		MiniMapFrame = React.createElement("Frame", {
			Name = "MiniMapFrame",
			Size = UDim2.new(0, 200, 0, 200),
			Position = UDim2.new(1, -10, 1, -210),
			AnchorPoint = Vector2.new(1, 1),
			BackgroundColor3 = Color3.fromRGB(30, 30, 35),
			BorderColor3 = Color3.fromRGB(100, 100, 100),
			BorderSizePixel = 2,
		}, {
			Label = React.createElement("TextLabel", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Text = "Mini Map\n(Coming Soon)",
				Font = Enum.Font.Gotham,
				TextSize = 16,
				TextColor3 = Color3.fromRGB(150, 150, 150),
			}),
		}),
	})
end

return HUD
