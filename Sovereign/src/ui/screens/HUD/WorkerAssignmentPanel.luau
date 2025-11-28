--!strict
-- WorkerAssignmentPanel: Shows information about workers assigned to a production building

local React = require(game.ReplicatedStorage.Packages.react)
local GameData = require(game.ReplicatedStorage.Shared.GameData)
local UIConfig = require(script.Parent.Parent.Parent.UIConfig)

local WorkerAssignmentPanel = React.Component:extend("WorkerAssignmentPanel")

function WorkerAssignmentPanel:init()
	self:setState({
		assignedWorkers = {},
	})

	-- Poll for assigned workers
	task.spawn(function()
		while true do
			task.wait(0.5)
			self:updateAssignedWorkers()
		end
	end)
end

function WorkerAssignmentPanel:updateAssignedWorkers()
	local selectedBuilding = self.props.selectedBuilding
	if not selectedBuilding or not selectedBuilding.Parent then
		return
	end

	-- Find all units in workspace
	local unitsFolder = game.Workspace:FindFirstChild("Units")
	if not unitsFolder then
		return
	end

	local assignedWorkers = {}
	for _, unit in unitsFolder:GetChildren() do
		if unit:IsA("Model") then
			local assignedTo = unit:GetAttribute("AssignedTo")
			local isWorking = unit:GetAttribute("IsWorking")
			local buildingType = selectedBuilding:GetAttribute("BuildingType")

			-- Check if this worker is assigned to this type of building
			if isWorking and assignedTo == buildingType then
				local resourcesCarrying = unit:GetAttribute("ResourcesCarrying") or 0
				local resourceType = unit:GetAttribute("ResourceType")
				local unitType = unit:GetAttribute("UnitType") or "Peasant"

				table.insert(assignedWorkers, {
					name = unit.Name,
					unitType = unitType,
					resourcesCarrying = resourcesCarrying,
					resourceType = resourceType,
				})
			end
		end
	end

	self:setState({
		assignedWorkers = assignedWorkers,
	})
end

function WorkerAssignmentPanel:render()
	local selectedBuilding = self.props.selectedBuilding

	if not selectedBuilding then
		return nil
	end

	local buildingType = selectedBuilding:GetAttribute("BuildingType")
	if not buildingType then
		return nil
	end

	local buildingInfo = GameData.Buildings[buildingType]
	if not buildingInfo then
		return nil
	end

	-- Only show for production buildings (not training buildings)
	if buildingInfo.can_train_units then
		return nil
	end

	local assignedWorkers = self.state.assignedWorkers or {}
	local resourceType = buildingInfo.produces_resource or "Resources"

	-- Create worker list items
	local workerItems = {}
	workerItems.Layout = React.createElement("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		Padding = UDim.new(0, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})

	if #assignedWorkers > 0 then
		for i, worker in assignedWorkers do
			local statusText = ""
			if worker.resourcesCarrying > 0 and worker.resourceType then
				statusText = `Carrying {worker.resourcesCarrying} {worker.resourceType}`
			else
				statusText = "Gathering..."
			end

			workerItems[`Worker{i}`] = React.createElement("Frame", {
				Size = UDim2.new(1, 0, 0, 35),
				LayoutOrder = i,
				BackgroundColor3 = UIConfig.HUD.TrainingQueueBackground,
				BorderSizePixel = 1,
				BorderColor3 = UIConfig.HUD.TrainingQueueBorder,
			}, {
				WorkerIcon = React.createElement("TextLabel", {
					Size = UDim2.new(0, 30, 1, 0),
					Position = UDim2.new(0, 3, 0, 0),
					BackgroundTransparency = 1,
					Text = "👷",
					Font = Enum.Font.GothamBold,
					TextSize = 18,
					TextColor3 = UIConfig.HUD.PanelTextColor,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),

				WorkerName = React.createElement("TextLabel", {
					Size = UDim2.new(0.5, -35, 0, 16),
					Position = UDim2.new(0, 35, 0, 2),
					BackgroundTransparency = 1,
					Text = worker.unitType,
					Font = Enum.Font.GothamBold,
					TextSize = 12,
					TextColor3 = UIConfig.HUD.PanelHeaderColor,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextTruncate = Enum.TextTruncate.AtEnd,
				}),

				WorkerStatus = React.createElement("TextLabel", {
					Size = UDim2.new(1, -35, 0, 14),
					Position = UDim2.new(0, 35, 0, 18),
					BackgroundTransparency = 1,
					Text = statusText,
					Font = Enum.Font.Gotham,
					TextSize = 10,
					TextColor3 = UIConfig.HUD.StatLabelColor,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextTruncate = Enum.TextTruncate.AtEnd,
				}),
			})
		end
	else
		workerItems.NoWorkers = React.createElement("TextLabel", {
			Size = UDim2.new(1, -10, 0, 30),
			Position = UDim2.new(0, 5, 0, 5),
			BackgroundTransparency = 1,
			Text = "No workers assigned\n\nRight-click peasants to assign them",
			Font = Enum.Font.Gotham,
			TextSize = 11,
			TextColor3 = UIConfig.HUD.StatLabelColor,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Top,
		})
	end

	-- Building storage info
	local storedAmount = selectedBuilding:GetAttribute(`Storage_{resourceType}`) or 0
	local maxStorage = buildingInfo.storage_capacity or 0

	return React.createElement("Frame", {
		Name = "WorkerAssignmentPanel",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
	}, {
		-- Header
		Header = React.createElement("Frame", {
			Size = UDim2.new(1, 0, 0, 35),
			BackgroundColor3 = UIConfig.HUD.TrainingQueueBackground,
			BorderSizePixel = 1,
			BorderColor3 = UIConfig.HUD.TrainingQueueBorder,
		}, {
			Title = React.createElement("TextLabel", {
				Size = UDim2.new(1, -10, 0, 18),
				Position = UDim2.new(0, 5, 0, 2),
				BackgroundTransparency = 1,
				Text = `🏭 {buildingType}`,
				Font = Enum.Font.GothamBold,
				TextSize = 14,
				TextColor3 = UIConfig.HUD.PanelHeaderColor,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),

			Storage = React.createElement("TextLabel", {
				Size = UDim2.new(1, -10, 0, 14),
				Position = UDim2.new(0, 5, 0, 20),
				BackgroundTransparency = 1,
				Text = `Storage: {storedAmount}/{maxStorage} {resourceType}`,
				Font = Enum.Font.Gotham,
				TextSize = 11,
				TextColor3 = UIConfig.HUD.StatLabelColor,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),

			CloseButton = React.createElement("TextButton", {
				Size = UDim2.new(0, 28, 0, 28),
				Position = UDim2.new(1, -31, 0, 3),
				BackgroundColor3 = UIConfig.HUD.TrainingUnitButtonBackground,
				BorderSizePixel = 1,
				BorderColor3 = UIConfig.HUD.TrainingUnitButtonBorder,
				Text = "X",
				Font = Enum.Font.GothamBold,
				TextSize = 16,
				TextColor3 = UIConfig.HUD.PanelTextColor,
				[React.Event.Activated] = function()
					if self.props.onClose then
						self.props.onClose()
					end
				end,
			}),
		}),

		-- Workers header
		WorkersHeader = React.createElement("Frame", {
			Size = UDim2.new(1, 0, 0, 25),
			Position = UDim2.new(0, 0, 0, 40),
			BackgroundColor3 = UIConfig.HUD.TrainingQueueBackground,
			BorderSizePixel = 1,
			BorderColor3 = UIConfig.HUD.TrainingQueueBorder,
		}, {
			Label = React.createElement("TextLabel", {
				Size = UDim2.new(1, -10, 1, 0),
				Position = UDim2.new(0, 5, 0, 0),
				BackgroundTransparency = 1,
				Text = `👥 Assigned Workers ({#assignedWorkers})`,
				Font = Enum.Font.GothamBold,
				TextSize = 12,
				TextColor3 = UIConfig.HUD.PanelHeaderColor,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
		}),

		-- Workers list (scrollable)
		WorkersSection = React.createElement("ScrollingFrame", {
			Size = UDim2.new(1, 0, 1, -70),
			Position = UDim2.new(0, 0, 0, 65),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 4,
			ScrollBarImageColor3 = UIConfig.HUD.TrainingProgressBar,
			CanvasSize = UDim2.new(0, 0, 0, math.max(100, #assignedWorkers * 39 + 4)),
		}, workerItems),
	})
end

return WorkerAssignmentPanel
