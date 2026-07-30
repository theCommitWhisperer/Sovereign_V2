-- A reusable panel component for consistent UI containers.
local React = require(game.ReplicatedStorage.Packages.react)
local UIConfig = require(script.Parent.Parent.UIConfig)
local MedievalCorners = require(script.Parent.MedievalCorners)

local Panel = React.Component:extend("Panel")

function Panel:render()
	local props = {}
	local children = {}

	-- Copy all props except medieval and children
	for key, value in pairs(self.props) do
		if key ~= "medieval" and type(key) == "string" then
			props[key] = value
		end
	end

	-- Add medieval styling if requested
	if self.props.medieval then
		props.BorderSizePixel = 0

		-- Add border stroke
		children.Border = React.createElement("UIStroke", {
			Color = UIConfig.HUD.StrokeColor,
			Thickness = UIConfig.HUD.BorderThickness,
		})

		-- Add corner decorations
		children.Corners = React.createElement(MedievalCorners, {
			size = 12,
			color = UIConfig.HUD.AccentGold,
			thickness = 2,
		})
	end

	-- Merge in any existing children
	if self.props[React.Children] then
		for key, value in pairs(self.props[React.Children]) do
			children[key] = value
		end
	end

	return React.createElement("Frame", props, children)
end

return Panel
