-- The keybindings screen where players can remap controls.
local React = require(game.ReplicatedStorage.Packages.react)
local UIConfig = require(script.Parent.Parent.Parent.UIConfig)
local Button = require(script.Parent.Parent.Parent.components.Button)

local Keybindings = React.Component:extend("Keybindings")

function Keybindings:render()
	local navigate = self.props.navigate
	return React.createElement("ScreenGui", {}, {
		Container = React.createElement("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 0.5,
			BackgroundColor3 = UIConfig.Color.Background,
		}, {
			Layout = React.createElement("UIListLayout", {
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 20),
			}),
			Title = React.createElement("TextLabel", {
				Text = "Keybindings",
				Size = UDim2.new(0, 400, 0, 60),
				FontFace = UIConfig.Font.Title,
				TextColor3 = UIConfig.Color.Primary,
				TextSize = 48,
				BackgroundTransparency = 1,
			}),
			ComingSoon = React.createElement("TextLabel", {
				Text = "(Coming Soon)",
				Size = UDim2.new(0, 400, 0, 30),
				FontFace = UIConfig.Font.Default,
				TextColor3 = UIConfig.Color.Primary,
				TextSize = 24,
				BackgroundTransparency = 1,
			}),
			BackButton = React.createElement(Button, {
				Text = "Back",
				OnClick = function()
					if navigate then
						navigate("settings")
					end
				end,
			}),
		}),
	})
end

return Keybindings
