-- The keybindings screen where players can remap controls.
local React = require(game.ReplicatedStorage.Packages.react)
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local UIConfig = require(script.Parent.Parent.Parent.UIConfig)
local Button = require(script.Parent.Parent.Parent.components.Button)

local Keybindings = React.Component:extend("Keybindings")

function Keybindings:init()
	-- Get the KeybindingsManager from the camera controller
	local player = Players.LocalPlayer
	local cameraController = nil

	-- Try to get camera controller from client scripts
	local success = pcall(function()
		local cameraScript = player.PlayerScripts.Parent:FindFirstChild("client")
		if cameraScript then
			local cameraModule = cameraScript:FindFirstChild("Camera")
			if cameraModule then
				-- Camera controller should be accessible through shared state
				-- For now, we'll load keybindings from player attributes
			end
		end
	end)

	self:setState({
		keybindings = {
			-- Camera Controls - Load from defaults
			PanUp = "W",
			PanDown = "S",
			PanLeft = "A",
			PanRight = "D",
			RotateLeft = "Q",
			RotateRight = "E",
			Focus = "F",
			ResetCamera = "Home",
			ToggleCameraMode = "Tab",
		},
		waitingForInput = nil, -- Which action is waiting for key rebind
		scrollbarVisible = false,
		conflictMessage = nil,
	})
	self.lastScrollTime = 0
	self.inputConnection = nil
end

function Keybindings:didMount()
	-- Listen for key input when waiting for rebind
	self.inputConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		-- Don't ignore gameProcessed - we want to catch all keyboard input when rebinding
		if self.state.waitingForInput and input.UserInputType == Enum.UserInputType.Keyboard then
			self:handleKeyInput(input.KeyCode)
		end
	end)
end

function Keybindings:willUnmount()
	-- Clean up input connection
	if self.inputConnection then
		self.inputConnection:Disconnect()
		self.inputConnection = nil
	end
end

function Keybindings:handleKeyInput(keyCode)
	local action = self.state.waitingForInput
	if not action then
		return
	end

	local keyName = self:getKeyDisplayName(keyCode.Name)

	-- Check for conflict with other bindings
	for otherAction, otherKey in pairs(self.state.keybindings) do
		if otherAction ~= action and otherKey == keyName then
			self.state.conflictMessage = string.format("'%s' is already bound to %s", keyName, otherAction)
			self.state.waitingForInput = nil
			self:setState({})

			spawn(function()
				task.wait(3)
				self.state.conflictMessage = nil
				self:setState({})
			end)
			return
		end
	end

	-- Update the keybinding
	local newKeybindings = {
		PanUp = self.state.keybindings.PanUp,
		PanDown = self.state.keybindings.PanDown,
		PanLeft = self.state.keybindings.PanLeft,
		PanRight = self.state.keybindings.PanRight,
		RotateLeft = self.state.keybindings.RotateLeft,
		RotateRight = self.state.keybindings.RotateRight,
		Focus = self.state.keybindings.Focus,
		ResetCamera = self.state.keybindings.ResetCamera,
		ToggleCameraMode = self.state.keybindings.ToggleCameraMode,
	}
	newKeybindings[action] = keyName

	-- NOTE: Direct state mutation is required due to react-lua limitation
	-- react-lua does not synchronously update self.state during renders triggered by setState,
	-- even when using the functional form. This causes self.state to have stale values
	-- during the render phase. Until this is fixed in react-lua, we must mutate self.state
	-- directly before calling setState to trigger the re-render.
	self.state.keybindings = newKeybindings
	self.state.waitingForInput = nil
	self:setState({}) -- Trigger re-render

	-- Save to player attributes
	self:saveKeybindings(newKeybindings)
end

function Keybindings:saveKeybindings(keybindings)
	-- Save keybindings to player attributes
	local player = Players.LocalPlayer
	local HttpService = game:GetService("HttpService")

	local success, err = pcall(function()
		-- Convert to KeyCode values for storage
		local data = {}
		for action, keyName in pairs(keybindings) do
			-- Store as string name
			data[action] = keyName
		end

		local jsonData = HttpService:JSONEncode(data)
		player:SetAttribute("CameraKeybindings", jsonData)
	end)

	if not success then
		warn("Failed to save keybindings:", err)
	end
end

function Keybindings:getKeyDisplayName(keyCodeName)
	-- Convert internal key names to friendly display names
	if keyCodeName == "LeftShift" or keyCodeName == "RightShift" then
		return "Shift"
	elseif keyCodeName == "LeftControl" or keyCodeName == "RightControl" then
		return "Ctrl"
	elseif keyCodeName == "LeftAlt" or keyCodeName == "RightAlt" then
		return "Alt"
	end
	return keyCodeName
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
					Text = "Camera Controls",
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
				ScrollBarImageTransparency = self.state.scrollbarVisible and 0.7 or 1,
				ScrollBarThickness = 6,
				ClipsDescendants = true,
				[React.Event.InputChanged] = function(rbx, input)
					if
						input.UserInputType == Enum.UserInputType.MouseWheel
						or input.UserInputType == Enum.UserInputType.Touch
					then
						self.lastScrollTime = tick()
						if not self.state.scrollbarVisible then
							self:setState({ scrollbarVisible = true })
						end

						spawn(function()
							task.wait(2)
							if tick() - self.lastScrollTime >= 2 then
								self:setState({ scrollbarVisible = false })
							end
						end)
					end
				end,
			}, {
				Padding = React.createElement("UIPadding", {
					PaddingTop = UDim.new(0, 20),
				}),
				Layout = React.createElement("UIListLayout", {
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 12),
					HorizontalAlignment = Enum.HorizontalAlignment.Center,
				}),

				-- Camera Movement Section
				MovementHeader = React.createElement("TextLabel", {
					Text = "Camera Movement",
					Size = UDim2.new(0.9, 0, 0, 30),
					TextSize = 28,
					FontFace = UIConfig.Font.Title,
					TextColor3 = UIConfig.Color.Primary,
					BackgroundTransparency = 1,
					TextXAlignment = Enum.TextXAlignment.Left,
					LayoutOrder = 1,
				}),
				PanUp = self:createKeybindingRow("PanUp", "Pan Forward", self.state.keybindings.PanUp, 2, self.state.waitingForInput),
				PanDown = self:createKeybindingRow("PanDown", "Pan Backward", self.state.keybindings.PanDown, 3, self.state.waitingForInput),
				PanLeft = self:createKeybindingRow("PanLeft", "Pan Left", self.state.keybindings.PanLeft, 4, self.state.waitingForInput),
				PanRight = self:createKeybindingRow("PanRight", "Pan Right", self.state.keybindings.PanRight, 5, self.state.waitingForInput),

				-- Camera Rotation Section
				RotationHeader = React.createElement("TextLabel", {
					Text = "Camera Rotation",
					Size = UDim2.new(0.9, 0, 0, 30),
					TextSize = 28,
					FontFace = UIConfig.Font.Title,
					TextColor3 = UIConfig.Color.Primary,
					BackgroundTransparency = 1,
					TextXAlignment = Enum.TextXAlignment.Left,
					LayoutOrder = 6,
				}),
				RotateLeft = self:createKeybindingRow("RotateLeft", "Rotate Left", self.state.keybindings.RotateLeft, 7, self.state.waitingForInput),
				RotateRight = self:createKeybindingRow("RotateRight", "Rotate Right", self.state.keybindings.RotateRight, 8, self.state.waitingForInput),

				-- Camera Actions Section
				ActionsHeader = React.createElement("TextLabel", {
					Text = "Camera Actions",
					Size = UDim2.new(0.9, 0, 0, 30),
					TextSize = 28,
					FontFace = UIConfig.Font.Title,
					TextColor3 = UIConfig.Color.Primary,
					BackgroundTransparency = 1,
					TextXAlignment = Enum.TextXAlignment.Left,
					LayoutOrder = 9,
				}),
				Focus = self:createKeybindingRow("Focus", "Focus on Target", self.state.keybindings.Focus, 10, self.state.waitingForInput),
				ResetCamera = self:createKeybindingRow("ResetCamera", "Reset Camera", self.state.keybindings.ResetCamera, 11, self.state.waitingForInput),
				ToggleCameraMode = self:createKeybindingRow("ToggleCameraMode", "Toggle Camera Mode", self.state.keybindings.ToggleCameraMode, 12, self.state.waitingForInput),

				-- Info text
				InfoText = React.createElement("TextLabel", {
					Text = "Right-click drag: Rotate camera (yaw & pitch)\nMiddle-click drag: Pan camera\nMouse wheel: Zoom in/out\n\nMobile: Use touch gestures\n\nClick a button and press any key to rebind",
					Size = UDim2.new(0.9, 0, 0, 120),
					TextSize = 18,
					FontFace = UIConfig.Font.Default,
					TextColor3 = Color3.fromRGB(200, 200, 200),
					BackgroundTransparency = 1,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextWrapped = true,
					LayoutOrder = 13,
				}),
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
						-- Reset all keybindings to defaults
						local defaultKeybindings = {
							PanUp = "W",
							PanDown = "S",
							PanLeft = "A",
							PanRight = "D",
							RotateLeft = "Q",
							RotateRight = "E",
							Focus = "F",
							ResetCamera = "Home",
							ToggleCameraMode = "Tab",
						}
						self:setState({
							keybindings = defaultKeybindings,
							waitingForInput = nil,
							conflictMessage = nil,
						})
						self:saveKeybindings(defaultKeybindings)
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
