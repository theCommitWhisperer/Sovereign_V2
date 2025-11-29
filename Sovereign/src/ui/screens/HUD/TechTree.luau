--!strict
-- TechTree: Full-screen modal showing technology research tree

local React = require(game.ReplicatedStorage.Packages.react)
local UIConfig = require(script.Parent.Parent.Parent.UIConfig)
local Modal = require(script.Parent.Parent.Parent.components.Modal)
local Button = require(script.Parent.Parent.Parent.components.Button)

local TechTree = React.Component:extend("TechTree")

function TechTree:init()
	self:setState({
		technologies = {},
		researched = {},
		currentResearch = nil,
		playerResources = {},
		selectedCategory = "Economy",
	})
end

function TechTree:didMount()
	-- Request tech data from server
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
	local GameEvent = RemoteEvents:WaitForChild("GameEvent")

	GameEvent:FireServer("GetTechnologies")

	-- Listen for tech updates
	self.techConnection = GameEvent.OnClientEvent:Connect(function(action, data)
		if action == "TechnologiesData" then
			self:setState({
				technologies = data.technologies or {},
				researched = data.researched or {},
				currentResearch = data.currentResearch,
			})
		elseif action == "ResearchStarted" then
			-- Refresh tech data
			GameEvent:FireServer("GetTechnologies")
		elseif action == "ResearchCompleted" then
			-- Show completion notification and refresh
			GameEvent:FireServer("GetTechnologies")
		end
	end)
end

function TechTree:willUnmount()
	if self.techConnection then
		self.techConnection:Disconnect()
	end
end

function TechTree:render()
	if not self.props.visible then
		return nil
	end

	local technologies = self.state.technologies or {}
	local researched = self.state.researched or {}
	local currentResearch = self.state.currentResearch
	local selectedCategory = self.state.selectedCategory
	local playerResources = self.props.playerResources or {}

	-- Group technologies by category
	local categories = { "Economy", "Military", "Building", "Special" }
	local techsByCategory = {
		Economy = {},
		Military = {},
		Building = {},
		Special = {},
	}

	for techId, tech in pairs(technologies) do
		if tech.category and techsByCategory[tech.category] then
			table.insert(techsByCategory[tech.category], {
				id = techId,
				data = tech,
				isResearched = researched[techId] or false,
				isResearching = currentResearch and currentResearch.techId == techId,
			})
		end
	end

	-- Category buttons
	local categoryButtons = {}
	for index, category in ipairs(categories) do
		categoryButtons["Category_" .. category] = React.createElement("TextButton", {
			Size = UDim2.new(0.24, -5, 0, 35),
			Position = UDim2.new((index - 1) * 0.25, 5, 0, 0),
			BackgroundColor3 = selectedCategory == category and UIConfig.HUD.CategoryButtonSelected
				or UIConfig.HUD.CategoryButtonBackground,
			BorderSizePixel = 2,
			BorderColor3 = UIConfig.HUD.StrokeColor,
			Text = category,
			TextColor3 = UIConfig.HUD.PanelTextColor,
			TextSize = 16,
			Font = UIConfig.Font.Title,
			AutoButtonColor = selectedCategory ~= category,
			[React.Event.Activated] = function()
				self:setState({ selectedCategory = category })
			end,
		})
	end

	-- Tech nodes for selected category
	local techNodes = {}
	local techs = techsByCategory[selectedCategory] or {}

	for index, techEntry in ipairs(techs) do
		local tech = techEntry.data
		local techId = techEntry.id
		local isResearched = techEntry.isResearched
		local isResearching = techEntry.isResearching

		-- Check if can research (has prerequisites)
		local canResearch = true
		local missingPrereqs = {}
		if tech.prerequisites then
			for _, prereqId in ipairs(tech.prerequisites) do
				if not researched[prereqId] then
					canResearch = false
					table.insert(missingPrereqs, prereqId)
				end
			end
		end

		-- Check if can afford
		local canAfford = true
		if tech.cost then
			for resource, cost in pairs(tech.cost) do
				if (playerResources[resource] or 0) < cost then
					canAfford = false
					break
				end
			end
		end

		-- Determine background color
		local bgColor
		if isResearched then
			bgColor = UIConfig.HUD.AccentGold -- Completed
		elseif isResearching then
			bgColor = Color3.fromRGB(100, 150, 255) -- In progress (blue)
		elseif not canResearch then
			bgColor = Color3.fromRGB(100, 100, 100) -- Locked (gray)
		elseif canAfford then
			bgColor = UIConfig.HUD.BuildingButtonAffordable -- Can afford (green)
		else
			bgColor = UIConfig.HUD.BuildingButtonUnaffordable -- Cannot afford (red)
		end

		-- Research progress bar
		local researchProgress = 0
		if isResearching and currentResearch then
			local elapsed = tick() - currentResearch.startTime
			local total = currentResearch.completeTime - currentResearch.startTime
			researchProgress = math.clamp(elapsed / total, 0, 1)
		end

		techNodes["Tech_" .. techId] = React.createElement("Frame", {
			Size = UDim2.new(0, 180, 0, 140),
			BackgroundColor3 = bgColor,
			BorderSizePixel = 2,
			BorderColor3 = UIConfig.HUD.StrokeColor,
			LayoutOrder = index,
		}, {
			TechName = React.createElement("TextLabel", {
				Size = UDim2.new(1, -10, 0, 25),
				Position = UDim2.fromOffset(5, 5),
				BackgroundTransparency = 1,
				Text = tech.name,
				TextColor3 = Color3.fromRGB(255, 255, 255),
				TextSize = 14,
				Font = UIConfig.Font.Title,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextWrapped = true,
			}),

			Description = React.createElement("TextLabel", {
				Size = UDim2.new(1, -10, 0, 50),
				Position = UDim2.fromOffset(5, 30),
				BackgroundTransparency = 1,
				Text = tech.description,
				TextColor3 = Color3.fromRGB(230, 230, 230),
				TextSize = 11,
				Font = UIConfig.Font.Default,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				TextWrapped = true,
			}),

			TimeLabel = React.createElement("TextLabel", {
				Size = UDim2.new(1, -10, 0, 15),
				Position = UDim2.fromOffset(5, 85),
				BackgroundTransparency = 1,
				Text = string.format("⏱️ %ds", tech.researchTime),
				TextColor3 = Color3.fromRGB(200, 200, 200),
				TextSize = 11,
				Font = UIConfig.Font.Default,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),

			StatusLabel = React.createElement("TextLabel", {
				Size = UDim2.new(1, -10, 0, 15),
				Position = UDim2.fromOffset(5, 102),
				BackgroundTransparency = 1,
				Text = isResearched and "✅ Researched"
					or isResearching and string.format("🔬 %.0f%%", researchProgress * 100)
					or not canResearch and "🔒 Locked"
					or canAfford and "✨ Available"
					or "💰 Need Resources",
				TextColor3 = Color3.fromRGB(255, 255, 255),
				TextSize = 11,
				Font = UIConfig.Font.Default,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),

			ResearchButton = (not isResearched and not isResearching and canResearch) and React.createElement(
				"TextButton",
				{
					Size = UDim2.new(1, -10, 0, 18),
					Position = UDim2.fromOffset(5, 117),
					BackgroundColor3 = canAfford and Color3.fromRGB(50, 150, 50) or Color3.fromRGB(150, 50, 50),
					BorderSizePixel = 1,
					BorderColor3 = Color3.fromRGB(255, 255, 255),
					Text = "Research",
					TextColor3 = Color3.fromRGB(255, 255, 255),
					TextSize = 12,
					Font = UIConfig.Font.Title,
					AutoButtonColor = canAfford,
					[React.Event.Activated] = function()
						if canAfford then
							if self.props.onResearchStarted then
								self.props.onResearchStarted(techId)
							end
						end
					end,
				}
			) or nil,

			ProgressBar = isResearching and React.createElement("Frame", {
				Size = UDim2.new(researchProgress, 0, 0, 3),
				Position = UDim2.new(0, 5, 1, -3),
				BackgroundColor3 = Color3.fromRGB(100, 200, 255),
				BorderSizePixel = 0,
			}) or nil,

			UIStroke = React.createElement("UIStroke", {
				Color = UIConfig.HUD.StrokeColor,
				Thickness = 1.5,
			}),
		})
	end

	return React.createElement(Modal, {
		title = "🔬 Technology Research",
		visible = self.props.visible,
		onClose = self.props.onClose,
		size = UDim2.fromScale(0.85, 0.9),
	}, {
		CategoryBar = React.createElement("Frame", {
			Size = UDim2.new(1, 0, 0, 40),
			BackgroundTransparency = 1,
		}, categoryButtons),

		TechGrid = React.createElement("ScrollingFrame", {
			Size = UDim2.new(1, 0, 1, -50),
			Position = UDim2.fromOffset(0, 45),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 8,
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			CanvasSize = UDim2.fromScale(0, 0),
		}, React.assign({
			Layout = React.createElement("UIGridLayout", {
				CellSize = UDim2.fromOffset(180, 140),
				CellPadding = UDim2.fromOffset(15, 15),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
			Padding = React.createElement("UIPadding", {
				PaddingLeft = UDim.new(0, 10),
				PaddingRight = UDim.new(0, 10),
				PaddingTop = UDim.new(0, 10),
				PaddingBottom = UDim.new(0, 10),
			}),
		}, techNodes)),

		HelpText = React.createElement("TextLabel", {
			Size = UDim2.new(1, -20, 0, 20),
			Position = UDim2.new(0, 10, 1, 25),
			BackgroundTransparency = 1,
			Text = "Research technologies to unlock powerful bonuses • Gray = Locked • Red = Need Resources • Green = Available",
			TextColor3 = UIConfig.HUD.PanelTextColor,
			TextSize = 12,
			Font = UIConfig.Font.Default,
			TextXAlignment = Enum.TextXAlignment.Center,
		}),
	})
end

return TechTree
