-- src/ui/screens/MainMenu/MainMenu.luau

local React = require(game.ReplicatedStorage.Packages.react)
local UIConfig = require(script.Parent.Parent.Parent.UIConfig)

-- Corrected paths to the 'components' directory
local Title = require(script.Parent.Parent.Parent.components.Title)
local Button = require(script.Parent.Parent.Parent.components.Button)

local MainMenu = React.Component:extend("MainMenu")

function MainMenu:render()
	print("MainMenu.luau: render() called. UI should be visible.")
	return React.createElement("ScreenGui", {
		Name = "MainMenuGui",
		ClipToDeviceSafeArea = true,
		DisplayOrder = 0,
		SafeAreaCompatibility = 1,
		ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets,
		Enabled = true,
		ResetOnSpawn = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, {
		BackgroundImage = React.createElement("ImageLabel", {
			Name = "BackgroundImage",
			Image = "rbxassetid://99876577284469",
			ScaleType = Enum.ScaleType.Stretch,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 1,
		}),
		MenuContainer = React.createElement("Frame", {
			Name = "MenuContainer",
			AnchorPoint = Vector2.new(0, 0.5),
			BackgroundTransparency = 1,
			Position = UDim2.new(0.08, 0, 0.5, 0),
			Size = UDim2.new(0.3, 0, 0.5, 0),
			ZIndex = 2,
		}, {
			UIListLayout = React.createElement("UIListLayout", {
				Padding = UDim.new(0, 50),
				FillDirection = Enum.FillDirection.Vertical,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
				VerticalAlignment = Enum.VerticalAlignment.Center,
			}),
			Title = React.createElement(Title, {
				LayoutOrder = 1,
				Size = UDim2.new(1, 0, 0, 80),
				Text = "Sovereign",
				TextSize = 80,
				TextColor3 = UIConfig.Color.Primary,
				BackgroundTransparency = 1,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			Spacer = React.createElement("Frame", {
				Name = "Spacer",
				LayoutOrder = 2,
				Size = UDim2.new(1, 0, 0, 150),
				BackgroundTransparency = 1,
			}),
			PlayGameButton = React.createElement(Button, {
				Name = "PlayGameButton",
				LayoutOrder = 3,
				Size = UDim2.new(1, 0, 0, 40),
				Text = "Play",
				TextSize = 40,
				BackgroundTransparency = 1,
				TextXAlignment = Enum.TextXAlignment.Left,
				OnClick = function()
					self.props.navigate("lobby")
				end,
			}),
			SettingsGameButton = React.createElement(Button, {
				Name = "SettingsGameButton",
				LayoutOrder = 4,
				Size = UDim2.new(1, 0, 0, 40),
				Text = "Settings",
				TextSize = 40,
				BackgroundTransparency = 1,
				TextXAlignment = Enum.TextXAlignment.Left,
				OnClick = function()
					self.props.navigate("settings")
				end,
			}),
			ExitGameButton = React.createElement(Button, {
				Name = "ExitGameButton",
				LayoutOrder = 5,
				Size = UDim2.new(1, 0, 0, 40),
				Text = "Exit",
				TextSize = 40,
				BackgroundTransparency = 1,
				TextXAlignment = Enum.TextXAlignment.Left,
				OnClick = function()
					game:GetService("Players").LocalPlayer:Kick("Player exited the game.")
				end,
			}),
		}),
	})
end

return MainMenu
