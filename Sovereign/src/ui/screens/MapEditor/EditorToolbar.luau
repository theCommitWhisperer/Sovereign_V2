--!strict
-- EditorToolbar: Left-side vertical toolbar for map editor tool selection
local React = require(game.ReplicatedStorage.Packages.react)
local UIConfig = require(script.Parent.Parent.Parent.UIConfig)

local EditorToolbar = React.Component:extend("EditorToolbar")

local TOOLS = {
	{ id = "Select", label = "Select", icon = "S", order = 1 },
	{ id = "TerrainBrush", label = "Brush", icon = "B", order = 2 },
	{ id = "Eraser", label = "Eraser", icon = "E", order = 3 },
	{ id = "FeaturePlace", label = "Feature", icon = "F", order = 4 },
	{ id = "SpawnZones", label = "Spawns", icon = "Z", order = 5 },
	{ id = "Settings", label = "Config", icon = "C", order = 6 },
}

function EditorToolbar:render()
	local activeTool = self.props.activeTool or "Select"
	local onToolSelected = self.props.onToolSelected

	local toolButtons = {
		UIListLayout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 6),
		}),
		UIPadding = React.createElement("UIPadding", {
			PaddingTop = UDim.new(0, 10),
			PaddingBottom = UDim.new(0, 8),
			PaddingLeft = UDim.new(0, 6),
			PaddingRight = UDim.new(0, 6),
		}),
	}

	for _, tool in ipairs(TOOLS) do
		local isActive = activeTool == tool.id
		local bgColor = isActive and Color3.fromRGB(138, 106, 106) or Color3.fromRGB(76, 62, 62)
		local textColor = isActive and Color3.fromRGB(209, 148, 92) or Color3.fromRGB(199, 166, 122)

		toolButtons[tool.id] = React.createElement("TextButton", {
			LayoutOrder = tool.order,
			Size = UDim2.new(1, 0, 0, 52),
			BackgroundColor3 = bgColor,
			BorderSizePixel = 0,
			Text = "",
			[React.Event.MouseButton1Click] = function()
				if onToolSelected then
					onToolSelected(tool.id)
				end
			end,
		}, {
			UICorner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 6) }),
			UIStroke = isActive and React.createElement("UIStroke", {
				Color = Color3.fromRGB(218, 165, 32),
				Thickness = 2,
			}) or React.createElement("UIStroke", {
				Color = Color3.fromRGB(199, 166, 122),
				Thickness = 1,
			}),
			Icon = React.createElement("TextLabel", {
				Size = UDim2.new(1, 0, 0, 28),
				Position = UDim2.new(0, 0, 0, 4),
				BackgroundTransparency = 1,
				Text = tool.icon,
				FontFace = UIConfig.Font.Title,
				TextColor3 = textColor,
				TextSize = 20,
			}),
			Label = React.createElement("TextLabel", {
				Size = UDim2.new(1, 0, 0, 14),
				Position = UDim2.new(0, 0, 1, -16),
				BackgroundTransparency = 1,
				Text = tool.label,
				FontFace = UIConfig.Font.Default,
				TextColor3 = textColor,
				TextSize = 10,
			}),
		})
	end

	return React.createElement("Frame", {
		Name = "EditorToolbar",
		Size = UDim2.new(0, 64, 1, -44),
		Position = UDim2.new(0, 0, 0, 44),
		BackgroundColor3 = Color3.fromRGB(90, 78, 78),
		BorderSizePixel = 0,
		ZIndex = 10,
	}, {
		UIStroke = React.createElement("UIStroke", {
			Color = Color3.fromRGB(199, 166, 122),
			Thickness = 2,
		}),
		Content = React.createElement("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
		}, toolButtons),
	})
end

return EditorToolbar
