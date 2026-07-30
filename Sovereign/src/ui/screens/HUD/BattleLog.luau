local React = require(game.ReplicatedStorage.Packages.react)
local UIConfig = require(script.Parent.Parent.Parent.UIConfig)

local BattleLog = React.Component:extend("BattleLog")

function BattleLog:init()
	self:setState({
		messages = self.props.messages or {},
		isExpanded = false,
	})
end

function BattleLog:didUpdate(prevProps)
	if self.props.messages ~= prevProps.messages then
		self:setState({ messages = self.props.messages })
	end
end

function BattleLog:render()
	local visibleMessages = self.state.isExpanded and self.state.messages or {
		self.state.messages[#self.state.messages],
		self.state.messages[#self.state.messages - 1],
		self.state.messages[#self.state.messages - 2],
	}

	-- Filter out nil values
	local filteredMessages = {}
	for _, msg in ipairs(visibleMessages) do
		if msg then
			table.insert(filteredMessages, msg)
		end
	end

	local messageElements = {}
	for i, message in ipairs(filteredMessages) do
		messageElements["Message" .. i] = React.createElement("TextLabel", {
			Size = UDim2.new(1, -10, 0, 20),
			BackgroundTransparency = 1,
			Text = message.text,
			TextColor3 = message.color or Color3.fromRGB(255, 255, 255),
			TextSize = 12,
			Font = Enum.Font.Gotham,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextWrapped = true,
			LayoutOrder = #filteredMessages - i, -- Reverse order (newest at bottom)
		})
	end

	return React.createElement("Frame", {
		Size = UDim2.new(0, 350, 0, self.state.isExpanded and 250 or 80),
		Position = UDim2.new(1, -370, 1, -(UIConfig.HUD.BottomBarHeight + (self.state.isExpanded and 270 or 100))),
		BackgroundColor3 = Color3.fromRGB(20, 20, 20),
		BackgroundTransparency = 0.3,
		BorderSizePixel = 2,
		BorderColor3 = UIConfig.HUD.TopButtonBorder,
		ZIndex = 15,
	}, {
		Header = React.createElement("Frame", {
			Size = UDim2.new(1, 0, 0, 25),
			BackgroundColor3 = Color3.fromRGB(40, 30, 20),
			BorderSizePixel = 0,
		}, {
			Title = React.createElement("TextLabel", {
				Size = UDim2.new(1, -30, 1, 0),
				BackgroundTransparency = 1,
				Text = "⚔️ Battle Log",
				TextColor3 = UIConfig.HUD.AccentGold,
				TextSize = 14,
				Font = Enum.Font.GothamBold,
				TextXAlignment = Enum.TextXAlignment.Left,
			}, {
				Padding = React.createElement("UIPadding", {
					PaddingLeft = UDim.new(0, 8),
				}),
			}),
			ExpandButton = React.createElement("TextButton", {
				Size = UDim2.fromOffset(25, 25),
				Position = UDim2.new(1, -25, 0, 0),
				BackgroundTransparency = 1,
				Text = self.state.isExpanded and "▼" or "▲",
				TextColor3 = Color3.fromRGB(200, 200, 200),
				TextSize = 12,
				Font = Enum.Font.GothamBold,
				[React.Event.MouseButton1Click] = function()
					self:setState({ isExpanded = not self.state.isExpanded })
				end,
			}),
		}),

		MessageContainer = React.createElement("Frame", {
			Size = UDim2.new(1, -10, 1, -30),
			Position = UDim2.fromOffset(5, 28),
			BackgroundTransparency = 1,
		}, {
			Layout = React.createElement("UIListLayout", {
				FillDirection = Enum.FillDirection.Vertical,
				Padding = UDim.new(0, 2),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
			Messages = React.createElement(React.Fragment, nil, messageElements),
		}),
	})
end

return BattleLog
