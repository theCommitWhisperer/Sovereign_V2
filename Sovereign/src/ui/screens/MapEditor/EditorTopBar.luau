--!strict
-- EditorTopBar: Unified top bar with back, map info, tool selection, and file actions
local React = require(game.ReplicatedStorage.Packages.react)
local UIConfig = require(script.Parent.Parent.Parent.UIConfig)

local EditorTopBar = React.Component:extend("EditorTopBar")

local TOOLS = {
	{ id = "Select", label = "Select", order = 1 },
	{ id = "TerrainBrush", label = "Brush", order = 2 },
	{ id = "Eraser", label = "Eraser", order = 3 },
	{ id = "FeaturePlace", label = "Feature", order = 4 },
	{ id = "SpawnZones", label = "Spawns", order = 5 },
	{ id = "Settings", label = "Config", order = 6 },
}

function EditorTopBar:render()
	local mapName = self.props.mapName or "Untitled Map"
	local mapSize = self.props.mapSize or 1000
	local maxPlayers = self.props.maxPlayers or 4
	local activeTool = self.props.activeTool or "Select"
	local onToolSelected = self.props.onToolSelected

	-- Build tool buttons
	local toolsChildren = {
		UIListLayout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 4),
		}),
	}
	for _, tool in ipairs(TOOLS) do
		local isActive = activeTool == tool.id
		toolsChildren[tool.id] = React.createElement("TextButton", {
			LayoutOrder = tool.order,
			Size = UDim2.new(0, 64, 0, 32),
			BackgroundColor3 = isActive and Color3.fromRGB(138, 106, 106) or Color3.fromRGB(61, 43, 31),
			BorderSizePixel = 0,
			Text = tool.label,
			FontFace = UIConfig.Font.Default,
			TextColor3 = isActive and Color3.fromRGB(255, 240, 200) or Color3.fromRGB(180, 165, 140),
			TextSize = 11,
			[React.Event.MouseButton1Click] = function()
				if onToolSelected then
					onToolSelected(tool.id)
				end
			end,
		}, {
			UICorner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 4) }),
			UIStroke = isActive and React.createElement("UIStroke", {
				Color = Color3.fromRGB(218, 165, 32),
				Thickness = 1.5,
			}) or nil,
		})
	end

	return React.createElement("Frame", {
		Name = "EditorTopBar",
		Size = UDim2.new(1, 0, 0, 44),
		BackgroundColor3 = Color3.fromRGB(90, 78, 78),
		BorderSizePixel = 0,
		ZIndex = 10,
	}, {
		UIStroke = React.createElement("UIStroke", {
			Color = Color3.fromRGB(199, 166, 122),
			Thickness = 2,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),

		-- Left section: Back + Map info + Tools (uses UIListLayout)
		LeftSection = React.createElement("Frame", {
			Size = UDim2.new(1, -160, 1, 0),
			BackgroundTransparency = 1,
		}, {
			UIPadding = React.createElement("UIPadding", {
				PaddingLeft = UDim.new(0, 8),
				PaddingTop = UDim.new(0, 5),
				PaddingBottom = UDim.new(0, 5),
			}),
			UIListLayout = React.createElement("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, 6),
			}),

			-- Back button
			BackButton = React.createElement("TextButton", {
				LayoutOrder = 1,
				Size = UDim2.new(0, 40, 0, 32),
				BackgroundColor3 = Color3.fromRGB(120, 70, 65),
				BorderSizePixel = 0,
				Text = "<",
				FontFace = UIConfig.Font.Title,
				TextColor3 = Color3.fromRGB(255, 220, 200),
				TextSize = 18,
				[React.Event.MouseButton1Click] = function()
					if self.props.onBack then
						self.props.onBack()
					end
				end,
			}, {
				UICorner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 4) }),
			}),

			-- Separator
			Sep1 = React.createElement("Frame", {
				LayoutOrder = 2,
				Size = UDim2.new(0, 1, 0, 28),
				BackgroundColor3 = Color3.fromRGB(120, 100, 80),
				BorderSizePixel = 0,
			}),

			-- Map name
			MapName = React.createElement("TextLabel", {
				LayoutOrder = 3,
				Size = UDim2.new(0, 120, 1, 0),
				BackgroundTransparency = 1,
				Text = mapName,
				FontFace = UIConfig.Font.Title,
				TextColor3 = Color3.fromRGB(209, 148, 92),
				TextSize = 15,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
			}),

			-- Map info badge
			MapInfo = React.createElement("TextLabel", {
				LayoutOrder = 4,
				Size = UDim2.new(0, 72, 0, 20),
				BackgroundColor3 = Color3.fromRGB(61, 43, 31),
				BorderSizePixel = 0,
				Text = string.format("%dx%d %dP", mapSize, mapSize, maxPlayers),
				FontFace = UIConfig.Font.Default,
				TextColor3 = Color3.fromRGB(160, 145, 120),
				TextSize = 9,
			}, {
				UICorner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 3) }),
			}),

			-- Separator
			Sep2 = React.createElement("Frame", {
				LayoutOrder = 5,
				Size = UDim2.new(0, 1, 0, 28),
				BackgroundColor3 = Color3.fromRGB(120, 100, 80),
				BorderSizePixel = 0,
			}),

			-- Tools
			ToolsGroup = React.createElement("Frame", {
				LayoutOrder = 6,
				Size = UDim2.new(0, 412, 0, 32),
				BackgroundTransparency = 1,
			}, toolsChildren),
		}),

		-- Right section: File actions (absolutely positioned to right edge)
		RightSection = React.createElement("Frame", {
			Size = UDim2.new(0, 150, 1, 0),
			Position = UDim2.new(1, 0, 0, 0),
			AnchorPoint = Vector2.new(1, 0),
			BackgroundTransparency = 1,
		}, {
			UIPadding = React.createElement("UIPadding", {
				PaddingRight = UDim.new(0, 8),
				PaddingTop = UDim.new(0, 7),
				PaddingBottom = UDim.new(0, 7),
			}),
			UIListLayout = React.createElement("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				HorizontalAlignment = Enum.HorizontalAlignment.Right,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, 4),
			}),

			SaveButton = React.createElement("TextButton", {
				LayoutOrder = 1,
				Size = UDim2.new(0, 44, 0, 28),
				BackgroundColor3 = Color3.fromRGB(76, 62, 62),
				BorderSizePixel = 0,
				Text = "Save",
				FontFace = UIConfig.Font.Default,
				TextColor3 = Color3.fromRGB(140, 210, 140),
				TextSize = 11,
				[React.Event.MouseButton1Click] = function()
					if self.props.onSave then
						self.props.onSave()
					end
				end,
			}, {
				UICorner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 4) }),
			}),

			LoadButton = React.createElement("TextButton", {
				LayoutOrder = 2,
				Size = UDim2.new(0, 44, 0, 28),
				BackgroundColor3 = Color3.fromRGB(76, 62, 62),
				BorderSizePixel = 0,
				Text = "Load",
				FontFace = UIConfig.Font.Default,
				TextColor3 = Color3.fromRGB(199, 166, 122),
				TextSize = 11,
				[React.Event.MouseButton1Click] = function()
					if self.props.onLoad then
						self.props.onLoad()
					end
				end,
			}, {
				UICorner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 4) }),
			}),

			ExportButton = React.createElement("TextButton", {
				LayoutOrder = 3,
				Size = UDim2.new(0, 50, 0, 28),
				BackgroundColor3 = Color3.fromRGB(76, 62, 62),
				BorderSizePixel = 0,
				Text = "Export",
				FontFace = UIConfig.Font.Default,
				TextColor3 = Color3.fromRGB(199, 166, 122),
				TextSize = 11,
				[React.Event.MouseButton1Click] = function()
					if self.props.onExport then
						self.props.onExport()
					end
				end,
			}, {
				UICorner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 4) }),
			}),
		}),
	})
end

return EditorTopBar
