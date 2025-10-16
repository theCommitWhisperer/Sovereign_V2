local React = require(game.ReplicatedStorage.Packages.react)
local Checkbox = require(script.Parent.Checkbox)
local Textbox = require(script.Parent.Textbox)
local Button = require(script.Parent.Button)

local SettingsPage = React.Component:extend("SettingsPage")

function SettingsPage:render()
	return React.createElement("Frame", {
		Name = "SettingsPage",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
	}, {
		BackgroundImage = React.createElement("ImageLabel", {
			Name = "BackgroundImage",
			Size = UDim2.fromScale(1, 1),
			Image = "rbxassetid://97541657322605",
			ScaleType = Enum.ScaleType.Fit,
		}),
		ContentFrame = React.createElement("Frame", {
			Name = "ContentFrame",
			Size = UDim2.new(0.3, 0, 0.5, 0),
			Position = UDim2.new(0.5, 0, 0.5, 0),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, {
			Title = React.createElement("TextLabel", {
				Text = "Settings",
				Size = UDim2.new(1, 0, 0.2, 0),
				Position = UDim2.new(0.5, 0, 0.1, 0),
				AnchorPoint = Vector2.new(0.5, 0),
				TextSize = 48,
				Font = Enum.Font.Merriweather,
				BackgroundTransparency = 1,
				TextColor3 = Color3.new(0, 0, 0),
			}),
			MusicVolume = React.createElement(Textbox, {
				Label = "Music Volume:",
				defaultText = "100",
				Position = UDim2.new(0.5, 0, 0.3, 0),
				Size = UDim2.new(0.8, 0, 0.1, 0),
				AnchorPoint = Vector2.new(0.5, 0),
			}),
			SoundEffectsVolume = React.createElement(Textbox, {
				Label = "Sound Effects Volume:",
				defaultText = "100",
				Position = UDim2.new(0.5, 0, 0.45, 0),
				Size = UDim2.new(0.8, 0, 0.1, 0),
				AnchorPoint = Vector2.new(0.5, 0),
			}),
			FullScreen = React.createElement(Checkbox, {
				Text = "Full Screen",
				defaultChecked = true,
				Position = UDim2.new(0.5, 0, 0.6, 0),
				Size = UDim2.new(0.8, 0, 0.1, 0),
				AnchorPoint = Vector2.new(0.5, 0),
			}),
			ShowSubtitles = React.createElement(Checkbox, {
				Text = "Show Subtitles",
				defaultChecked = false,
				Position = UDim2.new(0.5, 0, 0.75, 0),
				Size = UDim2.new(0.8, 0, 0.1, 0),
				AnchorPoint = Vector2.new(0.5, 0),
			}),
			BackButton = React.createElement(Button, {
				Name = "BackButton",
				Text = "Back",
				Position = UDim2.new(0.5, 0, 0.9, 0),
				Size = UDim2.new(0.4, 0, 0.1, 0),
				AnchorPoint = Vector2.new(0.5, 0),
				OnClick = self.props.OnBack,
			}),
		}),
	})
end

return SettingsPage
