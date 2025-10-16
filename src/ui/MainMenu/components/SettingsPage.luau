local React = require(game.ReplicatedStorage.Packages.react)
local UIConfig = require(script.Parent.Parent.Parent.UIConfig)
local Checkbox = require(script.Parent.Checkbox)
local Textbox = require(script.Parent.Textbox)
local Button = require(script.Parent.Button)

local SettingsPage = React.Component:extend("SettingsPage")

function SettingsPage:render()
	return React.createElement("Frame", {
		Name = "SettingsPage",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
		ZIndex = 1,
	}, {
		ScrollImage = React.createElement("ImageLabel", {
			Name = "ScrollImage",
			Size = UDim2.new(0.5, 0, 0.85, 0),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Image = "rbxassetid://97541657322605",
			ScaleType = Enum.ScaleType.Stretch,
			BackgroundTransparency = 1,
			ZIndex = 2,
		}, {
			ContentFrame = React.createElement("ScrollingFrame", {
				Name = "ContentFrame",
				Size = UDim2.fromScale(1, 1),
				Position = UDim2.fromScale(0.5, 0.5),
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				CanvasSize = UDim2.new(), -- Let UIListLayout control this
				ScrollBarImageColor3 = Color3.new(0, 0, 0),
			}, {
				Padding = React.createElement("UIPadding", {
					PaddingTop = UDim.new(0.25, 0),
					PaddingBottom = UDim.new(0.25, 0),
					PaddingLeft = UDim.new(0.25, 0),
					PaddingRight = UDim.new(0.25, 0),
				}),
				InnerFrame = React.createElement("Frame", {
					Name = "InnerFrame",
					Size = UDim2.fromScale(1, 1),
					BackgroundTransparency = 1,
				}, {
					Layout = React.createElement("UIListLayout", {
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, 15),
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
					MusicVolume = React.createElement(Textbox, {
						Label = "Music Volume:",
						defaultText = "100",
						LayoutOrder = 2,
						Size = UDim2.new(1, 0, 0, 40),
					}),
					SoundEffectsVolume = React.createElement(Textbox, {
						Label = "Sound Effects Volume:",
						defaultText = "100",
						LayoutOrder = 3,
						Size = UDim2.new(1, 0, 0, 40),
					}),
					FullScreen = React.createElement(Checkbox, {
						Text = "Full Screen",
						defaultChecked = true,
						LayoutOrder = 4,
						Size = UDim2.new(1, 0, 0, 30),
					}),
					ShowSubtitles = React.createElement(Checkbox, {
						Text = "Show Subtitles",
						defaultChecked = false,
						LayoutOrder = 5,
						Size = UDim2.new(1, 0, 0, 30),
					}),
					BackButton = React.createElement(Button, {
						Name = "BackButton",
						Text = "Back",
						LayoutOrder = 6,
						Size = UDim2.new(0.6, 0, 0, 50),
						OnClick = self.props.OnBack,
					}),
				}),
			}),
		}),
	})
end

return SettingsPage
