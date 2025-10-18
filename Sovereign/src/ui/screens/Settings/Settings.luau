-- src/ui/screens/Settings/Settings.luau

local React = require(game.ReplicatedStorage.Packages.react)
local components = script.Parent.Parent.Parent.components
local UIConfig = require(script.Parent.Parent.Parent.UIConfig)
local Button = require(components.Button)
local Slider = require(components.Slider)
local Toggle = require(components.Toggle) -- [ADD] Require the new Toggle component

local Settings = React.Component:extend("Settings")

function Settings:init()
	self:setState({ musicVolume = 100, soundEffectsVolume = 100, isFullScreen = true, showSubtitles = false })
end

function Settings:render()
	local navigate = self.props.navigate
	return React.createElement("ScreenGui", { Name = "SettingsGui", ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, {
		Background = React.createElement("Frame", {
			Name = "Background",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.5,
			BorderSizePixel = 0,
		}),
		ScrollImage = React.createElement("ImageLabel", {
			Name = "ScrollImage",
			Size = UDim2.new(0.5, 0, 0.85, 0),
			Position = UDim2.new(0.5, 0, 0.05, 0),
			AnchorPoint = Vector2.new(0.5, 0),
			Image = "rbxassetid://97541657322605",
			ScaleType = Enum.ScaleType.Stretch,
			BackgroundTransparency = 1,
			ZIndex = 2,
		}, {
			ContentFrame = React.createElement("ScrollingFrame", {
				Name = "ContentFrame",
				Size = UDim2.new(0.5, 0, 0.5, 0),
				Position = UDim2.fromScale(0.5, 0.5),
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				CanvasSize = UDim2.new(0, 0, 0, 0),
				ScrollBarImageColor3 = Color3.new(0, 0, 0),
			}, {
				Layout = React.createElement("UIListLayout", {
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 10),
					HorizontalAlignment = Enum.HorizontalAlignment.Center,
				}),

				Title = React.createElement("TextLabel", {
					Text = "Settings",
					Size = UDim2.new(1, 0, 0, 50),
					TextSize = 42,
					FontFace = UIConfig.Font.Title,
					LayoutOrder = 1,
					BackgroundTransparency = 1,
					TextColor3 = UIConfig.Color.Primary,
				}),

				MusicVolume = React.createElement("Frame", {
					Name = "MusicVolumeRow",
					Size = UDim2.new(1, 0, 0, 40),
					BackgroundTransparency = 1,
					LayoutOrder = 3,
				}, {
					Label = React.createElement("TextLabel", {
						Text = "Music Volume:",
						Size = UDim2.new(0.7, 0, 1, 0),
						Position = UDim2.fromScale(0, 0.5),
						AnchorPoint = Vector2.new(0, 0.5),
						TextSize = 24,
						FontFace = UIConfig.Font.Default,
						TextColor3 = UIConfig.Color.Primary,
						BackgroundTransparency = 1,
						TextXAlignment = Enum.TextXAlignment.Left,
					}),
					Input = React.createElement(Slider, {
						Size = UDim2.new(0, 250, 0, 4),
						Position = UDim2.fromScale(1, 0.5),
						AnchorPoint = Vector2.new(1, 0.5),
						min = 0,
						max = 100,
						value = self.state.musicVolume,
						onValueChanged = function(newValue)
							self:setState({ musicVolume = newValue })
						end,
					}),
				}),

				SoundEffectsVolume = React.createElement("Frame", {
					Name = "SoundEffectsVolumeRow",
					Size = UDim2.new(1, 0, 0, 40),
					BackgroundTransparency = 1,
					LayoutOrder = 4,
				}, {
					Label = React.createElement("TextLabel", {
						Text = "Sound Effects Volume:",
						Size = UDim2.new(0.7, 0, 1, 0),
						Position = UDim2.fromScale(0, 0.5),
						AnchorPoint = Vector2.new(0, 0.5),
						TextSize = 24,
						FontFace = UIConfig.Font.Default,
						TextColor3 = UIConfig.Color.Primary,
						BackgroundTransparency = 1,
						TextXAlignment = Enum.TextXAlignment.Left,
					}),
					Input = React.createElement(Slider, {
						Size = UDim2.new(0, 250, 0, 4),
						Position = UDim2.fromScale(1, 0.5),
						AnchorPoint = Vector2.new(1, 0.5),
						min = 0,
						max = 100,
						value = self.state.soundEffectsVolume,
						onValueChanged = function(newValue)
							self:setState({ soundEffectsVolume = newValue })
						end,
					}),
				}),

				-- [CHANGE] Swapped Checkbox for the new Toggle component
				FullScreen = React.createElement("Frame", {
					Name = "FullScreenRow",
					Size = UDim2.new(1, 0, 0, 40),
					BackgroundTransparency = 1,
					LayoutOrder = 5,
				}, {
					Label = React.createElement("TextLabel", {
						Text = "Full Screen",
						Size = UDim2.new(0.8, 0, 1, 0),
						Position = UDim2.fromScale(0, 0.5),
						AnchorPoint = Vector2.new(0, 0.5),
						TextSize = 24,
						FontFace = UIConfig.Font.Default,
						TextColor3 = UIConfig.Color.Primary,
						BackgroundTransparency = 1,
						TextXAlignment = Enum.TextXAlignment.Left,
					}),
					Input = React.createElement(Toggle, {
						Size = UDim2.new(0, 120, 1, 0), -- Set a fixed width for the toggle
						Position = UDim2.fromScale(1, 0.5),
						AnchorPoint = Vector2.new(1, 0.5),
						value = self.state.isFullScreen,
						onValueChanged = function(newValue)
							self:setState({ isFullScreen = newValue })
						end,
					}),
				}),

				-- [CHANGE] Swapped Checkbox for the new Toggle component
				ShowSubtitles = React.createElement("Frame", {
					Name = "ShowSubtitlesRow",
					Size = UDim2.new(1, 0, 0, 40),
					BackgroundTransparency = 1,
					LayoutOrder = 6,
				}, {
					Label = React.createElement("TextLabel", {
						Text = "Show Subtitles",
						Size = UDim2.new(0.8, 0, 1, 0),
						Position = UDim2.fromScale(0, 0.5),
						AnchorPoint = Vector2.new(0, 0.5),
						TextSize = 24,
						FontFace = UIConfig.Font.Default,
						TextColor3 = UIConfig.Color.Primary,
						BackgroundTransparency = 1,
						TextXAlignment = Enum.TextXAlignment.Left,
					}),
					Input = React.createElement(Toggle, {
						Size = UDim2.new(0, 120, 1, 0), -- Set a fixed width for the toggle
						Position = UDim2.fromScale(1, 0.5),
						AnchorPoint = Vector2.new(1, 0.5),
						value = self.state.showSubtitles,
						onValueChanged = function(newValue)
							self:setState({ showSubtitles = newValue })
						end,
					}),
				}),

				ButtonSpacer = React.createElement("Frame", {
					Name = "ButtonSpacer",
					Size = UDim2.new(1, 0, 0, 30),
					BackgroundTransparency = 1,
					LayoutOrder = 7,
				}),

				BackButton = React.createElement(Button, {
					Name = "BackButton",
					Text = "Back",
					LayoutOrder = 8,
					BackgroundTransparency = 1,
					TextSize = 32,
					Size = UDim2.new(0, 200, 0, 50),
					OnClick = function()
						if navigate then
							navigate("mainMenu")
						end
					end,
				}),
			}),
		}),
	})
end
return Settings
