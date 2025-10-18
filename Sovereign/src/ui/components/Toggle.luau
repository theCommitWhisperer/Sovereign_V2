-- A reusable component for toggling boolean values or cycling through a list of options.
local React = require(game.ReplicatedStorage.Packages.react)
local UIConfig = require(script.Parent.Parent.UIConfig)

local Toggle = React.Component:extend("Toggle")

function Toggle:render()
	local value = self.props.value
	local onValueChanged = self.props.onValueChanged
	local options = self.props.options
	local isCycler = options ~= nil

	local function handleLeftClick()
		if not onValueChanged then
			return
		end
		if isCycler then
			local currentIndex = table.find(options, value) or 1
			local prevIndex = (currentIndex - 2 + #options) % #options + 1
			onValueChanged(options[prevIndex])
		else
			onValueChanged(not value)
		end
	end

	local function handleRightClick()
		if not onValueChanged then
			return
		end
		if isCycler then
			local currentIndex = table.find(options, value) or 1
			local nextIndex = (currentIndex % #options) + 1
			onValueChanged(options[nextIndex])
		else
			onValueChanged(not value)
		end
	end

	local hasLabel = self.props.label ~= nil

	return React.createElement("Frame", {
		Name = "Toggle",
		Size = self.props.Size or UDim2.new(1, 0, 0, 24),
		Position = self.props.Position,
		AnchorPoint = self.props.AnchorPoint,
		LayoutOrder = self.props.LayoutOrder,
		BackgroundTransparency = 1,
	}, {
		Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 10),
		}),
		Label = hasLabel and React.createElement("TextLabel", {
			Text = self.props.label,
			Size = UDim2.new(0.5, -5, 1, 0),
			FontFace = UIConfig.Font.Default,
			TextColor3 = UIConfig.Color.Primary,
			TextSize = 22,
			BackgroundTransparency = 1,
			TextXAlignment = Enum.TextXAlignment.Left,
		}) or nil,

		ControlFrame = React.createElement("Frame", {
			Size = hasLabel and UDim2.new(0.5, -5, 1, 0) or UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
		}, {
			Layout = React.createElement("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder, -- This is the key fix
			}),
			LeftArrow = React.createElement("TextButton", {
				LayoutOrder = 1, -- Arrow First
				Name = "LeftArrow",
				Size = UDim2.new(0, 24, 1, 0),
				Text = "<",
				FontFace = UIConfig.Font.Default,
				TextColor3 = UIConfig.Color.Primary,
				TextSize = 24,
				BackgroundTransparency = 1,
				[React.Event.MouseButton1Click] = handleLeftClick,
			}),
			ValueLabel = React.createElement("TextLabel", {
				LayoutOrder = 2, -- Value Second
				Name = "ValueLabel",
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.new(0, 0, 1, 0),
				Text = " " .. tostring(value) .. " ",
				FontFace = UIConfig.Font.Default,
				TextColor3 = UIConfig.Color.Primary,
				TextSize = 22,
				BackgroundTransparency = 1,
			}),
			RightArrow = React.createElement("TextButton", {
				LayoutOrder = 3, -- Arrow Third
				Name = "RightArrow",
				Size = UDim2.new(0, 24, 1, 0),
				Text = ">",
				FontFace = UIConfig.Font.Default,
				TextColor3 = UIConfig.Color.Primary,
				TextSize = 24,
				BackgroundTransparency = 1,
				[React.Event.MouseButton1Click] = handleRightClick,
			}),
		}),
	})
end

return Toggle
