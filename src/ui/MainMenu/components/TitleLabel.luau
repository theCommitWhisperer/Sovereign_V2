local React = require(game.ReplicatedStorage.Packages.react)
local UIConfig = require(script.Parent.Parent.Parent.UIConfig)

local TitleLabel = React.Component:extend("TitleLabel")

function TitleLabel:render()
	local props = {
		Name = "TitleLabel",
		Text = "Sovereign",
		FontFace = UIConfig.getFont(self.props.FontFace, UIConfig.Font.Title),
		TextSize = 64,
		TextColor3 = UIConfig.Color.Primary,
		TextStrokeTransparency = 0,
		Size = UIConfig.Size.Title,
		Position = UDim2.new(0.5, 0, 0.2, 0),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Center,
	}

	for k, v in pairs(self.props) do
		if k ~= "FontFace" then
			props[k] = v
		end
	end

	return React.createElement("TextLabel", props)
end

return TitleLabel