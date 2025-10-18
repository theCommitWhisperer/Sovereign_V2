-- In thecommitwhisperer/sovereign_v2/Sovereign_V2-2a7f9b1a80569056b2a17430b670ecd3e29324fa/Sovereign/src/ui/components/Slider.luau
-- A reusable slider component for things like volume control.
local React = require(game.ReplicatedStorage.Packages.react)
local UIConfig = require(script.Parent.Parent.UIConfig)
local UserInputService = game:GetService("UserInputService")

local Slider = React.Component:extend("Slider")

function Slider:init()
	self.state = {
		value = self.props.value or 50,
		showPercentage = false,
	}
	self.isDragging = false
	self.mouseMoveConnection = nil
	self.mouseUpConnection = nil
	self.lastInteractionTime = 0
end

function Slider:willUnmount()
	if self.mouseMoveConnection then
		self.mouseMoveConnection:Disconnect()
	end
	if self.mouseUpConnection then
		self.mouseUpConnection:Disconnect()
	end
end

function Slider:render()
	local value = self.state.value
	local min = self.props.min or 0
	local max = self.props.max or 100
	local percentage = (max - min) > 0 and (value - min) / (max - min) or 0

	return React.createElement("Frame", {
		Name = "SliderContainer",
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
		Label = React.createElement("TextLabel", {
			Text = self.props.label or "",
			Size = UDim2.new(0.4, 0, 1, 0),
			FontFace = UIConfig.Font.Default,
			TextColor3 = UIConfig.Color.Primary,
			TextSize = 22,
			BackgroundTransparency = 1,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		SliderFrame = React.createElement("Frame", {
			Name = "Slider",
			Size = UDim2.new(0.6, 0, 0, 4),
			BackgroundTransparency = 1,
		}, {
			Padding = React.createElement("UIPadding", {
				PaddingLeft = UDim.new(0, 6),
				PaddingRight = UDim.new(0, 6),
			}),
			Background = React.createElement("Frame", {
				Name = "BackgroundBar",
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = UIConfig.Color.SliderTrack,
				BorderSizePixel = 0,
			}, {
				Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 2) }),
			}),
			Progress = React.createElement("Frame", {
				Name = "Progress",
				Size = UDim2.new(percentage, 0, 1, 0),
				BackgroundColor3 = UIConfig.Color.SliderProgress,
				BorderSizePixel = 0,
			}, {
				Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 2) }),
			}),
			Handle = React.createElement("TextButton", {
				Name = "Handle",
				Size = UDim2.new(0, 12, 0, 12),
				Position = UDim2.new(percentage, 0, 0.5, 0),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Text = "",
				BackgroundColor3 = UIConfig.Color.SliderProgress,
				ZIndex = 2,
				[React.Event.MouseButton1Down] = function(rbx)
					self.isDragging = true
					self.lastInteractionTime = tick()
					self:setState({ showPercentage = true })

					if self.mouseMoveConnection then
						self.mouseMoveConnection:Disconnect()
					end
					if self.mouseUpConnection then
						self.mouseUpConnection:Disconnect()
					end

					self.mouseMoveConnection = UserInputService.InputChanged:Connect(function(input)
						if input.UserInputType == Enum.UserInputType.MouseMovement and self.isDragging then
							self.lastInteractionTime = tick()
							local frame = rbx.Parent
							local relativeX = UserInputService:GetMouseLocation().X - frame.AbsolutePosition.X
							local newPercentage = math.clamp(relativeX / frame.AbsoluteSize.X, 0, 1)
							local newValue = math.floor(min + (max - min) * newPercentage)
							if newValue ~= self.state.value then
								self:setState({ value = newValue })
								if self.props.onValueChanged then
									self.props.onValueChanged(newValue)
								end
							end
						end
					end)
					self.mouseUpConnection = UserInputService.InputEnded:Connect(function(input)
						if input.UserInputType == Enum.UserInputType.MouseButton1 then
							self.isDragging = false
							if self.mouseMoveConnection then
								self.mouseMoveConnection:Disconnect()
							end
							if self.mouseUpConnection then
								self.mouseUpConnection:Disconnect()
							end
							local interactionTime = self.lastInteractionTime
							spawn(function()
								task.wait(2)
								if self.lastInteractionTime == interactionTime then
									self:setState({ showPercentage = false })
								end
							end)
						end
					end)
				end,
			}, {
				Corner = React.createElement("UICorner", { CornerRadius = UDim.new(1, 0) }),
			}),
			Tooltip = self.state.showPercentage and React.createElement("Frame", {
				Name = "TooltipFrame",
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(percentage, 0, 0.5, -20),
				Size = UDim2.new(0, 40, 0, 24),
				BackgroundTransparency = 1,
				ZIndex = 3,
			}, {
				Container = React.createElement("Frame", {
					Name = "Container",
					Size = UDim2.fromScale(1, 1),
					BackgroundColor3 = UIConfig.Color.TooltipBackground,
				}, {
					Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 4) }),
					Label = React.createElement("TextLabel", {
						Text = tostring(value),
						Size = UDim2.fromScale(1, 1),
						BackgroundTransparency = 1,
						TextColor3 = UIConfig.Color.Primary,
						FontFace = UIConfig.Font.Default,
						TextSize = 18,
					}),
				}),
				Pointer = React.createElement("ImageLabel", {
					AnchorPoint = Vector2.new(0.5, 0),
					Position = UDim2.new(0.5, 0, 1, -1),
					Size = UDim2.new(0, 12, 0, 6),
					BackgroundTransparency = 1,
					ImageColor3 = UIConfig.Color.TooltipBackground,
					Image = "rbxassetid://3926305904",
					ZIndex = -1,
				}),
			}) or nil,
		}),
	})
end

return Slider
