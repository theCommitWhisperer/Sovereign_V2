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
			-- Match by the unique building INSTANCE id, not the building type, so
			-- the panel counts workers for THIS building only.
			local assignedBuildingId = unit:GetAttribute("AssignedBuildingId")

			if unit:GetAttribute("IsWorking") and assignedBuildingId == selectedBuilding.Name then
				table.insert(assignedWorkers, {
					name = unit.Name,
					unitType = unit:GetAttribute("UnitType") or "Peasant",
					resourcesCarrying = unit:GetAttribute("ResourcesCarrying") or 0,
					resourceType = unit:GetAttribute("ResourceType"),
					workerState = unit:GetAttribute("WorkerState") or "Working",
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
	local capacity = selectedBuilding:GetAttribute("WorkerSlots") or buildingInfo.worker_slots or 1
	-- Total employed = physical operator + virtual workers (server-published).
	-- Falls back to the visible list length before the attribute is set.
	local workerCount = selectedBuilding:GetAttribute("WorkerCount") or #assignedWorkers

	-- Create worker list items
	local workerItems = {}
	workerItems.Layout = React.createElement("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		Padding = UDim.new(0, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})

	-- Friendly labels for the live WorkerState attribute.
	local STATE_LABELS = {
		Walking = "🚶 Walking to work",
		Working = "⚒️ Working",
		Gathering = "🪓 Gathering",
		Returning = "📦 Hauling back",
	}

	if #assignedWorkers > 0 then
		for i, worker in assignedWorkers do
			local statusText = STATE_LABELS[worker.workerState] or "⚒️ Working"
			if worker.resourcesCarrying > 0 and worker.resourceType then
				statusText = `{statusText} · {worker.resourcesCarrying} {worker.resourceType}`
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
			Text = "No workers assigned\n\nUse + to staff the nearest idle peasant",
			Font = Enum.Font.Gotham,
			TextSize = 11,
			TextColor3 = UIConfig.HUD.StatLabelColor,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Top,
		})
	end

	-- Building storage info (storage_capacity is a table keyed by resource type)
	local storedAmount = selectedBuilding:GetAttribute(`Storage_{resourceType}`) or 0
	local maxStorage = (buildingInfo.storage_capacity and buildingInfo.storage_capacity[resourceType]) or 0

	-- Live effective output estimate: output/tick × staffed workers ÷ interval.
	local producesResource = buildingInfo.produces_resource ~= nil
	local outputPer = buildingInfo.production_output or 1
	local interval = buildingInfo.production_time or (1 / (buildingInfo.production_rate or 1))
	local effectiveWorkers = math.min(workerCount, capacity)
	local ratePerSec = (interval > 0) and (outputPer * effectiveWorkers / interval) or 0
	local storageText = producesResource
			and `Storage: {storedAmount}/{maxStorage} {resourceType}  ·  ~{string.format("%.1f", ratePerSec)}/s`
		or `Workers: {workerCount}/{capacity}`

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
				Text = storageText,
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

		-- Workers header + add/remove controls
		WorkersHeader = React.createElement("Frame", {
			Size = UDim2.new(1, 0, 0, 25),
			Position = UDim2.new(0, 0, 0, 40),
			BackgroundColor3 = UIConfig.HUD.TrainingQueueBackground,
			BorderSizePixel = 1,
			BorderColor3 = UIConfig.HUD.TrainingQueueBorder,
		}, {
			Label = React.createElement("TextLabel", {
				Size = UDim2.new(1, -70, 1, 0),
				Position = UDim2.new(0, 5, 0, 0),
				BackgroundTransparency = 1,
				Text = `👥 Workers ({workerCount}/{capacity})`,
				Font = Enum.Font.GothamBold,
				TextSize = 12,
				TextColor3 = UIConfig.HUD.PanelHeaderColor,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),

			RemoveButton = React.createElement("TextButton", {
				Size = UDim2.new(0, 26, 0, 21),
				Position = UDim2.new(1, -60, 0, 2),
				BackgroundColor3 = UIConfig.HUD.TrainingUnitButtonBackground,
				BorderSizePixel = 1,
				BorderColor3 = UIConfig.HUD.TrainingUnitButtonBorder,
				Text = "−",
				Font = Enum.Font.GothamBold,
				TextSize = 18,
				TextColor3 = UIConfig.HUD.PanelTextColor,
				[React.Event.Activated] = function()
					if self.props.onRemoveWorker then
						self.props.onRemoveWorker()
					end
				end,
			}),

			AddButton = React.createElement("TextButton", {
				Size = UDim2.new(0, 26, 0, 21),
				Position = UDim2.new(1, -30, 0, 2),
				BackgroundColor3 = UIConfig.HUD.TrainingUnitButtonBackground,
				BorderSizePixel = 1,
				BorderColor3 = UIConfig.HUD.TrainingUnitButtonBorder,
				Text = "+",
				Font = Enum.Font.GothamBold,
				TextSize = 18,
				TextColor3 = UIConfig.HUD.PanelTextColor,
				[React.Event.Activated] = function()
					if self.props.onAddWorker then
						self.props.onAddWorker()
					end
				end,
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
