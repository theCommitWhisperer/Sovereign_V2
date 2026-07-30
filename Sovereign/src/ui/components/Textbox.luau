-- src/ui/components/Textbox.luau
local React = require(game.ReplicatedStorage.Packages.react)
local UIConfig = require(script.Parent.Parent.UIConfig)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)
local channel = DebugManager.newChannel("Textbox", "info")

local Textbox = React.Component:extend("Textbox")

function Textbox:render()
	channel:info("Component Log: Textbox.luau is rendering.")

	local props = {
		Size = UDim2.new(1, 0, 1, 0),
		Text = self.props.Text or "",
		TextSize = 24,
		Font = Enum.Font.SourceSans,
		TextColor3 = UIConfig.Color.Primary,
		BackgroundColor3 = UIConfig.Color.Secondary,
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		[React.Event.FocusLost] = function(rbx)
			if self.props.onTextChanged then
				self.props.onTextChanged(rbx.Text)
			end
		end,
	}

	-- [FIX] Filter out our custom props before passing them to the TextBox
	for key, value in pairs(self.props) do
		if key ~= "onTextChanged" and key ~= "defaultText" then
			props[key] = value
		end
	end

	return React.createElement("TextBox", props)
end

return Textbox