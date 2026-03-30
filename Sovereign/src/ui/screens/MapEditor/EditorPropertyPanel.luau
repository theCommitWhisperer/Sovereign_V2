--!strict
-- EditorPropertyPanel: Context-sensitive left panel for map editor
-- Shows sculpt controls (Mode, Size, Strength, Hardness, Shape, Material) for TerrainBrush
local React = require(game.ReplicatedStorage.Packages.react)
local UserInputService = game:GetService("UserInputService")

local Players = game:GetService("Players")
local localPlayer = Players.LocalPlayer

local UIConfig = require(script.Parent.Parent.Parent.UIConfig)
local TerrainPalette = require(script.Parent.TerrainPalette)
local BrushPanel = require(script.Parent.BrushPanel)
local BudgetPanel = require(script.Parent.BudgetPanel)

-- Draggable Slider class component
local Slider = React.Component:extend("Slider")

function Slider:init()
	self:setState({ isDragging = false })
	self.trackRef = React.createRef()
	self.inputMovedConn = nil :: RBXScriptConnection?
	self.inputEndedConn = nil :: RBXScriptConnection?
end

function Slider:willUnmount()
	if self.inputMovedConn then
		self.inputMovedConn:Disconnect()
		self.inputMovedConn = nil
	end
	if self.inputEndedConn then
		self.inputEndedConn:Disconnect()
		self.inputEndedConn = nil
	end
end

local function computeSliderValue(mouseX: number, trackFrame: GuiObject, min: number, max: number, step: number): number
	local trackPos = trackFrame.AbsolutePosition.X
	local trackSize = trackFrame.AbsoluteSize.X
	if trackSize <= 0 then return min end
	local fraction = math.clamp((mouseX - trackPos) / trackSize, 0, 1)
	local raw = min + fraction * (max - min)
	return math.clamp(math.round(raw / step) * step, min, max)
end

function Slider:startDrag(mouseX: number)
	self:setState({ isDragging = true })

	local trackFrame = self.trackRef.current
	if trackFrame then
		local step = self.props.step or 1
		local val = computeSliderValue(mouseX, trackFrame, self.props.min, self.props.max, step)
		self.props.onChange(val)
	end

	-- Track mouse movement globally so dragging off the slider still works
	self.inputMovedConn = UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			local tf = self.trackRef.current
			if tf then
				local step = self.props.step or 1
				local v = computeSliderValue(input.Position.X, tf, self.props.min, self.props.max, step)
				self.props.onChange(v)
			end
		end
	end)

	self.inputEndedConn = UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			self:stopDrag()
		end
	end)
end

function Slider:stopDrag()
	self:setState({ isDragging = false })
	if self.inputMovedConn then
		self.inputMovedConn:Disconnect()
		self.inputMovedConn = nil
	end
	if self.inputEndedConn then
		self.inputEndedConn:Disconnect()
		self.inputEndedConn = nil
	end
end

function Slider:render()
	local props = self.props
	local step = props.step or 1
	local fraction = math.clamp((props.value - props.min) / (props.max - props.min), 0, 1)
	local displayValue = if props.formatValue
		then props.formatValue(props.value)
		else tostring(math.floor(props.value / step) * step)

	return React.createElement("Frame", {
		LayoutOrder = props.layoutOrder,
		Size = UDim2.new(1, 0, 0, 46),
		BackgroundTransparency = 1,
	}, {
		Label = React.createElement("TextLabel", {
			Size = UDim2.new(0.6, 0, 0, 22),
			BackgroundTransparency = 1,
			Text = props.label,
			FontFace = UIConfig.Font.Default,
			TextColor3 = Color3.fromRGB(199, 166, 122),
			TextSize = 18,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		Value = React.createElement("TextLabel", {
			Size = UDim2.new(0.4, 0, 0, 22),
			BackgroundTransparency = 1,
			Text = displayValue,
			FontFace = UIConfig.Font.Default,
			TextColor3 = Color3.fromRGB(209, 148, 92),
			TextSize = 18,
			TextXAlignment = Enum.TextXAlignment.Right,
		}),
		-- Step down button
		MinusBtn = React.createElement("TextButton", {
			Size = UDim2.new(0, 20, 0, 18),
			Position = UDim2.new(0, 0, 0, 26),
			BackgroundColor3 = Color3.fromRGB(61, 43, 31),
			BorderSizePixel = 0,
			Text = "<",
			FontFace = UIConfig.Font.Default,
			TextColor3 = Color3.fromRGB(180, 160, 130),
			TextSize = 14,
			[React.Event.MouseButton1Click] = function()
				local newVal = math.clamp(props.value - step, props.min, props.max)
				props.onChange(newVal)
			end,
		}, {
			UICorner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 2) }),
		}),
		-- Draggable track
		SliderTrack = React.createElement("Frame", {
			ref = self.trackRef,
			Size = UDim2.new(1, -44, 0, 14),
			Position = UDim2.new(0, 22, 0, 28),
			BackgroundColor3 = Color3.fromRGB(61, 43, 31),
			BorderSizePixel = 0,
			[React.Event.InputBegan] = function(_, input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 then
					self:startDrag(input.Position.X)
				end
			end,
		}, {
			UICorner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 7) }),
			Fill = React.createElement("Frame", {
				Size = UDim2.new(fraction, 0, 1, 0),
				BackgroundColor3 = Color3.fromRGB(209, 148, 92),
				BorderSizePixel = 0,
			}, {
				UICorner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 7) }),
			}),
			-- Thumb nub
			Thumb = React.createElement("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(fraction, 0, 0.5, 0),
				Size = UDim2.new(0, 16, 0, 16),
				BackgroundColor3 = Color3.fromRGB(235, 180, 100),
				BorderSizePixel = 0,
				ZIndex = 2,
			}, {
				UICorner = React.createElement("UICorner", { CornerRadius = UDim.new(1, 0) }),
			}),
		}),
		-- Step up button
		PlusBtn = React.createElement("TextButton", {
			Size = UDim2.new(0, 20, 0, 18),
			Position = UDim2.new(1, -20, 0, 26),
			BackgroundColor3 = Color3.fromRGB(61, 43, 31),
			BorderSizePixel = 0,
			Text = ">",
			FontFace = UIConfig.Font.Default,
			TextColor3 = Color3.fromRGB(180, 160, 130),
			TextSize = 14,
			[React.Event.MouseButton1Click] = function()
				local newVal = math.clamp(props.value + step, props.min, props.max)
				props.onChange(newVal)
			end,
		}, {
			UICorner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 2) }),
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
			Padding = UDim.new(0, 3),
		}),
	}

	local buttonWidth = math.floor(204 / #props.options)
	for i, option in ipairs(props.options) do
		local isSelected = props.selected == option
		toggleButtons[option] = React.createElement("TextButton", {
			LayoutOrder = i,
			Size = UDim2.new(0, buttonWidth, 0, 32),
			BackgroundColor3 = isSelected and Color3.fromRGB(155, 120, 120) or Color3.fromRGB(61, 43, 31),
			BorderSizePixel = 0,
			Text = option,
			FontFace = UIConfig.Font.Default,
			TextColor3 = isSelected and Color3.fromRGB(255, 245, 230) or Color3.fromRGB(190, 175, 155),
			TextSize = 16,
			[React.Event.MouseButton1Click] = function()
				props.onChange(option)
			end,
		}, {
			UICorner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 4) }),
		})
	end

	return React.createElement("Frame", {
		LayoutOrder = props.layoutOrder,
		Size = UDim2.new(1, 0, 0, 54),
		BackgroundTransparency = 1,
	}, {
		Label = React.createElement("TextLabel", {
			Size = UDim2.new(1, 0, 0, 20),
			BackgroundTransparency = 1,
			Text = props.label,
			FontFace = UIConfig.Font.Default,
			TextColor3 = Color3.fromRGB(199, 166, 122),
			TextSize = 16,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		Buttons = React.createElement("Frame", {
			Size = UDim2.new(1, 0, 0, 32),
			Position = UDim2.new(0, 0, 0, 22),
			BackgroundTransparency = 1,
		}, toggleButtons),
	})
end

local FEATURE_TYPES = {
	{ id = "Mountain", label = "Mountain", color = { 140, 130, 120 } },
	{ id = "Hill", label = "Hill", color = { 100, 180, 70 } },
	{ id = "Lake", label = "Lake", color = { 50, 120, 200 } },
	{ id = "River", label = "River", color = { 70, 140, 220 } },
	{ id = "Forest", label = "Forest", color = { 40, 120, 30 } },
	{ id = "Rock", label = "Rock", color = { 100, 100, 110 } },
}

local EditorPropertyPanel = React.Component:extend("EditorPropertyPanel")

function EditorPropertyPanel:init()
	self:setState({
		brushRadius = 20,
		brushMode = "Raise",
		brushStrength = 0.5,
		brushHardness = 0.5,
		brushShape = "Circle",
		selectedMaterial = "Grass",
		selectedFeature = "Mountain",
		featureScale = 1.0,
		-- Resources tool
		selectedResource = "Wood",
		resourceBrushRadius = 30,
		resourceDensity = 5,
		-- ZonePaint tool
		selectedZone = 0, -- 0 = Neutral, 1-4 = Players
		zoneBrushRadius = 40,
		zoneBrushShape = "Circle",
		-- KeepSpawn tool
		selectedSpawnZone = 1,
		keepSpawnRadius = 150,
	})
end

function EditorPropertyPanel:render()
	local activeTool = self.props.activeTool or "Select"
	local onBrushSettingsChanged = self.props.onBrushSettingsChanged

	local function notifyBrushChange(overrides: { [string]: any }?)
		if onBrushSettingsChanged then
			local settings = {
				radius = if overrides and overrides.radius then overrides.radius else self.state.brushRadius,
				mode = if overrides and overrides.mode then overrides.mode else self.state.brushMode,
				strength = if overrides and overrides.strength then overrides.strength else self.state.brushStrength,
				hardness = if overrides and overrides.hardness then overrides.hardness else self.state.brushHardness,
				shape = if overrides and overrides.shape then overrides.shape else self.state.brushShape,
				material = if overrides and overrides.material then overrides.material else self.state.selectedMaterial,
			}
			onBrushSettingsChanged(settings)
		end
	end

	local content = {}

	if activeTool == "TerrainBrush" then
		content.ModeToggle = createToggle({
			label = "Mode",
			options = { "Raise", "Lower", "Flatten", "Paint" },
			selected = self.state.brushMode,
			layoutOrder = 1,
			onChange = function(mode)
				self:setState({ brushMode = mode })
				localPlayer:SetAttribute("EditorBrushMode", mode)
				notifyBrushChange({ mode = mode })
			end,
		})

		content.ShapeToggle = createToggle({
			label = "Shape",
			options = { "Circle", "Square" },
			selected = self.state.brushShape,
			layoutOrder = 2,
			onChange = function(shape)
				self:setState({ brushShape = shape })
				localPlayer:SetAttribute("EditorBrushShape", shape)
				notifyBrushChange({ shape = shape })
			end,
		})

		content.BrushSize = React.createElement(Slider, {
			label = "Size",
			value = self.state.brushRadius,
			min = 10,
			max = 200,
			step = 5,
			layoutOrder = 3,
			onChange = function(val)
				self:setState({ brushRadius = val })
				localPlayer:SetAttribute("EditorBrushRadius", val)
				notifyBrushChange({ radius = val })
			end,
		})

		content.StrengthSlider = React.createElement(Slider, {
			label = "Strength",
			value = self.state.brushStrength * 100,
			min = 5,
			max = 100,
			step = 5,
			layoutOrder = 4,
			formatValue = function(v) return tostring(math.floor(v)) .. "%" end,
			onChange = function(val)
				local strength = val / 100
				self:setState({ brushStrength = strength })
				localPlayer:SetAttribute("EditorBrushStrength", strength)
				notifyBrushChange({ strength = strength })
			end,
		})

		content.HardnessSlider = React.createElement(Slider, {
			label = "Hardness",
			value = self.state.brushHardness * 100,
			min = 0,
			max = 100,
			step = 10,
			layoutOrder = 5,
			formatValue = function(v) return tostring(math.floor(v)) .. "%" end,
			onChange = function(val)
				local hardness = val / 100
				self:setState({ brushHardness = hardness })
				localPlayer:SetAttribute("EditorBrushHardness", hardness)
				notifyBrushChange({ hardness = hardness })
			end,
		})

		if self.state.brushMode == "Paint" or self.state.brushMode == "Raise" then
			content.MaterialLabel = React.createElement("TextLabel", {
				LayoutOrder = 6,
				Size = UDim2.new(1, 0, 0, 20),
				BackgroundTransparency = 1,
				Text = "Material",
				FontFace = UIConfig.Font.Default,
				TextColor3 = Color3.fromRGB(209, 148, 92),
				TextSize = 16,
				TextXAlignment = Enum.TextXAlignment.Left,
			})

			content.Palette = React.createElement(TerrainPalette, {
				LayoutOrder = 7,
				selectedMaterial = self.state.selectedMaterial,
				onMaterialSelected = function(material)
					self:setState({ selectedMaterial = material })
					localPlayer:SetAttribute("EditorBrushMaterial", material)
					notifyBrushChange({ material = material })
				end,
			})
		end

	elseif activeTool == "Eraser" then
		content.ShapeToggle = createToggle({
			label = "Shape",
			options = { "Circle", "Square" },
			selected = self.state.brushShape,
			layoutOrder = 1,
			onChange = function(shape)
				self:setState({ brushShape = shape })
				localPlayer:SetAttribute("EditorBrushShape", shape)
			end,
		})

		content.BrushSize = React.createElement(Slider, {
			label = "Size",
			value = self.state.brushRadius,
			min = 10,
			max = 200,
			step = 5,
			layoutOrder = 2,
			onChange = function(val)
				self:setState({ brushRadius = val })
				localPlayer:SetAttribute("EditorBrushRadius", val)
			end,
		})

		content.Hint = React.createElement("TextLabel", {
			LayoutOrder = 3,
			Size = UDim2.new(1, 0, 0, 28),
			BackgroundTransparency = 1,
			Text = "Click to erase terrain.",
			FontFace = UIConfig.Font.Default,
			TextColor3 = Color3.fromRGB(160, 145, 120),
			TextSize = 15,
			TextXAlignment = Enum.TextXAlignment.Left,
		})

	elseif activeTool == "Select" then
		content.Hint = React.createElement("TextLabel", {
			LayoutOrder = 1,
			Size = UDim2.new(1, 0, 0, 90),
			BackgroundTransparency = 1,
			Text = "Click to select.\nDrag to move.\nDelete to remove.\n\nClick a resource disc\nto select it, then\nDelete to erase it.",
			FontFace = UIConfig.Font.Default,
			TextColor3 = Color3.fromRGB(160, 145, 120),
			TextSize = 15,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
		})

	elseif activeTool == "FeaturePlace" then
		content.FeatureLabel = React.createElement("TextLabel", {
			LayoutOrder = 1,
			Size = UDim2.new(1, 0, 0, 20),
			BackgroundTransparency = 1,
			Text = "Feature Type",
			FontFace = UIConfig.Font.Default,
			TextColor3 = Color3.fromRGB(209, 148, 92),
			TextSize = 16,
			TextXAlignment = Enum.TextXAlignment.Left,
		})

		local featureButtons = {
			UIGridLayout = React.createElement("UIGridLayout", {
				CellSize = UDim2.new(0, 90, 0, 34),
				CellPadding = UDim2.new(0, 4, 0, 4),
				FillDirection = Enum.FillDirection.Horizontal,
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		}
		for i, feat in ipairs(FEATURE_TYPES) do
			local isSelected = self.state.selectedFeature == feat.id
			featureButtons[feat.id] = React.createElement("TextButton", {
				LayoutOrder = i,
				BackgroundColor3 = isSelected and Color3.fromRGB(155, 120, 120) or Color3.fromRGB(61, 43, 31),
				BorderSizePixel = 0,
				Text = feat.label,
				FontFace = UIConfig.Font.Default,
				TextColor3 = isSelected and Color3.fromRGB(255, 245, 230) or Color3.fromRGB(190, 175, 155),
				TextSize = 14,
				[React.Event.MouseButton1Click] = function()
					self:setState({ selectedFeature = feat.id })
					localPlayer:SetAttribute("EditorFeatureType", feat.id)
				end,
			}, {
				UICorner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 4) }),
				ColorStrip = React.createElement("Frame", {
					Size = UDim2.new(0, 4, 1, 0),
					BackgroundColor3 = Color3.fromRGB(feat.color[1], feat.color[2], feat.color[3]),
					BorderSizePixel = 0,
				}, {
					UICorner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 2) }),
				}),
			})
		end
		content.FeatureGrid = React.createElement("Frame", {
			LayoutOrder = 2,
			Size = UDim2.new(1, 0, 0, 76),
			BackgroundTransparency = 1,
		}, featureButtons)

		content.ScaleSlider = React.createElement(Slider, {
			label = "Scale",
			value = self.state.featureScale * 10,
			min = 5,
			max = 20,
			step = 1,
			layoutOrder = 3,
			onChange = function(val)
				local scale = val / 10
				self:setState({ featureScale = scale })
				localPlayer:SetAttribute("EditorFeatureScale", scale)
			end,
		})

		content.Hint = React.createElement("TextLabel", {
			LayoutOrder = 4,
			Size = UDim2.new(1, 0, 0, 28),
			BackgroundTransparency = 1,
			Text = "Click on the map to place.",
			FontFace = UIConfig.Font.Default,
			TextColor3 = Color3.fromRGB(160, 145, 120),
			TextSize = 15,
			TextXAlignment = Enum.TextXAlignment.Left,
		})

	elseif activeTool == "Resources" then
		local RESOURCE_LIST = {
			{ id = "Wood",     label = "Wood",     color = Color3.fromRGB(60, 140, 40) },
			{ id = "Stone",    label = "Stone",    color = Color3.fromRGB(160, 155, 150) },
			{ id = "Food",     label = "Food",     color = Color3.fromRGB(200, 180, 50) },
			{ id = "Iron_Ore", label = "Iron Ore", color = Color3.fromRGB(110, 80, 70) },
		}
		local ZONE_COLORS = {
			[0] = Color3.fromRGB(140, 120, 80),
			[1] = Color3.fromRGB(80, 120, 200),
			[2] = Color3.fromRGB(200, 80, 80),
			[3] = Color3.fromRGB(80, 180, 80),
			[4] = Color3.fromRGB(200, 160, 40),
		}
		local ZONE_LABELS_RES = { [0]="Neutral", [1]="P1", [2]="P2", [3]="P3", [4]="P4" }

		local selectedZoneOwner = self.props.selectedResourceZone or 0
		local resourceAreas     = self.props.resourceAreas or {}
		local resBudgetMode     = self.props.resourceBudgetMode or "Equal"
		local resBudgetTargets  = self.props.resourceBudgetTargets or {}
		local resBudgetLocked   = self.props.resourceBudgetLocked or {}

		-- ── Zone tabs ──────────────────────────────────────────────────
		local zoneTabs: { [string]: any } = {
			UIListLayout = React.createElement("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				Padding = UDim.new(0, 3),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		}
		for i = 0, 4 do
			local isSel = selectedZoneOwner == i
			local lbl = ZONE_LABELS_RES[i]
			zoneTabs["ZTab_" .. i] = React.createElement("TextButton", {
				LayoutOrder = i + 1,
				Size = UDim2.new(0, 38, 0, 26),
				BackgroundColor3 = if isSel then ZONE_COLORS[i] else Color3.fromRGB(50, 35, 22),
				BorderSizePixel = 0,
				Text = lbl,
				FontFace = UIConfig.Font.Default,
				TextColor3 = if isSel then Color3.fromRGB(255, 245, 220) else Color3.fromRGB(160, 145, 120),
				TextSize = 12,
				[React.Event.MouseButton1Click] = function()
					if self.props.onResourceZoneChanged then self.props.onResourceZoneChanged(i) end
				end,
			}, { UICorner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 4) }) })
		end
		content.ZoneTabs = React.createElement("Frame", {
			LayoutOrder = 1,
			Size = UDim2.new(1, 0, 0, 28),
			BackgroundTransparency = 1,
		}, zoneTabs)

		-- ── Resource type picker for selected zone ──────────────────────
		-- Build budget rows for just the current zone tab (4 resources)
		local resRows: { { id: string, label: string, color: Color3 } } = {}
		for _, res in ipairs(RESOURCE_LIST) do
			local rowId = tostring(selectedZoneOwner) .. "_" .. res.id
			table.insert(resRows, {
				id = rowId,
				label = ZONE_LABELS_RES[selectedZoneOwner] .. " " .. res.label,
				color = res.color,
			})
		end

		-- Resource type selector (picks which type within the zone)
		local resBtns: { [string]: any } = {
			UIGridLayout = React.createElement("UIGridLayout", {
				CellSize = UDim2.new(0, 96, 0, 34),
				CellPadding = UDim2.new(0, 4, 0, 4),
				FillDirection = Enum.FillDirection.Horizontal,
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		}
		for i, res in ipairs(RESOURCE_LIST) do
			local isSel = self.state.selectedResource == res.id
			resBtns["Res_" .. res.id] = React.createElement("TextButton", {
				LayoutOrder = i,
				BackgroundColor3 = if isSel then Color3.fromRGB(155, 120, 120) else Color3.fromRGB(61, 43, 31),
				BorderSizePixel = 0,
				Text = res.label,
				FontFace = UIConfig.Font.Default,
				TextColor3 = if isSel then Color3.fromRGB(255, 245, 230) else Color3.fromRGB(190, 175, 155),
				TextSize = 14,
				[React.Event.MouseButton1Click] = function()
					self:setState({ selectedResource = res.id })
					localPlayer:SetAttribute("EditorResourceType", res.id)
				end,
			}, {
				UICorner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 4) }),
				ColorStrip = React.createElement("Frame", {
					Size = UDim2.new(0, 4, 1, 0),
					BackgroundColor3 = res.color,
					BorderSizePixel = 0,
				}, { UICorner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 2) }) }),
			})
		end
		content.ResGrid = React.createElement("Frame", {
			LayoutOrder = 2,
			Size = UDim2.new(1, 0, 0, 76),
			BackgroundTransparency = 1,
		}, resBtns)

		-- ── Budget panel for this zone's resources ──────────────────────
		local usedForZone: { [string]: number } = {}
		for _, res in ipairs(RESOURCE_LIST) do
			local rowId = tostring(selectedZoneOwner) .. "_" .. res.id
			usedForZone[rowId] = resourceAreas[rowId] or 0
		end

		content.ResBudget = React.createElement(BudgetPanel, {
			LayoutOrder = 3,
			rows = resRows,
			mode = resBudgetMode,
			targets = resBudgetTargets,
			locked  = resBudgetLocked,
			used    = usedForZone,
			onModeChanged = self.props.onResourceBudgetModeChanged,
			onTargetChanged = self.props.onResourceBudgetTargetChanged,
			onLockedChanged = self.props.onResourceBudgetLockedChanged,
		})

		-- ── Brush size & density ────────────────────────────────────────
		content.ResSizeSlider = React.createElement(Slider, {
			label = "Brush Size",
			value = self.state.resourceBrushRadius,
			min = 10,
			max = 150,
			step = 5,
			layoutOrder = 4,
			onChange = function(val)
				self:setState({ resourceBrushRadius = val })
				localPlayer:SetAttribute("EditorResourceBrushRadius", val)
			end,
		})

		content.DensitySlider = React.createElement(Slider, {
			label = "Density",
			value = self.state.resourceDensity,
			min = 1,
			max = 10,
			step = 1,
			layoutOrder = 5,
			onChange = function(val)
				self:setState({ resourceDensity = val })
				localPlayer:SetAttribute("EditorResourceDensity", val)
			end,
		})

		local resourceOverlayOn = self.props.resourceOverlayOn == true
		content.ResOverlayToggle = React.createElement("TextButton", {
			LayoutOrder = 6,
			Size = UDim2.new(1, 0, 0, 28),
			BackgroundColor3 = if resourceOverlayOn then Color3.fromRGB(80, 100, 130) else Color3.fromRGB(61, 43, 31),
			BorderSizePixel = 0,
			Text = if resourceOverlayOn then "Hide Resource Overlay" else "Show Resource Overlay",
			FontFace = UIConfig.Font.Default,
			TextColor3 = if resourceOverlayOn then Color3.fromRGB(200, 220, 255) else Color3.fromRGB(190, 175, 155),
			TextSize = 14,
			[React.Event.MouseButton1Click] = function()
				if self.props.onToggleResourceOverlay then self.props.onToggleResourceOverlay() end
			end,
		}, { UICorner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 4) }) })

		content.ResHint = React.createElement("TextLabel", {
			LayoutOrder = 7,
			Size = UDim2.new(1, 0, 0, 28),
			BackgroundTransparency = 1,
			Text = "LMB: Place resource patch.\nRMB+drag: Orbit camera.",
			FontFace = UIConfig.Font.Default,
			TextColor3 = Color3.fromRGB(160, 145, 120),
			TextSize = 14,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
		})

	elseif activeTool == "ZonePaint" then
		local ZONE_LIST = {
			{ id = 0, label = "Neutral", color = Color3.fromRGB(140, 120, 80) },
			{ id = 1, label = "P1",      color = Color3.fromRGB(80, 120, 200) },
			{ id = 2, label = "P2",      color = Color3.fromRGB(200, 80, 80)  },
			{ id = 3, label = "P3",      color = Color3.fromRGB(80, 180, 80)  },
			{ id = 4, label = "P4",      color = Color3.fromRGB(200, 160, 40) },
		}

		local zoneAreas        = self.props.zoneAreas or { [0]=0,[1]=0,[2]=0,[3]=0,[4]=0 }
		local zoneBudgetMode   = self.props.zoneBudgetMode or "Equal"
		local zoneBudgetTargets = self.props.zoneBudgetTargets or {}
		local zoneBudgetLocked  = self.props.zoneBudgetLocked or {}
		local zoneMode         = self.props.zoneMode or "Brush"
		local polygonClosed    = self.props.polygonClosed or false
		local polygonNodeCount = self.props.polygonNodeCount or 0

		-- ── Mode toggle: Brush / Polygon / Spawns ──────────────────────
		content.ModeToggle = React.createElement("Frame", {
			LayoutOrder = 0,
			Size = UDim2.new(1, 0, 0, 30),
			BackgroundTransparency = 1,
		}, {
			UIListLayout = React.createElement("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				Padding = UDim.new(0, 4),
				VerticalAlignment = Enum.VerticalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
			BrushBtn = React.createElement("TextButton", {
				LayoutOrder = 1,
				Size = UDim2.new(0.33, -3, 0, 26),
				BackgroundColor3 = if zoneMode == "Brush" then Color3.fromRGB(155, 120, 120) else Color3.fromRGB(61, 43, 31),
				BorderSizePixel = 0,
				Text = "Brush",
				FontFace = UIConfig.Font.Default,
				TextColor3 = if zoneMode == "Brush" then Color3.fromRGB(255, 245, 230) else Color3.fromRGB(190, 175, 155),
				TextSize = 13,
				[React.Event.MouseButton1Click] = function()
					if self.props.onZoneModeChanged then self.props.onZoneModeChanged("Brush") end
				end,
			}, { UICorner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 4) }) }),
			PolyBtn = React.createElement("TextButton", {
				LayoutOrder = 2,
				Size = UDim2.new(0.34, -3, 0, 26),
				BackgroundColor3 = if zoneMode == "Polygon" then Color3.fromRGB(155, 120, 120) else Color3.fromRGB(61, 43, 31),
				BorderSizePixel = 0,
				Text = "Polygon",
				FontFace = UIConfig.Font.Default,
				TextColor3 = if zoneMode == "Polygon" then Color3.fromRGB(255, 245, 230) else Color3.fromRGB(190, 175, 155),
				TextSize = 13,
				[React.Event.MouseButton1Click] = function()
					if self.props.onZoneModeChanged then self.props.onZoneModeChanged("Polygon") end
				end,
			}, { UICorner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 4) }) }),
			SpawnsBtn = React.createElement("TextButton", {
				LayoutOrder = 3,
				Size = UDim2.new(0.33, -3, 0, 26),
				BackgroundColor3 = if zoneMode == "Spawns" then Color3.fromRGB(155, 120, 120) else Color3.fromRGB(61, 43, 31),
				BorderSizePixel = 0,
				Text = "Spawns",
				FontFace = UIConfig.Font.Default,
				TextColor3 = if zoneMode == "Spawns" then Color3.fromRGB(255, 245, 230) else Color3.fromRGB(190, 175, 155),
				TextSize = 13,
				[React.Event.MouseButton1Click] = function()
					if self.props.onZoneModeChanged then self.props.onZoneModeChanged("Spawns") end
				end,
			}, { UICorner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 4) }) }),
		})

		-- ── Zone selector (Polygon mode only — Brush mode uses BrushPanel) ──
		if zoneMode == "Polygon" then
			local zoneButtons = {
				UIGridLayout = React.createElement("UIGridLayout", {
					CellSize = UDim2.new(0, 40, 0, 30),
					CellPadding = UDim2.new(0, 3, 0, 3),
					FillDirection = Enum.FillDirection.Horizontal,
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
			}
			for i, zone in ipairs(ZONE_LIST) do
				local isSelected = self.state.selectedZone == zone.id
				zoneButtons["Zone" .. zone.id] = React.createElement("TextButton", {
					LayoutOrder = i,
					BackgroundColor3 = isSelected and Color3.fromRGB(155, 120, 120) or Color3.fromRGB(61, 43, 31),
					BorderSizePixel = 0,
					Text = zone.label,
					FontFace = UIConfig.Font.Default,
					TextColor3 = isSelected and Color3.fromRGB(255, 245, 230) or Color3.fromRGB(190, 175, 155),
					TextSize = 12,
					[React.Event.MouseButton1Click] = function()
						self:setState({ selectedZone = zone.id })
						localPlayer:SetAttribute("EditorZoneNumber", zone.id)
					end,
				}, {
					UICorner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 4) }),
					ColorStrip = React.createElement("Frame", {
						Size = UDim2.new(0, 3, 1, 0),
						BackgroundColor3 = zone.color,
						BorderSizePixel = 0,
					}, { UICorner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 2) }) }),
				})
			end
			content.ZoneLabel = React.createElement("TextLabel", {
				LayoutOrder = 1,
				Size = UDim2.new(1, 0, 0, 18),
				BackgroundTransparency = 1,
				Text = "Zone / Territory",
				FontFace = UIConfig.Font.Default,
				TextColor3 = Color3.fromRGB(209, 148, 92),
				TextSize = 15,
				TextXAlignment = Enum.TextXAlignment.Left,
			})
			content.ZoneGrid = React.createElement("Frame", {
				LayoutOrder = 2,
				Size = UDim2.new(1, 0, 0, 66),
				BackgroundTransparency = 1,
			}, zoneButtons)
		end

		-- ── Polygon mode controls ──────────────────────────────────────
		if zoneMode == "Polygon" then
			local statusText = if polygonClosed
				then "Polygon closed — ready to commit"
				elseif polygonNodeCount >= 3
				then "Click near first node to close"
				else "Click on the map to place nodes"

			content.PolyStatus = React.createElement("TextLabel", {
				LayoutOrder = 3,
				Size = UDim2.new(1, 0, 0, 38),
				BackgroundTransparency = 1,
				Text = statusText,
				FontFace = UIConfig.Font.Default,
				TextColor3 = if polygonClosed then Color3.fromRGB(120, 200, 120) else Color3.fromRGB(190, 175, 155),
				TextSize = 13,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
			})

			content.PolyButtons = React.createElement("Frame", {
				LayoutOrder = 4,
				Size = UDim2.new(1, 0, 0, 32),
				BackgroundTransparency = 1,
			}, {
				UIListLayout = React.createElement("UIListLayout", {
					FillDirection = Enum.FillDirection.Horizontal,
					Padding = UDim.new(0, 6),
					VerticalAlignment = Enum.VerticalAlignment.Center,
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
				CommitBtn = React.createElement("TextButton", {
					LayoutOrder = 1,
					Size = UDim2.new(0.5, -3, 0, 28),
					BackgroundColor3 = if polygonClosed
						then Color3.fromRGB(60, 150, 80)
						else Color3.fromRGB(40, 60, 40),
					BorderSizePixel = 0,
					Text = "Commit",
					FontFace = UIConfig.Font.Default,
					TextColor3 = if polygonClosed then Color3.fromRGB(230, 255, 230) else Color3.fromRGB(100, 130, 100),
					TextSize = 13,
					[React.Event.MouseButton1Click] = function()
						if polygonClosed and self.props.onCommitPolygon then
							self.props.onCommitPolygon()
						end
					end,
				}, { UICorner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 4) }) }),
				CancelBtn = React.createElement("TextButton", {
					LayoutOrder = 2,
					Size = UDim2.new(0.5, -3, 0, 28),
					BackgroundColor3 = Color3.fromRGB(150, 60, 60),
					BorderSizePixel = 0,
					Text = "Cancel",
					FontFace = UIConfig.Font.Default,
					TextColor3 = Color3.fromRGB(255, 220, 220),
					TextSize = 13,
					[React.Event.MouseButton1Click] = function()
						if self.props.onCancelPolygon then
							self.props.onCancelPolygon()
						end
					end,
				}, { UICorner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 4) }) }),
			})
		end

		-- ── Overlay toggle button ──────────────────────────────────────
		local zoneOverlayOn = self.props.zoneOverlayOn == true
		content.OverlayToggle = React.createElement("TextButton", {
			LayoutOrder = 5,
			Size = UDim2.new(1, 0, 0, 28),
			BackgroundColor3 = if zoneOverlayOn then Color3.fromRGB(80, 120, 80) else Color3.fromRGB(61, 43, 31),
			BorderSizePixel = 0,
			Text = if zoneOverlayOn then "Hide Zone Overlay" else "Show Zone Overlay",
			FontFace = UIConfig.Font.Default,
			TextColor3 = if zoneOverlayOn then Color3.fromRGB(200, 255, 200) else Color3.fromRGB(190, 175, 155),
			TextSize = 14,
			[React.Event.MouseButton1Click] = function()
				if self.props.onToggleZoneOverlay then self.props.onToggleZoneOverlay() end
			end,
		}, { UICorner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 4) }) })

		-- ── Brush mode: zone selector + budget + sliders ───────────────
		if zoneMode == "Brush" then
			content.ZoneBrushPanel = React.createElement(BrushPanel, {
				sectionLabel = "Zone / Territory",
				options = ZONE_LIST,
				selectedId = self.state.selectedZone,
				onSelected = function(id)
					self:setState({ selectedZone = id })
					localPlayer:SetAttribute("EditorZoneNumber", id)
				end,
				brushRadius = self.state.zoneBrushRadius,
				onRadiusChanged = function(val)
					self:setState({ zoneBrushRadius = val })
					localPlayer:SetAttribute("EditorZoneBrushRadius", val)
				end,
				radiusMin = 20,
				radiusMax = 300,
				radiusStep = 10,
				brushShape = self.state.zoneBrushShape,
				onShapeChanged = function(shape)
					self:setState({ zoneBrushShape = shape })
					localPlayer:SetAttribute("EditorZoneBrushShape", shape)
				end,
				budgetPanel = React.createElement(BudgetPanel, {
					rows = ZONE_LIST,
					mode = zoneBudgetMode,
					targets = zoneBudgetTargets,
					locked  = zoneBudgetLocked,
					used    = zoneAreas,
					onModeChanged   = self.props.onZoneBudgetModeChanged,
					onTargetChanged = self.props.onZoneBudgetTargetChanged,
					onLockedChanged = self.props.onZoneBudgetLockedChanged,
				}),
			})

		-- ── Spawns mode: P1–P4 selector + radius ───────────────────────
		elseif zoneMode == "Spawns" then
			local SPAWN_ZONES = {
				{ id = 1, label = "P1", color = Color3.fromRGB(80, 120, 200) },
				{ id = 2, label = "P2", color = Color3.fromRGB(200, 80, 80) },
				{ id = 3, label = "P3", color = Color3.fromRGB(80, 180, 80) },
				{ id = 4, label = "P4", color = Color3.fromRGB(200, 160, 40) },
			}
			content.SpawnBrushPanel = React.createElement(BrushPanel, {
				sectionLabel = "Keep Spawn Zone",
				options = SPAWN_ZONES,
				selectedId = self.state.selectedSpawnZone,
				onSelected = function(id)
					self:setState({ selectedSpawnZone = id })
					localPlayer:SetAttribute("EditorKeepSpawnZone", id)
				end,
				brushRadius = self.state.keepSpawnRadius,
				onRadiusChanged = function(val)
					self:setState({ keepSpawnRadius = val })
					localPlayer:SetAttribute("EditorKeepSpawnRadius", val)
				end,
				radiusMin = 50,
				radiusMax = 400,
				radiusStep = 25,
				extraContent = {
					SpawnHint = React.createElement("TextLabel", {
						LayoutOrder = 99,
						Size = UDim2.new(1, 0, 0, 52),
						BackgroundTransparency = 1,
						Text = "Select a player zone then\nclick the map to place\ntheir Keep spawn point.",
						FontFace = UIConfig.Font.Default,
						TextColor3 = Color3.fromRGB(160, 145, 120),
						TextSize = 15,
						TextWrapped = true,
						TextXAlignment = Enum.TextXAlignment.Left,
					}),
				},
			})
		end -- if zoneMode

	elseif activeTool == "Settings" then
		local onMapSettingsChanged = self.props.onMapSettingsChanged
		local mapSize = self.props.mapSize or 1000
		local maxPlayers = self.props.maxPlayers or 4
		local neutralZoneWidth = self.props.neutralZoneWidth or 100
		local resourceDensity = self.props.resourceDensity or { Wood = 20, Stone = 15, Food = 10, Iron_Ore = 8 }

		-- Map Size (free-type number input)
		content.SizeRow = React.createElement("Frame", {
			LayoutOrder = 1,
			Size = UDim2.new(1, 0, 0, 30),
			BackgroundTransparency = 1,
		}, {
			Label = React.createElement("TextLabel", {
				Size = UDim2.new(0, 80, 1, 0),
				BackgroundTransparency = 1,
				Text = "Map Size",
				FontFace = UIConfig.Font.Default,
				TextColor3 = Color3.fromRGB(199, 166, 122),
				TextSize = 13,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			Input = React.createElement("TextBox", {
				Position = UDim2.new(0, 84, 0, 0),
				Size = UDim2.new(1, -84, 1, 0),
				BackgroundColor3 = Color3.fromRGB(40, 28, 18),
				BorderSizePixel = 0,
				Text = tostring(mapSize),
				FontFace = UIConfig.Font.Default,
				TextColor3 = Color3.fromRGB(240, 210, 160),
				TextSize = 13,
				TextXAlignment = Enum.TextXAlignment.Center,
				ClearTextOnFocus = false,
				[React.Event.FocusLost] = function(rbx)
					local num = tonumber(rbx.Text)
					if num then
						num = math.max(100, math.floor(num))
						rbx.Text = tostring(num)
						if onMapSettingsChanged then
							onMapSettingsChanged({ size = num })
						end
					else
						rbx.Text = tostring(mapSize)
					end
				end,
			}, {
				UICorner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 4) }),
				UIPadding = React.createElement("UIPadding", {
					PaddingLeft = UDim.new(0, 6),
					PaddingRight = UDim.new(0, 6),
				}),
			}),
		})

		-- Max Players
		content.MaxPlayersToggle = createToggle({
			label = "Max Players",
			options = { "2", "4" },
			selected = tostring(maxPlayers),
			layoutOrder = 2,
			onChange = function(val)
				if onMapSettingsChanged then
					onMapSettingsChanged({ maxPlayers = tonumber(val) })
				end
			end,
		})

		-- Neutral Zone Width
		content.NeutralZoneSlider = React.createElement(Slider, {
			label = "Neutral Zone",
			value = neutralZoneWidth,
			min = 0,
			max = 300,
			step = 25,
			layoutOrder = 3,
			formatValue = function(v) return tostring(math.floor(v)) end,
			onChange = function(val)
				if onMapSettingsChanged then
					onMapSettingsChanged({ neutralZoneWidth = val })
				end
			end,
		})

		-- Resource Density header
		content.ResourceHeader = React.createElement("TextLabel", {
			LayoutOrder = 4,
			Size = UDim2.new(1, 0, 0, 20),
			BackgroundTransparency = 1,
			Text = "Resource Spawn Density",
			FontFace = UIConfig.Font.Default,
			TextColor3 = Color3.fromRGB(209, 148, 92),
			TextSize = 16,
			TextXAlignment = Enum.TextXAlignment.Left,
		})

		content.WoodSlider = React.createElement(Slider, {
			label = "Wood",
			value = resourceDensity.Wood or 20,
			min = 0,
			max = 50,
			step = 5,
			layoutOrder = 5,
			onChange = function(val)
				if onMapSettingsChanged then
					local rd = {}
					for k, v in pairs(resourceDensity) do rd[k] = v end
					rd.Wood = val
					onMapSettingsChanged({ resourceDensity = rd })
				end
			end,
		})

		content.StoneSlider = React.createElement(Slider, {
			label = "Stone",
			value = resourceDensity.Stone or 15,
			min = 0,
			max = 50,
			step = 5,
			layoutOrder = 6,
			onChange = function(val)
				if onMapSettingsChanged then
					local rd = {}
					for k, v in pairs(resourceDensity) do rd[k] = v end
					rd.Stone = val
					onMapSettingsChanged({ resourceDensity = rd })
				end
			end,
		})

		content.FoodSlider = React.createElement(Slider, {
			label = "Food",
			value = resourceDensity.Food or 10,
			min = 0,
			max = 50,
			step = 5,
			layoutOrder = 7,
			onChange = function(val)
				if onMapSettingsChanged then
					local rd = {}
					for k, v in pairs(resourceDensity) do rd[k] = v end
					rd.Food = val
					onMapSettingsChanged({ resourceDensity = rd })
				end
			end,
		})

		content.IronSlider = React.createElement(Slider, {
			label = "Iron Ore",
			value = resourceDensity.Iron_Ore or 8,
			min = 0,
			max = 50,
			step = 5,
			layoutOrder = 8,
			onChange = function(val)
				if onMapSettingsChanged then
					local rd = {}
					for k, v in pairs(resourceDensity) do rd[k] = v end
					rd.Iron_Ore = val
					onMapSettingsChanged({ resourceDensity = rd })
				end
			end,
		})
	end

	content.UIListLayout = React.createElement("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 6),
	})

	return React.createElement("Frame", {
		Name = "PropertyPanel",
		Size = UDim2.new(0, 230, 0, 620),
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
			PaddingTop = UDim.new(0, 10),
			PaddingLeft = UDim.new(0, 10),
			PaddingRight = UDim.new(0, 10),
			PaddingBottom = UDim.new(0, 10),
		}),
		Content = React.createElement("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
		}, content),
	})
end

return EditorPropertyPanel
