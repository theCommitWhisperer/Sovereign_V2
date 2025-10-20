local React = require(game.ReplicatedStorage.Packages.react)
local GameData = require(game.ReplicatedStorage.Shared.GameData)

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

	-- Create unit buttons
	local unitButtons = {}
	for i, unitType in trainableUnits do
		local unitInfo = GameData.Units[unitType]
		if unitInfo then
			-- Format cost display
			local costText = ""
			local costParts = {}
			for resource, amount in unitInfo.cost do
				table.insert(costParts, `{resource}: {amount}`)
			end
			costText = table.concat(costParts, ", ")

			unitButtons[`Unit{i}`] = React.createElement("TextButton", {
				Size = UDim2.new(1, -10, 0, 60),
				Position = UDim2.new(0, 5, 0, (i - 1) * 65 + 40),
				BackgroundColor3 = Color3.fromRGB(60, 60, 65),
				BorderColor3 = Color3.fromRGB(100, 100, 100),
				BorderSizePixel = 2,
				Text = "",
				[React.Event.Activated] = function()
					if self.props.onTrainUnit then
						self.props.onTrainUnit(unitType)
					end
				end,
			}, {
				Name = React.createElement("TextLabel", {
					Size = UDim2.new(1, -10, 0, 20),
					Position = UDim2.new(0, 5, 0, 5),
					BackgroundTransparency = 1,
					Text = unitType,
					Font = Enum.Font.GothamBold,
					TextSize = 16,
					TextColor3 = Color3.fromRGB(255, 255, 255),
					TextXAlignment = Enum.TextXAlignment.Left,
				}),

				Cost = React.createElement("TextLabel", {
					Size = UDim2.new(1, -10, 0, 15),
					Position = UDim2.new(0, 5, 0, 25),
					BackgroundTransparency = 1,
					Text = costText,
					Font = Enum.Font.Gotham,
					TextSize = 12,
					TextColor3 = Color3.fromRGB(200, 200, 200),
					TextXAlignment = Enum.TextXAlignment.Left,
				}),

				TrainingTime = React.createElement("TextLabel", {
					Size = UDim2.new(1, -10, 0, 15),
					Position = UDim2.new(0, 5, 0, 40),
					BackgroundTransparency = 1,
					Text = `Time: {unitInfo.training_time_seconds or 0}s`,
					Font = Enum.Font.Gotham,
					TextSize = 12,
					TextColor3 = Color3.fromRGB(150, 150, 150),
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
			})
		end
	end

	-- Create queue display
	local queueDisplay = {}
	if #queue > 0 then
		for i, entry in queue do
			local progress = 1 - (entry.timeRemaining / entry.totalTime)

			queueDisplay[`QueueEntry{i}`] = React.createElement("Frame", {
				Size = UDim2.new(1, -10, 0, 30),
				Position = UDim2.new(0, 5, 0, (i - 1) * 35),
				BackgroundColor3 = Color3.fromRGB(50, 50, 55),
				BorderSizePixel = 1,
				BorderColor3 = Color3.fromRGB(80, 80, 80),
			}, {
				UnitName = React.createElement("TextLabel", {
					Size = UDim2.new(0.6, 0, 1, 0),
					BackgroundTransparency = 1,
					Text = entry.unitType,
					Font = Enum.Font.Gotham,
					TextSize = 14,
					TextColor3 = Color3.fromRGB(255, 255, 255),
					TextXAlignment = Enum.TextXAlignment.Left,
					TextTruncate = Enum.TextTruncate.AtEnd,
				}, {
					Padding = React.createElement("UIPadding", {
						PaddingLeft = UDim.new(0, 5),
					}),
				}),

				TimeRemaining = React.createElement("TextLabel", {
					Size = UDim2.new(0.4, 0, 1, 0),
					Position = UDim2.new(0.6, 0, 0, 0),
					BackgroundTransparency = 1,
					Text = `{math.ceil(entry.timeRemaining)}s`,
					Font = Enum.Font.Gotham,
					TextSize = 12,
					TextColor3 = Color3.fromRGB(200, 200, 200),
					TextXAlignment = Enum.TextXAlignment.Right,
				}, {
					Padding = React.createElement("UIPadding", {
						PaddingRight = UDim.new(0, 5),
					}),
				}),

				ProgressBar = React.createElement("Frame", {
					Size = UDim2.new(progress, 0, 0, 3),
					Position = UDim2.new(0, 0, 1, -3),
					BackgroundColor3 = Color3.fromRGB(0, 200, 0),
					BorderSizePixel = 0,
				}),
			})
		end
	end

	return React.createElement("Frame", {
		Name = "TrainingPanel",
		Size = UDim2.new(0, 300, 0, 400),
		Position = UDim2.new(0, 10, 0.5, -200),
		BackgroundColor3 = Color3.fromRGB(40, 40, 45),
		BorderSizePixel = 2,
		BorderColor3 = Color3.fromRGB(100, 100, 100),
	}, {
		Padding = React.createElement("UIPadding", {
			PaddingTop = UDim.new(0, 8),
			PaddingBottom = UDim.new(0, 8),
			PaddingLeft = UDim.new(0, 8),
			PaddingRight = UDim.new(0, 8),
		}),

		Header = React.createElement("TextLabel", {
			Size = UDim2.new(1, 0, 0, 25),
			BackgroundTransparency = 1,
			Text = `{buildingType} - Training`,
			Font = Enum.Font.GothamBold,
			TextSize = 16,
			TextColor3 = Color3.fromRGB(255, 255, 255),
			TextXAlignment = Enum.TextXAlignment.Left,
		}),

		UnitsSection = React.createElement("ScrollingFrame", {
			Size = UDim2.new(1, 0, 0, 200),
			Position = UDim2.new(0, 0, 0, 30),
			BackgroundColor3 = Color3.fromRGB(30, 30, 35),
			BorderSizePixel = 1,
			BorderColor3 = Color3.fromRGB(60, 60, 65),
			ScrollBarThickness = 6,
			CanvasSize = UDim2.new(0, 0, 0, #trainableUnits * 65 + 10),
		}, unitButtons),

		QueueHeader = React.createElement("TextLabel", {
			Size = UDim2.new(1, 0, 0, 20),
			Position = UDim2.new(0, 0, 0, 240),
			BackgroundTransparency = 1,
			Text = `Training Queue ({#queue})`,
			Font = Enum.Font.GothamBold,
			TextSize = 14,
			TextColor3 = Color3.fromRGB(255, 255, 255),
			TextXAlignment = Enum.TextXAlignment.Left,
		}),

		QueueSection = React.createElement("ScrollingFrame", {
			Size = UDim2.new(1, 0, 1, -270),
			Position = UDim2.new(0, 0, 0, 265),
			BackgroundColor3 = Color3.fromRGB(30, 30, 35),
			BorderSizePixel = 1,
			BorderColor3 = Color3.fromRGB(60, 60, 65),
			ScrollBarThickness = 6,
			CanvasSize = UDim2.new(0, 0, 0, #queue * 35 + 10),
		}, queueDisplay),
	})
end

return TrainingPanel
