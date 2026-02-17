--!strict
-- EditorPropertyPanel: Context-sensitive left panel for map editor
-- Positioned below the top bar on the left side
local React = require(game.ReplicatedStorage.Packages.react)
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIConfig = require(script.Parent.Parent.Parent.UIConfig)
local TerrainPalette = require(script.Parent.TerrainPalette)

local EditorPropertyPanel = React.Component:extend("EditorPropertyPanel")

-- Slider component
local function createSlider(props: {
	label: string,
	value: number,
	min: number,
	max: number,
	step: number?,
	layoutOrder: number,
	onChange: (number) -> (),
})
	local fraction = math.clamp((props.value - props.min) / (props.max - props.min), 0, 1)
	local step = props.step or 1
	local displayValue = math.floor(props.value / step) * step

	return React.createElement("Frame", {
		LayoutOrder = props.layoutOrder,
		Size = UDim2.new(1, 0, 0, 36),
		BackgroundTransparency = 1,
	}, {
		Label = React.createElement("TextLabel", {
			Size = UDim2.new(0.6, 0, 0, 14),
			BackgroundTransparency = 1,
			Text = props.label,
			FontFace = UIConfig.Font.Default,
			TextColor3 = Color3.fromRGB(199, 166, 122),
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		Value = React.createElement("TextLabel", {
			Size = UDim2.new(0.4, 0, 0, 14),
			BackgroundTransparency = 1,
			Text = tostring(displayValue),
			FontFace = UIConfig.Font.Default,
			TextColor3 = Color3.fromRGB(209, 148, 92),
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Right,
		}),
		SliderTrack = React.createElement("Frame", {
			Size = UDim2.new(1, 0, 0, 6),
			Position = UDim2.new(0, 0, 0, 18),
			BackgroundColor3 = Color3.fromRGB(61, 43, 31),
			BorderSizePixel = 0,
		}, {
			UICorner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 3) }),
			Fill = React.createElement("Frame", {
				Size = UDim2.new(fraction, 0, 1, 0),
				BackgroundColor3 = Color3.fromRGB(209, 148, 92),
				BorderSizePixel = 0,
			}, {
				UICorner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 3) }),
			}),
		}),
		MinusButton = React.createElement("TextButton", {
			Size = UDim2.new(0.5, 0, 0, 14),
			Position = UDim2.new(0, 0, 0, 16),
			BackgroundTransparency = 1,
			Text = "",
			[React.Event.MouseButton1Click] = function()
				local newVal = math.clamp(props.value - step, props.min, props.max)
				props.onChange(newVal)
			end,
		}),
		PlusButton = React.createElement("TextButton", {
			Size = UDim2.new(0.5, 0, 0, 14),
			Position = UDim2.new(0.5, 0, 0, 16),
			BackgroundTransparency = 1,
			Text = "",
			[React.Event.MouseButton1Click] = function()
				local newVal = math.clamp(props.value + step, props.min, props.max)
				props.onChange(newVal)
			end,
		}),
	})
end

-- Toggle button group
local function createToggle(props: {
	label: string,
	options: { string },
	selected: string,
	layoutOrder: number,
	onChange: (string) -> (),
})
	local toggleButtons = {
		UIListLayout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 4),
		}),
	}

	for i, option in ipairs(props.options) do
		local isSelected = props.selected == option
		toggleButtons[option] = React.createElement("TextButton", {
			LayoutOrder = i,
			Size = UDim2.new(0, 60, 0, 22),
			BackgroundColor3 = isSelected and Color3.fromRGB(138, 106, 106) or Color3.fromRGB(61, 43, 31),
			BorderSizePixel = 0,
			Text = option,
			FontFace = UIConfig.Font.Default,
			TextColor3 = isSelected and Color3.fromRGB(255, 240, 200) or Color3.fromRGB(180, 165, 140),
			TextSize = 10,
			[React.Event.MouseButton1Click] = function()
				props.onChange(option)
			end,
		}, {
			UICorner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 4) }),
			UIStroke = isSelected and React.createElement("UIStroke", {
				Color = Color3.fromRGB(209, 148, 92),
				Thickness = 1,
			}) or nil,
		})
	end

	return React.createElement("Frame", {
		LayoutOrder = props.layoutOrder,
		Size = UDim2.new(1, 0, 0, 38),
		BackgroundTransparency = 1,
	}, {
		Label = React.createElement("TextLabel", {
			Size = UDim2.new(1, 0, 0, 14),
			BackgroundTransparency = 1,
			Text = props.label,
			FontFace = UIConfig.Font.Default,
			TextColor3 = Color3.fromRGB(199, 166, 122),
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		Buttons = React.createElement("Frame", {
			Size = UDim2.new(1, 0, 0, 22),
			Position = UDim2.new(0, 0, 0, 16),
			BackgroundTransparency = 1,
		}, toggleButtons),
	})
end

function EditorPropertyPanel:init()
	self:setState({
		brushRadius = 20,
		brushHeight = 10,
		brushShape = "Block",
		selectedMaterial = "Grass",
	})
end

function EditorPropertyPanel:render()
	local activeTool = self.props.activeTool or "Select"
	local onBrushSettingsChanged = self.props.onBrushSettingsChanged

	local function notifyBrushChange(overrides: { [string]: any }?)
		if onBrushSettingsChanged then
			local settings = {
				radius = if overrides and overrides.radius then overrides.radius else self.state.brushRadius,
				height = if overrides and overrides.height then overrides.height else self.state.brushHeight,
				shape = if overrides and overrides.shape then overrides.shape else self.state.brushShape,
				material = if overrides and overrides.material then overrides.material else self.state.selectedMaterial,
			}
			onBrushSettingsChanged(settings)
		end
	end

	local content = {}

	-- Tool-specific controls
	if activeTool == "TerrainBrush" or activeTool == "Eraser" then
		if activeTool == "TerrainBrush" then
			content.MaterialLabel = React.createElement("TextLabel", {
				LayoutOrder = 1,
				Size = UDim2.new(1, 0, 0, 16),
				BackgroundTransparency = 1,
				Text = "Material",
				FontFace = UIConfig.Font.Default,
				TextColor3 = Color3.fromRGB(209, 148, 92),
				TextSize = 12,
				TextXAlignment = Enum.TextXAlignment.Left,
			})

			content.Palette = React.createElement(TerrainPalette, {
				LayoutOrder = 2,
				selectedMaterial = self.state.selectedMaterial,
				onMaterialSelected = function(material)
					self:setState({ selectedMaterial = material })
					notifyBrushChange({ material = material })
				end,
			})
		end

		content.BrushSize = createSlider({
			label = "Brush Size",
			value = self.state.brushRadius,
			min = 5,
			max = 100,
			step = 5,
			layoutOrder = 3,
			onChange = function(val)
				self:setState({ brushRadius = val })
				notifyBrushChange({ radius = val })
			end,
		})

		content.BrushHeight = createSlider({
			label = "Height",
			value = self.state.brushHeight,
			min = 2,
			max = 50,
			step = 2,
			layoutOrder = 4,
			onChange = function(val)
				self:setState({ brushHeight = val })
				notifyBrushChange({ height = val })
			end,
		})

		content.BrushShape = createToggle({
			label = "Shape",
			options = { "Block", "Ball" },
			selected = self.state.brushShape,
			layoutOrder = 5,
			onChange = function(shape)
				self:setState({ brushShape = shape })
				notifyBrushChange({ shape = shape })
			end,
		})
	elseif activeTool == "Select" then
		content.Hint = React.createElement("TextLabel", {
			LayoutOrder = 1,
			Size = UDim2.new(1, 0, 0, 50),
			BackgroundTransparency = 1,
			Text = "Click to select.\nDrag to move.\nDelete to remove.",
			FontFace = UIConfig.Font.Default,
			TextColor3 = Color3.fromRGB(160, 145, 120),
			TextSize = 10,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
		})
	elseif activeTool == "FeaturePlace" then
		content.Hint = React.createElement("TextLabel", {
			LayoutOrder = 1,
			Size = UDim2.new(1, 0, 0, 30),
			BackgroundTransparency = 1,
			Text = "Click to place features.",
			FontFace = UIConfig.Font.Default,
			TextColor3 = Color3.fromRGB(160, 145, 120),
			TextSize = 10,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
		})
	elseif activeTool == "SpawnZones" then
		content.Hint = React.createElement("TextLabel", {
			LayoutOrder = 1,
			Size = UDim2.new(1, 0, 0, 30),
			BackgroundTransparency = 1,
			Text = "Drag to place spawn zones.",
			FontFace = UIConfig.Font.Default,
			TextColor3 = Color3.fromRGB(160, 145, 120),
			TextSize = 10,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
		})
	elseif activeTool == "Settings" then
		content.Hint = React.createElement("TextLabel", {
			LayoutOrder = 1,
			Size = UDim2.new(1, 0, 0, 30),
			BackgroundTransparency = 1,
			Text = "Map settings (Phase 4).",
			FontFace = UIConfig.Font.Default,
			TextColor3 = Color3.fromRGB(160, 145, 120),
			TextSize = 10,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
		})
	end

	content.UIListLayout = React.createElement("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 4),
	})

	return React.createElement("Frame", {
		Name = "PropertyPanel",
		Size = UDim2.new(0, 200, 0, 300),
		Position = UDim2.new(0, 0, 0, 46),
		BackgroundColor3 = Color3.fromRGB(76, 62, 62),
		BackgroundTransparency = 0.05,
		BorderSizePixel = 0,
		ZIndex = 10,
	}, {
		UIStroke = React.createElement("UIStroke", {
			Color = Color3.fromRGB(140, 115, 85),
			Thickness = 1,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
		UICorner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 0) }),
		UIPadding = React.createElement("UIPadding", {
			PaddingTop = UDim.new(0, 8),
			PaddingLeft = UDim.new(0, 8),
			PaddingRight = UDim.new(0, 8),
			PaddingBottom = UDim.new(0, 8),
		}),
		Content = React.createElement("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
		}, content),
	})
end

return EditorPropertyPanel
