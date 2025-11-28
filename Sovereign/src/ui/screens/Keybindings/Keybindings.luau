-- The keybindings screen where players can remap controls.
local React = require(game.ReplicatedStorage.Packages.react)
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local UIConfig = require(script.Parent.Parent.Parent.UIConfig)
local Button = require(script.Parent.Parent.Parent.components.Button)

local Keybindings = React.Component:extend("Keybindings")

local KeybindingsManager = require(script.Parent.Parent.Parent.Parent.Client.Camera.KeybindingsManager)

function Keybindings:init()
	self:setState({
		keybindings = KeybindingsManager.GetAllKeybindings(),
		waitingForInput = nil,
		conflictMessage = nil,
	})
	self.managerConnection = nil
end

function Keybindings:didMount()
	-- Listen for key input when waiting for rebind
	self.inputConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if self.state.waitingForInput and input.UserInputType == Enum.UserInputType.Keyboard then
			self:handleKeyInput(input.KeyCode)
		end
	end)

	-- Listen for external changes from the manager (e.g., reset to defaults)
	self.managerConnections = {}
	for _, action in ipairs(KeybindingsManager.GetAllActions()) do
		local connection = KeybindingsManager.OnKeybindingChanged(action, function()
			self:setState({ keybindings = KeybindingsManager.GetAllKeybindings() })
		end)
		table.insert(self.managerConnections, connection)
	end
end

function Keybindings:willUnmount()
	-- Clean up input connection
	if self.inputConnection then
		self.inputConnection:Disconnect()
		self.inputConnection = nil
	end
	-- Clean up manager connections
	if self.managerConnections then
		for _, connection in ipairs(self.managerConnections) do
			connection:Disconnect()
		end
		self.managerConnections = nil
	end
end

function Keybindings:handleKeyInput(keyCode)

	local action = self.state.waitingForInput

	if not action then

		return

	end



	local success, conflictAction = KeybindingsManager.SetKeybinding(action, keyCode)



	if success then

		self:setState({

			waitingForInput = nil,

			conflictMessage = nil,

			keybindings = KeybindingsManager.GetAllKeybindings(),

		})

	else

		local keyName = KeybindingsManager.GetKeyCodeName(keyCode)

		local conflictDesc = "another action"

		if conflictAction then

			conflictDesc = KeybindingsManager.GetActionDescription(conflictAction)

		end



		self:setState({

			waitingForInput = nil,

			conflictMessage = string.format("'%s' is already bound to %s", keyName, conflictDesc),

		})



		-- Clear the message after a delay

		task.delay(3, function()

			if self.state.conflictMessage then

				self:setState({ conflictMessage = nil })

			end

		end)

	end

end



function Keybindings:createKeybindingRow(action, displayName, keyName, layoutOrder, waitingForInput)
	local isWaiting = waitingForInput == action
	local buttonText = isWaiting and "Press any key..." or keyName

	return React.createElement("Frame", {
		Size = UDim2.new(0.9, 0, 0, 40),
		BackgroundTransparency = 1,
		LayoutOrder = layoutOrder,
	}, {
		Label = React.createElement("TextLabel", {
			Text = displayName,
			Size = UDim2.new(0.6, 0, 1, 0),
			Position = UDim2.fromScale(0, 0.5),
			AnchorPoint = Vector2.new(0, 0.5),
			TextSize = 24,
			FontFace = UIConfig.Font.Default,
			TextColor3 = UIConfig.Color.Primary,
			BackgroundTransparency = 1,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		KeyButton = React.createElement(Button, {
			Text = buttonText,
			TextSize = 24,
			Size = UDim2.new(0, 150, 0, 35),
			Position = UDim2.fromScale(1, 0.5),
			AnchorPoint = Vector2.new(1, 0.5),
			BackgroundTransparency = isWaiting and 0.3 or 1,
			OnClick = function()
				self.state.waitingForInput = action
				self:setState({})
			end,
		}),
	})
end

function Keybindings:render()
	local navigate = self.props.navigate

	local actionGroups = {
		{
			Title = "Camera Movement",
			Actions = { "PanUp", "PanDown", "PanLeft", "PanRight" },
		},
		{
			Title = "Camera Rotation",
			Actions = { "RotateLeft", "RotateRight" },
		},
		{
			Title = "Camera Actions",
			Actions = { "Focus", "ResetCamera", "ToggleCameraMode" },
		},
		{
			Title = "Placement",
			Actions = { "RotatePlacement", "CyclePlacementType", "CyclePivot" },
		},
	}

	local keybindingElements = {}
	local layoutOrder = 1
	for _, group in ipairs(actionGroups) do
		-- Group Header
		table.insert(
			keybindingElements,
			React.createElement("TextLabel", {
				Text = group.Title,
				Size = UDim2.new(0.9, 0, 0, 30),
				TextSize = 28,
				FontFace = UIConfig.Font.Title,
				TextColor3 = UIConfig.Color.Primary,
				BackgroundTransparency = 1,
				TextXAlignment = Enum.TextXAlignment.Left,
				LayoutOrder = layoutOrder,
			})
		)
		layoutOrder = layoutOrder + 1

		-- Keybinding Rows
		for _, action in ipairs(group.Actions) do
			local keyCode = self.state.keybindings[action]
			if keyCode then
				table.insert(
					keybindingElements,
					self:createKeybindingRow(
						action,
						KeybindingsManager.GetActionDescription(action),
						KeybindingsManager.GetKeyCodeName(keyCode),
						layoutOrder,
						self.state.waitingForInput
					)
				)
				layoutOrder = layoutOrder + 1
			end
		end
	end

	-- Info text
	table.insert(keybindingElements, React.createElement("TextLabel", {
		Text = "Right-click drag: Rotate camera (yaw & pitch)\nMiddle-click drag: Pan camera\nMouse wheel: Zoom in/out\n\nMobile: Use touch gestures\n\nClick a button and press any key to rebind",
		Size = UDim2.new(0.9, 0, 0, 120),
		TextSize = 18,
		FontFace = UIConfig.Font.Default,
		TextColor3 = Color3.fromRGB(200, 200, 200),
		BackgroundTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		LayoutOrder = layoutOrder,
	}))

	return React.createElement("ScreenGui", { Name = "KeybindingsGui", ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, {
		Background = React.createElement("Frame", {
			Name = "Background",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.5,
			BorderSizePixel = 0,
		}),
		ScrollImage = React.createElement("ImageLabel", {
			Name = "ScrollImage",
			Size = UDim2.new(0.6, 0, 0.9, 0),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Image = "rbxassetid://97541657322605",
			ScaleType = Enum.ScaleType.Stretch,
			BackgroundTransparency = 1,
			ZIndex = 2,
		}, {
			Header = React.createElement("Frame", {
				Name = "Header",
				Size = UDim2.new(0.5, 0, 0.12, 0),
				Position = UDim2.fromScale(0.5, 0.08),
				AnchorPoint = Vector2.new(0.5, 0),
				BackgroundTransparency = 1,
			}, {
				Title = React.createElement("TextLabel", {
					Text = "Controls",
					Size = UDim2.fromScale(1, 1),
					TextSize = 38,
					FontFace = UIConfig.Font.Title,
					BackgroundTransparency = 1,
					TextColor3 = UIConfig.Color.Primary,
				}),
			}),

			-- Conflict message
			ConflictMessage = self.state.conflictMessage and React.createElement("TextLabel", {
				Name = "ConflictMessage",
				Text = self.state.conflictMessage,
				Size = UDim2.new(0.5, 0, 0, 30),
				Position = UDim2.fromScale(0.5, 0.19),
				AnchorPoint = Vector2.new(0.5, 0),
				TextSize = 20,
				FontFace = UIConfig.Font.Default,
				TextColor3 = Color3.fromRGB(255, 100, 100),
				BackgroundTransparency = 1,
			}) or nil,

			ContentFrame = React.createElement("ScrollingFrame", {
				Name = "ContentFrame",
				Size = UDim2.new(0.5, 0, 0.6, 0),
				Position = UDim2.fromScale(0.5, 0.5),
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
				ScrollBarImageColor3 = Color3.new(0, 0, 0),
				ScrollBarThickness = 6,
				ClipsDescendants = true,
			}, {
				Padding = React.createElement("UIPadding", {
					PaddingTop = UDim.new(0, 20),
				}),
				Layout = React.createElement("UIListLayout", {
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 12),
					HorizontalAlignment = Enum.HorizontalAlignment.Center,
				}),
				-- Insert all the dynamic elements here
				Elements = React.createElement(React.Fragment, {}, keybindingElements),
			}),

			Footer = React.createElement("Frame", {
				Name = "Footer",
				Size = UDim2.new(0.5, 0, 0.12, 0),
				Position = UDim2.fromScale(0.5, 0.8),
				AnchorPoint = Vector2.new(0.5, 0),
				BackgroundTransparency = 1,
			}, {
				ButtonLayout = React.createElement("UIListLayout", {
					FillDirection = Enum.FillDirection.Horizontal,
					HorizontalAlignment = Enum.HorizontalAlignment.Center,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					Padding = UDim.new(0, 20),
				}),
				ResetButton = React.createElement(Button, {
					Name = "ResetButton",
					Text = "Reset to Defaults",
					Size = UDim2.new(0, 180, 0, 45),
					BackgroundTransparency = 1,
					TextSize = 28,
					OnClick = function()
						KeybindingsManager.ResetToDefaults()
						self:setState({
							waitingForInput = nil,
							conflictMessage = nil,
							keybindings = KeybindingsManager.GetAllKeybindings(),
						})
					end,
				}),
				BackButton = React.createElement(Button, {
					Name = "BackButton",
					Text = "Back",
					Size = UDim2.new(0, 150, 0, 45),
					BackgroundTransparency = 1,
					TextSize = 28,
					OnClick = function()
						if navigate then
							navigate("settings")
						end
					end,
				}),
			}),
		}),
	})
end

return Keybindings
