-- src/ui/screens/Settings/Settings.luau

local React = require(game.ReplicatedStorage.Packages.react)
local components = script.Parent.Parent.Parent.components
local UIConfig = require(script.Parent.Parent.Parent.UIConfig)
local Button = require(components.Button)
local Slider = require(components.Slider)
local Toggle = require(components.Toggle)

local Settings = React.Component:extend("Settings")

function Settings:init()
	self:setState({
		masterVolume = 100,
		musicVolume = 100,
		soundEffectsVolume = 100,
		isFullScreen = true,
		showSubtitles = false,
		showUnitHealthBars = "Always",
		scrollbarVisible = false,
	})
	self.lastScrollTime = 0
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
				Size = UDim2.new(0.5, 0, 0.15, 0),
				Position = UDim2.fromScale(0.5, 0.086),
				AnchorPoint = Vector2.new(0.5, 0),
				BackgroundTransparency = 1,
			}, {
				Title = React.createElement("TextLabel", {
					Text = "Settings",
					Size = UDim2.fromScale(1, 1),
					TextSize = 42,
					FontFace = UIConfig.Font.Title,
					BackgroundTransparency = 1,
					TextColor3 = UIConfig.Color.Primary,
				}),
			}),

			ContentFrame = React.createElement("ScrollingFrame", {
				Name = "ContentFrame",
				Size = UDim2.new(0.5, 0, 0.55, 0),
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
				-- [FIX] Using a UIPadding object to create space for the tooltip
				Padding = React.createElement("UIPadding", {
					PaddingTop = UDim.new(0, 30),
				}),
				Layout = React.createElement("UIListLayout", {
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 15), -- This now only controls space between items
					HorizontalAlignment = Enum.HorizontalAlignment.Center,
				}),

				Keybindings = React.createElement("Frame", {
					Name = "KeybindingsRow",
					Size = UDim2.new(0.8, 0, 0, 40),
					BackgroundTransparency = 1,
					LayoutOrder = 1,
				}, {
					Label = React.createElement("TextLabel", {
						Text = "Keybindings",
						Size = UDim2.new(0.5, 0, 1, 0),
						Position = UDim2.fromScale(0, 0.5),
						AnchorPoint = Vector2.new(0, 0.5),
						TextSize = 28,
						FontFace = UIConfig.Font.Default,
						TextColor3 = UIConfig.Color.Primary,
						BackgroundTransparency = 1,
						TextXAlignment = Enum.TextXAlignment.Left,
					}),
					Input = React.createElement(Button, {
						Name = "KeybindingsButton",
						Text = "Edit",
						TextSize = 28,
						Size = UDim2.new(0, 150, 1, 0),
						Position = UDim2.fromScale(1, 0.5),
						AnchorPoint = Vector2.new(1, 0.5),
						BackgroundTransparency = 1,
						OnClick = function()
							if navigate then
								navigate("keybindings")
							end
						end,
					}),
				}),
				MasterVolume = React.createElement("Frame", {
					Name = "MasterVolumeRow",
					Size = UDim2.new(0.8, 0, 0, 40),
					BackgroundTransparency = 1,
					LayoutOrder = 2,
				}, {
					Label = React.createElement("TextLabel", {
						Text = "Master Volume:",
						Size = UDim2.new(0.5, 0, 1, 0),
						Position = UDim2.fromScale(0, 0.5),
						AnchorPoint = Vector2.new(0, 0.5),
						TextSize = 28,
						FontFace = UIConfig.Font.Default,
						TextColor3 = UIConfig.Color.Primary,
						BackgroundTransparency = 1,
						TextXAlignment = Enum.TextXAlignment.Left,
					}),
					Input = React.createElement(Slider, {
						Size = UDim2.new(0, 200, 0, 4),
						Position = UDim2.fromScale(1, 0.5),
						AnchorPoint = Vector2.new(1, 0.5),
						min = 0,
						max = 100,
						value = self.state.masterVolume,
						onValueChanged = function(newValue)
							self:setState({ masterVolume = newValue })
						end,
					}),
				}),
				MusicVolume = React.createElement("Frame", {
					Name = "MusicVolumeRow",
					Size = UDim2.new(0.8, 0, 0, 40),
					BackgroundTransparency = 1,
					LayoutOrder = 3,
				}, {
					Label = React.createElement("TextLabel", {
						Text = "Music Volume:",
						Size = UDim2.new(0.5, 0, 1, 0),
						Position = UDim2.fromScale(0, 0.5),
						AnchorPoint = Vector2.new(0, 0.5),
						TextSize = 28,
						FontFace = UIConfig.Font.Default,
						TextColor3 = UIConfig.Color.Primary,
						BackgroundTransparency = 1,
						TextXAlignment = Enum.TextXAlignment.Left,
					}),
					Input = React.createElement(Slider, {
						Size = UDim2.new(0, 200, 0, 4),
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
					Size = UDim2.new(0.8, 0, 0, 40),
					BackgroundTransparency = 1,
					LayoutOrder = 4,
				}, {
					Label = React.createElement("TextLabel", {
						Text = "Sound Effects Volume:",
						Size = UDim2.new(0.5, 0, 1, 0),
						Position = UDim2.fromScale(0, 0.5),
						AnchorPoint = Vector2.new(0, 0.5),
						TextSize = 28,
						FontFace = UIConfig.Font.Default,
						TextColor3 = UIConfig.Color.Primary,
						BackgroundTransparency = 1,
						TextXAlignment = Enum.TextXAlignment.Left,
					}),
					Input = React.createElement(Slider, {
						Size = UDim2.new(0, 200, 0, 4),
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
				FullScreen = React.createElement("Frame", {
					Name = "FullScreenRow",
					Size = UDim2.new(0.8, 0, 0, 40),
					BackgroundTransparency = 1,
					LayoutOrder = 5,
				}, {
					Label = React.createElement("TextLabel", {
						Text = "Full Screen",
						Size = UDim2.new(0.5, 0, 1, 0),
						Position = UDim2.fromScale(0, 0.5),
						AnchorPoint = Vector2.new(0, 0.5),
						TextSize = 28,
						FontFace = UIConfig.Font.Default,
						TextColor3 = UIConfig.Color.Primary,
						BackgroundTransparency = 1,
						TextXAlignment = Enum.TextXAlignment.Left,
					}),
					Input = React.createElement(Toggle, {
						Size = UDim2.new(0, 150, 1, 0),
						Position = UDim2.fromScale(1, 0.5),
						AnchorPoint = Vector2.new(1, 0.5),
						value = self.state.isFullScreen,
						onValueChanged = function(newValue)
							self:setState({ isFullScreen = newValue })
						end,
					}),
				}),
				ShowSubtitles = React.createElement("Frame", {
					Name = "ShowSubtitlesRow",
					Size = UDim2.new(0.8, 0, 0, 40),
					BackgroundTransparency = 1,
					LayoutOrder = 6,
				}, {
					Label = React.createElement("TextLabel", {
						Text = "Show Subtitles",
						Size = UDim2.new(0.5, 0, 1, 0),
						Position = UDim2.fromScale(0, 0.5),
						AnchorPoint = Vector2.new(0, 0.5),
						TextSize = 28,
						FontFace = UIConfig.Font.Default,
						TextColor3 = UIConfig.Color.Primary,
						BackgroundTransparency = 1,
						TextXAlignment = Enum.TextXAlignment.Left,
					}),
					Input = React.createElement(Toggle, {
						Size = UDim2.new(0, 150, 1, 0),
						Position = UDim2.fromScale(1, 0.5),
						AnchorPoint = Vector2.new(1, 0.5),
						value = self.state.showSubtitles,
						onValueChanged = function(newValue)
							self:setState({ showSubtitles = newValue })
						end,
					}),
				}),
				ShowUnitHealthBars = React.createElement("Frame", {
					Name = "ShowUnitHealthBarsRow",
					Size = UDim2.new(0.8, 0, 0, 40),
					BackgroundTransparency = 1,
					LayoutOrder = 7,
				}, {
					Label = React.createElement("TextLabel", {
						Text = "Show Unit Health Bars",
						Size = UDim2.new(0.5, 0, 1, 0),
						Position = UDim2.fromScale(0, 0.5),
						AnchorPoint = Vector2.new(0, 0.5),
						TextSize = 28,
						FontFace = UIConfig.Font.Default,
						TextColor3 = UIConfig.Color.Primary,
						BackgroundTransparency = 1,
						TextXAlignment = Enum.TextXAlignment.Left,
					}),
					Input = React.createElement(Toggle, {
						Size = UDim2.new(0, 150, 1, 0),
						Position = UDim2.fromScale(1, 0.5),
						AnchorPoint = Vector2.new(1, 0.5),
						value = self.state.showUnitHealthBars,
						onValueChanged = function(newValue)
							local options = { "Always", "When Damaged", "Never" }
							local currentIndex = table.find(options, self.state.showUnitHealthBars) or 1
							local nextIndex = (currentIndex % #options) + 1
							self:setState({ showUnitHealthBars = options[nextIndex] })
						end,
					}),
				}),
			}),

			Footer = React.createElement("Frame", {
				Name = "Footer",
				Size = UDim2.new(0.5, 0, 0.15, 0),
				Position = UDim2.fromScale(0.5, 0.78),
				AnchorPoint = Vector2.new(0.5, 0),
				BackgroundTransparency = 1,
			}, {
				BackButton = React.createElement(Button, {
					Name = "BackButton",
					Text = "Back",
					Size = UDim2.new(0, 200, 0, 50),
					Position = UDim2.fromScale(0.5, 0.5),
					AnchorPoint = Vector2.new(0.5, 0.5),
					BackgroundTransparency = 1,
					TextSize = 32,
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
