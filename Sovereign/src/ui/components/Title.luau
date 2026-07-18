local React = require(game.ReplicatedStorage.Packages.react)
local UIConfig = require(script.Parent.Parent.UIConfig)
local Title = React.Component:extend("Title")

-- List of props that should NEVER be passed to TextLabel
local FORBIDDEN_PROPS = {
	Padding = true,
	FontFace = true,
	[React.Children] = true,
	ref = true,
}

function Title:render()
	-- Start with default props
	local props = {
		Name = "Title",
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

	-- Create children array
	local children = {}

	-- Copy existing children if any
	local originalChildren = self.props[React.Children]
	if originalChildren and type(originalChildren) == "table" then
		for i, child in ipairs(originalChildren) do
			children[i] = child
		end
	end

	-- Handle Padding specially - convert to UIPadding child
	if self.props.Padding and typeof(self.props.Padding) == "UDim" then
		local paddingValue = self.props.Padding
		table.insert(children, React.createElement("UIPadding", {
			PaddingLeft = paddingValue,
			PaddingRight = paddingValue,
			PaddingTop = paddingValue,
			PaddingBottom = paddingValue,
		}))
	end

	-- Merge user props, but filter out forbidden ones
	for k, v in pairs(self.props) do
		if not FORBIDDEN_PROPS[k] then
			props[k] = v
		end
	end

	-- Triple-check: make absolutely sure Padding doesn't exist
	props.Padding = nil

	-- Return TextLabel with or without children
	if #children > 0 then
		return React.createElement("TextLabel", props, children)
	else
		return React.createElement("TextLabel", props)
	end
end

return Title
