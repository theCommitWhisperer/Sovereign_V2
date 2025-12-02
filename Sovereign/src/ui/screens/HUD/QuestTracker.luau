--!strict
-- QuestTracker: Side panel showing active quests with progress

local React = require(game.ReplicatedStorage.Packages.react)
local UIConfig = require(script.Parent.Parent.Parent.UIConfig)
local Panel = require(script.Parent.Parent.Parent.components.Panel)

local QuestTracker = React.Component:extend("QuestTracker")

function QuestTracker:init()
	self:setState({
		quests = {},
		collapsed = false,
	})
end

function QuestTracker:didMount()
	-- Request quest data from server
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
	local GameEvent = RemoteEvents:WaitForChild("GameEvent")

	GameEvent:FireServer("GetQuests")

	-- Listen for quest updates
	self.questConnection = GameEvent.OnClientEvent:Connect(function(action, data)
		if action == "QuestsData" then
			self:setState({
				quests = data.activeQuests or {},
			})
		elseif action == "QuestProgress" then
			-- Refresh quest data
			GameEvent:FireServer("GetQuests")
		elseif action == "QuestCompleted" then
			-- Refresh quest data
			GameEvent:FireServer("GetQuests")
		elseif action == "QuestUnlocked" then
			-- Refresh quest data
			GameEvent:FireServer("GetQuests")
		end
	end)
end

function QuestTracker:willUnmount()
	if self.questConnection then
		self.questConnection:Disconnect()
	end
end

function QuestTracker:render()
	local quests = self.state.quests or {}
	local collapsed = self.state.collapsed

	-- Calculate total height based on quests
	local questCount = 0
	for _ in pairs(quests) do
		questCount += 1
	end

	local headerHeight = 35
	local questHeight = 80
	local padding = 10
	local totalHeight = if collapsed then headerHeight else headerHeight + (questCount * questHeight) + padding

	-- Build quest elements
	local questElements = {}
	local index = 0

	for questId, quest in pairs(quests) do
		if quest.isActive and not quest.isCompleted then
			index += 1

			-- Calculate overall progress
			local totalObjectives = #quest.objectives
			local completedObjectives = 0
			for _, objective in ipairs(quest.objectives) do
				if objective.current >= objective.required then
					completedObjectives += 1
				end
			end
			local overallProgress = completedObjectives / totalObjectives

			-- Build objective text
			local objectiveTexts = {}
			for objIndex, objective in ipairs(quest.objectives) do
				local isDone = objective.current >= objective.required
				local checkmark = isDone and "✅" or "⬜"
				table.insert(
					objectiveTexts,
					string.format("%s %s (%d/%d)", checkmark, objective.description, objective.current, objective.required)
				)
			end

			questElements["Quest_" .. questId] = React.createElement("Frame", {
				Size = UDim2.new(1, 0, 0, questHeight),
				Position = UDim2.fromOffset(0, (index - 1) * questHeight),
				BackgroundColor3 = UIConfig.HUD.DarkWood,
				BorderSizePixel = 1,
				BorderColor3 = UIConfig.HUD.StrokeColor,
			}, {
				QuestName = React.createElement("TextLabel", {
					Size = UDim2.new(1, -10, 0, 18),
					Position = UDim2.fromOffset(5, 3),
					BackgroundTransparency = 1,
					Text = quest.name,
					TextColor3 = UIConfig.HUD.AccentGold,
					TextSize = 13,
					Font = UIConfig.Font.Title,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextTruncate = Enum.TextTruncate.AtEnd,
				}),

				ProgressBar = React.createElement("Frame", {
					Size = UDim2.new(1, -10, 0, 4),
					Position = UDim2.fromOffset(5, 23),
					BackgroundColor3 = Color3.fromRGB(50, 50, 50),
					BorderSizePixel = 0,
				}, {
					Fill = React.createElement("Frame", {
						Size = UDim2.new(overallProgress, 0, 1, 0),
						BackgroundColor3 = UIConfig.HUD.AccentGold,
						BorderSizePixel = 0,
					}),
				}),

				Objectives = React.createElement("TextLabel", {
					Size = UDim2.new(1, -10, 0, 48),
					Position = UDim2.fromOffset(5, 30),
					BackgroundTransparency = 1,
					Text = table.concat(objectiveTexts, "\n"),
					TextColor3 = UIConfig.HUD.PanelTextColor,
					TextSize = 11,
					Font = UIConfig.Font.Default,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextWrapped = true,
				}),

				UIStroke = React.createElement("UIStroke", {
					Color = UIConfig.HUD.StrokeColor,
					Thickness = 1,
				}),
			})
		end
	end

	return React.createElement(Panel, {
		medieval = true,
		Size = UDim2.new(0, 280, 0, totalHeight),
		Position = UDim2.new(1, -290, 0, UIConfig.HUD.TopBarHeight + 10),
		BackgroundColor3 = UIConfig.HUD.PanelBackground,
	}, {
		Header = React.createElement("Frame", {
			Size = UDim2.new(1, 0, 0, headerHeight),
			BackgroundTransparency = 1,
		}, {
			Title = React.createElement("TextLabel", {
				Size = UDim2.new(1, -60, 1, 0),
				Position = UDim2.fromOffset(10, 0),
				BackgroundTransparency = 1,
				Text = "📜 Active Quests",
				TextColor3 = UIConfig.HUD.PanelHeaderColor,
				TextSize = 18,
				Font = UIConfig.Font.Title,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),

			ToggleButton = React.createElement("TextButton", {
				Size = UDim2.fromOffset(30, 30),
				Position = UDim2.new(1, -35, 0, 2),
				BackgroundColor3 = UIConfig.HUD.CategoryButtonBackground,
				BorderSizePixel = 1,
				BorderColor3 = UIConfig.HUD.StrokeColor,
				Text = collapsed and "▼" or "▲",
				TextColor3 = UIConfig.HUD.PanelTextColor,
				TextSize = 16,
				Font = UIConfig.Font.Default,
				[React.Event.Activated] = function()
					self:setState({ collapsed = not collapsed })
				end,
			}),

			QuestCount = not collapsed and React.createElement("TextLabel", {
				Size = UDim2.new(0, 40, 0, 18),
				Position = UDim2.new(1, -70, 0, 8),
				BackgroundTransparency = 1,
				Text = string.format("(%d)", questCount),
				TextColor3 = UIConfig.HUD.PanelTextColor,
				TextSize = 14,
				Font = UIConfig.Font.Default,
				TextXAlignment = Enum.TextXAlignment.Right,
			}) or nil,
		}),

		QuestsContainer = not collapsed and React.createElement("Frame", {
			Size = UDim2.new(1, -10, 1, -headerHeight - 5),
			Position = UDim2.fromOffset(5, headerHeight + 5),
			BackgroundTransparency = 1,
		}, questElements) or nil,

		NoQuestsLabel = (not collapsed and questCount == 0) and React.createElement("TextLabel", {
			Size = UDim2.new(1, -20, 0, 40),
			Position = UDim2.fromOffset(10, headerHeight + 10),
			BackgroundTransparency = 1,
			Text = "No active quests.\n\nComplete tasks to unlock more!",
			TextColor3 = UIConfig.HUD.PanelTextColor,
			TextSize = 12,
			Font = UIConfig.Font.Default,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Top,
		}) or nil,
	})
end

return QuestTracker
