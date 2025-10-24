local React = require(game.ReplicatedStorage.Packages.react)
local GameData = require(game.ReplicatedStorage.Shared.GameData)
local UIConfig = require(script.Parent.Parent.Parent.UIConfig)

local TrainingPanel = React.Component:extend("TrainingPanel")

function TrainingPanel:init()
	self:setState({
		queue = {},
	})
end

function TrainingPanel:render()
	local selectedBuilding = self.props.selectedBuilding

	if not selectedBuilding then
		return nil
	end

	local buildingType = selectedBuilding:GetAttribute("BuildingType")
	if not buildingType then
		return nil
	end

	local buildingInfo = GameData.Buildings[buildingType]
	if not buildingInfo or not buildingInfo.can_train_units then
		return nil
	end

	-- Get trainable units
	local trainableUnits = buildingInfo.can_train_units or {}
	local queue = self.props.queue or {}

	-- Create unit buttons (horizontal grid layout)
	local unitButtons = {}
	unitButtons.Layout = React.createElement("UIGridLayout", {
		CellSize = UDim2.new(0, 100, 0, 80),
		CellPadding = UDim2.new(0, 8, 0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})

	for i, unitType in trainableUnits do
		local unitInfo = GameData.Units[unitType]
		if unitInfo then
			-- Format cost display
			local costParts = {}
			for resource, amount in unitInfo.cost do
				table.insert(costParts, `{resource}: {amount}`)
			end
			local costText = table.concat(costParts, "\n")

			unitButtons[`Unit{i}`] = React.createElement("TextButton", {
				LayoutOrder = i,
				BackgroundColor3 = UIConfig.HUD.TrainingUnitButtonBackground,
				BorderColor3 = UIConfig.HUD.TrainingUnitButtonBorder,
				BorderSizePixel = 2,
				Text = "",
				[React.Event.Activated] = function()
					if self.props.onTrainUnit then
						self.props.onTrainUnit(unitType)
					end
				end,
			}, {
				Name = React.createElement("TextLabel", {
					Size = UDim2.new(1, -4, 0, 20),
					Position = UDim2.new(0, 2, 0, 2),
					BackgroundTransparency = 1,
					Text = unitType,
					Font = Enum.Font.GothamBold,
					TextSize = 13,
					TextColor3 = UIConfig.HUD.PanelHeaderColor,
					TextXAlignment = Enum.TextXAlignment.Center,
					TextScaled = true,
				}),

				Cost = React.createElement("TextLabel", {
					Size = UDim2.new(1, -4, 0, 30),
					Position = UDim2.new(0, 2, 0, 24),
					BackgroundTransparency = 1,
					Text = costText,
					Font = Enum.Font.Gotham,
					TextSize = 10,
					TextColor3 = UIConfig.HUD.PanelTextColor,
					TextXAlignment = Enum.TextXAlignment.Center,
				}),

				TrainingTime = React.createElement("TextLabel", {
					Size = UDim2.new(1, -4, 0, 15),
					Position = UDim2.new(0, 2, 1, -17),
					BackgroundTransparency = 1,
					Text = `{unitInfo.training_time_seconds or 0}s`,
					Font = Enum.Font.Gotham,
					TextSize = 11,
					TextColor3 = UIConfig.HUD.StatLabelColor,
					TextXAlignment = Enum.TextXAlignment.Center,
				}),
			})
		end
	end

	-- Create queue display (compact list)
	local queueDisplay = {}
	queueDisplay.Layout = React.createElement("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		Padding = UDim.new(0, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})

	if #queue > 0 then
		for i, entry in queue do
			local progress = 1 - (entry.timeRemaining / entry.totalTime)

			queueDisplay[`QueueEntry{i}`] = React.createElement("Frame", {
				Size = UDim2.new(1, 0, 0, 25),
				LayoutOrder = i,
				BackgroundColor3 = UIConfig.HUD.TrainingQueueBackground,
				BorderSizePixel = 1,
				BorderColor3 = UIConfig.HUD.TrainingQueueBorder,
			}, {
				UnitName = React.createElement("TextLabel", {
					Size = UDim2.new(0.65, -5, 1, 0),
					Position = UDim2.new(0, 3, 0, 0),
					BackgroundTransparency = 1,
					Text = entry.unitType,
					Font = Enum.Font.Gotham,
					TextSize = 12,
					TextColor3 = UIConfig.HUD.PanelTextColor,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextTruncate = Enum.TextTruncate.AtEnd,
				}),

				TimeRemaining = React.createElement("TextLabel", {
					Size = UDim2.new(0.35, -3, 1, 0),
					Position = UDim2.new(0.65, 0, 0, 0),
					BackgroundTransparency = 1,
					Text = `{math.ceil(entry.timeRemaining)}s`,
					Font = Enum.Font.Gotham,
					TextSize = 11,
					TextColor3 = UIConfig.HUD.StatLabelColor,
					TextXAlignment = Enum.TextXAlignment.Right,
				}),

				ProgressBar = React.createElement("Frame", {
					Size = UDim2.new(progress, 0, 0, 2),
					Position = UDim2.new(0, 0, 1, -2),
					BackgroundColor3 = UIConfig.HUD.TrainingProgressBar,
					BorderSizePixel = 0,
				}),
			})
		end
	end

	-- Layout: Top section for units, bottom section for queue
	return React.createElement("Frame", {
		Name = "TrainingPanel",
		Size = UDim2.new(1, 0, 1, 0), -- Fill content area
		BackgroundTransparency = 1,
	}, {
		-- Header
		Header = React.createElement("Frame", {
			Size = UDim2.new(1, 0, 0, 30),
			BackgroundColor3 = UIConfig.HUD.TrainingQueueBackground,
			BorderSizePixel = 1,
			BorderColor3 = UIConfig.HUD.TrainingQueueBorder,
		}, {
			Title = React.createElement("TextLabel", {
				Size = UDim2.new(1, -10, 1, 0),
				Position = UDim2.new(0, 5, 0, 0),
				BackgroundTransparency = 1,
				Text = `⚔️ Training - {buildingType}`,
				Font = Enum.Font.GothamBold,
				TextSize = 14,
				TextColor3 = UIConfig.HUD.PanelHeaderColor,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),

			CloseButton = React.createElement("TextButton", {
				Size = UDim2.new(0, 25, 0, 25),
				Position = UDim2.new(1, -28, 0, 2.5),
				BackgroundColor3 = UIConfig.HUD.TrainingUnitButtonBackground,
				BorderSizePixel = 1,
				BorderColor3 = UIConfig.HUD.TrainingUnitButtonBorder,
				Text = "✕",
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

		-- Units section (scrollable grid)
		UnitsSection = React.createElement("ScrollingFrame", {
			Size = UDim2.new(1, 0, 0.6, -35),
			Position = UDim2.new(0, 0, 0, 35),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 4,
			ScrollBarImageColor3 = UIConfig.HUD.TrainingProgressBar,
			CanvasSize = UDim2.new(0, 0, 0, math.ceil(#trainableUnits / 4) * 88),
		}, unitButtons),

		-- Queue header
		QueueHeader = React.createElement("Frame", {
			Size = UDim2.new(1, 0, 0, 25),
			Position = UDim2.new(0, 0, 0.6, 0),
			BackgroundColor3 = UIConfig.HUD.TrainingQueueBackground,
			BorderSizePixel = 1,
			BorderColor3 = UIConfig.HUD.TrainingQueueBorder,
		}, {
			Label = React.createElement("TextLabel", {
				Size = UDim2.new(1, -10, 1, 0),
				Position = UDim2.new(0, 5, 0, 0),
				BackgroundTransparency = 1,
				Text = `📋 Training Queue ({#queue})`,
				Font = Enum.Font.GothamBold,
				TextSize = 12,
				TextColor3 = UIConfig.HUD.PanelHeaderColor,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
		}),

		-- Queue section (scrollable list)
		QueueSection = React.createElement("ScrollingFrame", {
			Size = UDim2.new(1, 0, 0.4, -30),
			Position = UDim2.new(0, 0, 0.6, 25),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 4,
			ScrollBarImageColor3 = UIConfig.HUD.TrainingProgressBar,
			CanvasSize = UDim2.new(0, 0, 0, #queue * 29 + 4),
		}, queueDisplay),
	})
end

return TrainingPanel
