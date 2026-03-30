--!strict
-- BrushPanel: Reusable brush tool panel used by ZonePaint and Resources.
-- Props:
--   sectionLabel    string                          Header label
--   options         {{id:any, label:string, color:Color3}}   Selector buttons
--   selectedId      any                             Currently selected option id
--   onSelected      (id:any)->()
--   brushRadius     number
--   onRadiusChanged (number)->()
--   radiusMin       number?                         Default 10
--   radiusMax       number?                         Default 300
--   radiusStep      number?                         Default 10
--   brushShape      string?                         "Circle"|"Square" — omit to hide shape toggle
--   onShapeChanged  ((string)->())?
--   -- Budget panel (optional ReactElement — rendered between option grid and sliders)
--   budgetPanel     any?
--   -- Extra slots rendered after the sliders (optional)
--   extraContent    {[string]:any}?

local React = require(game.ReplicatedStorage.Packages.react)
local UserInputService = game:GetService("UserInputService")
local UIConfig = require(script.Parent.Parent.Parent.UIConfig)

-- ── Slider (self-contained so BrushPanel has no external deps)
local Slider = React.Component:extend("BrushPanelSlider")

function Slider:init()
	self:setState({ isDragging = false })
	self.trackRef = React.createRef()
	self.inputMovedConn = nil :: RBXScriptConnection?
	self.inputEndedConn = nil :: RBXScriptConnection?
end

function Slider:willUnmount()
	if self.inputMovedConn then self.inputMovedConn:Disconnect() end
	if self.inputEndedConn then self.inputEndedConn:Disconnect() end
end

local function computeVal(mouseX: number, frame: GuiObject, min: number, max: number, step: number): number
	local pos  = frame.AbsolutePosition.X
	local size = frame.AbsoluteSize.X
	if size <= 0 then return min end
	local frac = math.clamp((mouseX - pos) / size, 0, 1)
	return math.clamp(math.round((min + frac * (max - min)) / step) * step, min, max)
end

function Slider:startDrag(mouseX: number)
	self:setState({ isDragging = true })
	local tf = self.trackRef.current
	if tf then
		local step = self.props.step or 1
		self.props.onChange(computeVal(mouseX, tf, self.props.min, self.props.max, step))
	end
	self.inputMovedConn = UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			local tf2 = self.trackRef.current
			if tf2 then
				local step = self.props.step or 1
				self.props.onChange(computeVal(input.Position.X, tf2, self.props.min, self.props.max, step))
			end
		end
	end)
	self.inputEndedConn = UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			self:setState({ isDragging = false })
			if self.inputMovedConn then self.inputMovedConn:Disconnect() self.inputMovedConn = nil end
			if self.inputEndedConn then self.inputEndedConn:Disconnect() self.inputEndedConn = nil end
		end
	end)
end

function Slider:render()
	local props = self.props
	local min, max, step = props.min, props.max, props.step or 1
	local value = props.value
	local fill  = math.clamp((value - min) / math.max(max - min, 0.001), 0, 1)
	local displayValue = if props.formatValue then props.formatValue(value) else tostring(value)

	return React.createElement("Frame", {
		LayoutOrder = props.layoutOrder,
		Size = UDim2.new(1, 0, 0, 46),
		BackgroundTransparency = 1,
	}, {
		LabelRow = React.createElement("Frame", {
			Size = UDim2.new(1, 0, 0, 18),
			BackgroundTransparency = 1,
		}, {
			Label = React.createElement("TextLabel", {
				Size = UDim2.new(1, -40, 1, 0),
				BackgroundTransparency = 1,
				Text = props.label,
				FontFace = UIConfig.Font.Default,
				TextColor3 = Color3.fromRGB(190, 175, 155),
				TextSize = 15,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			Value = React.createElement("TextLabel", {
				Size = UDim2.new(0, 40, 1, 0),
				Position = UDim2.new(1, -40, 0, 0),
				BackgroundTransparency = 1,
				Text = displayValue,
				FontFace = UIConfig.Font.Default,
				TextColor3 = Color3.fromRGB(230, 215, 190),
				TextSize = 15,
				TextXAlignment = Enum.TextXAlignment.Right,
			}),
		}),
		Controls = React.createElement("Frame", {
			Size = UDim2.new(1, 0, 0, 22),
			Position = UDim2.new(0, 0, 0, 22),
			BackgroundTransparency = 1,
		}, {
			MinusBtn = React.createElement("TextButton", {
				Size = UDim2.new(0, 20, 0, 18),
				Position = UDim2.new(0, 0, 0.5, -9),
				BackgroundColor3 = Color3.fromRGB(61, 43, 31),
				BorderSizePixel = 0,
				Text = "−",
				FontFace = UIConfig.Font.Default,
				TextColor3 = Color3.fromRGB(200, 185, 160),
				TextSize = 16,
				[React.Event.MouseButton1Click] = function()
					props.onChange(math.clamp(math.round((value - step) / step) * step, min, max))
				end,
			}, { UICorner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 3) }) }),
			Track = React.createElement("Frame", {
				Size = UDim2.new(1, -48, 0, 8),
				Position = UDim2.new(0, 26, 0.5, -4),
				BackgroundColor3 = Color3.fromRGB(35, 25, 15),
				BorderSizePixel = 0,
				[React.Event.InputBegan] = function(_, input)
					if input.UserInputType == Enum.UserInputType.MouseButton1 then
						self:startDrag(input.Position.X)
					end
				end,
			}, {
				UICorner = React.createElement("UICorner", { CornerRadius = UDim.new(1, 0) }),
				Fill = React.createElement("Frame", {
					Size = UDim2.new(fill, 0, 1, 0),
					BackgroundColor3 = Color3.fromRGB(155, 120, 80),
					BorderSizePixel = 0,
				}, { UICorner = React.createElement("UICorner", { CornerRadius = UDim.new(1, 0) }) }),
				trackRef = self.trackRef,
			}),
			PlusBtn = React.createElement("TextButton", {
				Size = UDim2.new(0, 20, 0, 18),
				Position = UDim2.new(1, -20, 0.5, -9),
				BackgroundColor3 = Color3.fromRGB(61, 43, 31),
				BorderSizePixel = 0,
				Text = "+",
				FontFace = UIConfig.Font.Default,
				TextColor3 = Color3.fromRGB(200, 185, 160),
				TextSize = 16,
				[React.Event.MouseButton1Click] = function()
					props.onChange(math.clamp(math.round((value + step) / step) * step, min, max))
				end,
			}, { UICorner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 3) }) }),
		}),
	})
end

-- ── BrushPanel (functional component)
local function BrushPanel(props: any)
	local options: { { id: any, label: string, color: Color3 } } = props.options or {}
	local selectedId = props.selectedId
	local brushShape: string? = props.brushShape
	local lo = 0

	local children: { [string]: any } = {}

	local function nextLO(): number lo += 1 return lo end

	-- ── Section label
	children.SectionLabel = React.createElement("TextLabel", {
		LayoutOrder = nextLO(),
		Size = UDim2.new(1, 0, 0, 20),
		BackgroundTransparency = 1,
		Text = props.sectionLabel or "Select",
		FontFace = UIConfig.Font.Default,
		TextColor3 = Color3.fromRGB(209, 148, 92),
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
	})

	-- ── Option selector buttons
	local btnSize = if #options <= 5
		then UDim2.new(0, 40, 0, 30)
		else UDim2.new(0, 96, 0, 34)
	local gridH = if #options <= 5 then 66 else 76
	local stripW = if #options <= 5 then 3 else 4

	local btnChildren: { [string]: any } = {
		UIGridLayout = React.createElement("UIGridLayout", {
			CellSize = btnSize,
			CellPadding = UDim2.new(0, 4, 0, 4),
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}
	for i, opt in ipairs(options) do
		local isSel = selectedId == opt.id
		btnChildren["Opt_" .. tostring(opt.id)] = React.createElement("TextButton", {
			LayoutOrder = i,
			BackgroundColor3 = if isSel then Color3.fromRGB(155, 120, 120) else Color3.fromRGB(61, 43, 31),
			BorderSizePixel = 0,
			Text = opt.label,
			FontFace = UIConfig.Font.Default,
			TextColor3 = if isSel then Color3.fromRGB(255, 245, 230) else Color3.fromRGB(190, 175, 155),
			TextSize = 14,
			[React.Event.MouseButton1Click] = function()
				if props.onSelected then props.onSelected(opt.id) end
			end,
		}, {
			UICorner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 4) }),
			ColorStrip = React.createElement("Frame", {
				Size = UDim2.new(0, stripW, 1, 0),
				BackgroundColor3 = opt.color,
				BorderSizePixel = 0,
			}, { UICorner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 2) }) }),
		})
	end
	children.OptionGrid = React.createElement("Frame", {
		LayoutOrder = nextLO(),
		Size = UDim2.new(1, 0, 0, gridH),
		BackgroundTransparency = 1,
	}, btnChildren)

	-- ── Budget panel slot (optional — caller passes a BudgetPanel element)
	if props.budgetPanel then
		children.BudgetPanelSlot = React.createElement("Frame", {
			LayoutOrder = nextLO(),
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
		}, { Inner = props.budgetPanel })
	end

	-- ── Shape toggle (optional)
	if brushShape and props.onShapeChanged then
		local shapeOpts = { "Circle", "Square" }
		local shapeBtns: { [string]: any } = {
			UIListLayout = React.createElement("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				Padding = UDim.new(0, 4),
				VerticalAlignment = Enum.VerticalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
			ShapeLabel = React.createElement("TextLabel", {
				LayoutOrder = 0,
				Size = UDim2.new(0, 48, 1, 0),
				BackgroundTransparency = 1,
				Text = "Shape",
				FontFace = UIConfig.Font.Default,
				TextColor3 = Color3.fromRGB(190, 175, 155),
				TextSize = 15,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
		}
		for i, shape in ipairs(shapeOpts) do
			local isSel = brushShape == shape
			shapeBtns["Shape_" .. shape] = React.createElement("TextButton", {
				LayoutOrder = i,
				Size = UDim2.new(0, 60, 0, 24),
				BackgroundColor3 = if isSel then Color3.fromRGB(155, 120, 120) else Color3.fromRGB(61, 43, 31),
				BorderSizePixel = 0,
				Text = shape,
				FontFace = UIConfig.Font.Default,
				TextColor3 = if isSel then Color3.fromRGB(255, 245, 230) else Color3.fromRGB(190, 175, 155),
				TextSize = 14,
				[React.Event.MouseButton1Click] = function()
					if props.onShapeChanged then props.onShapeChanged(shape) end
				end,
			}, { UICorner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 4) }) })
		end
		children.ShapeToggle = React.createElement("Frame", {
			LayoutOrder = nextLO(),
			Size = UDim2.new(1, 0, 0, 30),
			BackgroundTransparency = 1,
		}, shapeBtns)
	end

	-- ── Brush size slider
	children.SizeSlider = React.createElement(Slider, {
		label = "Brush Size",
		value = props.brushRadius or 40,
		min = props.radiusMin or 10,
		max = props.radiusMax or 300,
		step = props.radiusStep or 10,
		layoutOrder = nextLO(),
		onChange = function(v)
			if props.onRadiusChanged then props.onRadiusChanged(v) end
		end,
	})

	-- ── Extra content
	if props.extraContent then
		for k, v in pairs(props.extraContent) do
			children[k] = v
		end
	end

	children.Layout = React.createElement("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})

	return React.createElement("Frame", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
	}, children)
end

return BrushPanel
