-- src/ui/components/Checkbox.luau
local React = require(game.ReplicatedStorage.Packages.react)
local UIConfig = require(script.Parent.Parent.UIConfig)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)
local channel = DebugManager.newChannel("Checkbox", "info")

local Checkbox = React.Component:extend("Checkbox")

function Checkbox:render()
	channel:info("Component Log: Checkbox.luau is rendering.")

	local props = {
		Size = UDim2.fromOffset(24, 24),
		Position = UDim2.fromScale(0, 0.5),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		[React.Event.MouseButton1Click] = function()
			if self.props.onValueChanged then
				self.props.onValueChanged(not self.props.checked)
			end
		end,
	}

	-- [FIX] Filter out our custom props before passing them to the TextButton
	for key, value in pairs(self.props) do
		if key ~= "checked" and key ~= "onValueChanged" then
			props[key] = value
		end
	end

	return React.createElement("TextButton", props, {
		Box = React.createElement("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = UIConfig.Color.Secondary,
			BorderSizePixel = 0,
		}, {
			Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 4) }),
			Check = self.props.checked and React.createElement("Frame", {
				Size = UDim2.new(0.7, 0, 0.7, 0),
				Position = UDim2.new(0.5, 0, 0.5, 0),
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = UIConfig.Color.Primary,
			}) or nil,
		}),
	})
end

return Checkbox