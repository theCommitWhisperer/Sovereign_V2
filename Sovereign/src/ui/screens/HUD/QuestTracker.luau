--!strict
-- QuestTracker: Side panel showing active quests with progress.
-- Returns nil when there are zero active quests so no empty panel or stray brackets render.

local React = require(game.ReplicatedStorage.Packages.react)
local UIConfig = require(script.Parent.Parent.Parent.UIConfig)
local Theme = require(script.Parent.Parent.Parent.Theme)
local Panel = require(script.Parent.Parent.Parent.components.Panel)

local QuestTracker = React.Component:extend("QuestTracker")

function QuestTracker:init()
	self:setState({
		collapsed = true,
	})
end

function QuestTracker:render()
	local quests = self.props.quests or {}
	local collapsed = self.state.collapsed

	-- Count active, non-completed quests
	local questCount = 0
	local activeQuestsList = {}
	for questId, quest in pairs(quests) do
		if quest and quest.isActive and not quest.isCompleted then
			questCount += 1
			activeQuestsList[questId] = quest
		end
	end

	-- Return nil if zero active quests so no empty panel or stray brackets render!
	if questCount == 0 then
		return nil
	end

	local headerHeight = 35
	local questHeight = 80
	local padding = 10
	local totalHeight = if collapsed then headerHeight else headerHeight + (questCount * questHeight) + padding

	-- Build quest elements
	local questElements = {}
	local index = 0

	for questId, quest in pairs(activeQuestsList) do
		index += 1

		-- Calculate overall progress
		local totalObjectives = #quest.objectives
		local completedObjectives = 0
		for _, objective in ipairs(quest.objectives) do
			if objective.current >= objective.required then
				completedObjectives += 1
			end
		end
		local overallProgress = if totalObjectives > 0 then completedObjectives / totalObjectives else 0

		-- Build objective text
		local objectiveTexts = {}
		for _, objective in ipairs(quest.objectives) do
			local isDone = objective.current >= objective.required
			local checkmark = isDone and "✅" or "⬜"
			table.insert(
				objectiveTexts,
				string.format("%s %s (%d/%d)", checkmark, objective.description, objective.current, objective.required)
			)
		end

		questElements["Quest_" .. tostring(questId)] = React.createElement("Frame", {
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
				Text = quest.name or "Quest",
				TextColor3 = UIConfig.HUD.AccentGold,
				TextSize = Theme.TextSize.Body,
				FontFace = Theme.FontFace.Display,
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
				TextSize = Theme.TextSize.Caption,
				FontFace = Theme.FontFace.Body,
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

	return React.createElement(Panel, {
		medieval = false, -- Disable redundant medieval corners inside modal
		Size = UDim2.new(1, 0, 0, totalHeight),
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
				TextSize = Theme.TextSize.Heading,
				FontFace = Theme.FontFace.Display,
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
				TextSize = Theme.TextSize.Small,
				FontFace = Theme.FontFace.Body,
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
				TextSize = Theme.TextSize.Caption,
				FontFace = Theme.FontFace.Body,
				TextXAlignment = Enum.TextXAlignment.Right,
			}) or nil,
		}),

		QuestsContainer = not collapsed and React.createElement("Frame", {
			Size = UDim2.new(1, -10, 1, -headerHeight - 5),
			Position = UDim2.fromOffset(5, headerHeight + 5),
			BackgroundTransparency = 1,
		}, questElements) or nil,
	})
end

return QuestTracker
