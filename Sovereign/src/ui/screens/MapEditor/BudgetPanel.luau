--!strict
-- BudgetPanel: Per-row lockable budget display used by ZonePaint and Resources.
-- Props:
--   rows            {{id:any, label:string, color:Color3}}   One row per tracked entity
--   mode            "Freeform"|"Equal"|"Custom"
--   targets         {[any]:number}      target % per row id
--   locked          {[any]:boolean}     enforcement on/off per row id
--   used            {[any]:number}      actual % used per row id (nil key = 0)
--   onModeChanged   (string)->()
--   onTargetChanged (id:any, pct:number)->()
--   onLockedChanged (id:any, locked:boolean)->()

local React = require(game.ReplicatedStorage.Packages.react)
local UIConfig = require(script.Parent.Parent.Parent.UIConfig)

local ZONE_LABELS = { [0]="N", [1]="P1", [2]="P2", [3]="P3", [4]="P4" }

local function BudgetPanel(props: any)
	local rows: { { id: any, label: string, color: Color3 } } = props.rows or {}
	local mode: string = props.mode or "Freeform"
	local targets: { [any]: number } = props.targets or {}
	local locked: { [any]: boolean } = props.locked or {}
	local used: { [any]: number } = props.used or {}
	local n = #rows

	local children: { [string]: any } = {}

	-- ── Master mode buttons ──────────────────────────────────────────────
	local modeBtns: { [string]: any } = {
		UIListLayout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 4),
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}
	for i, m in ipairs({ "Freeform", "Equal", "Custom" }) do
		local isSel = mode == m
		modeBtns["Mode_" .. m] = React.createElement("TextButton", {
			LayoutOrder = i,
			Size = UDim2.new(0, 62, 0, 24),
			BackgroundColor3 = if isSel then Color3.fromRGB(120, 90, 60) else Color3.fromRGB(50, 35, 22),
			BorderSizePixel = 0,
			Text = m,
			FontFace = UIConfig.Font.Default,
			TextColor3 = if isSel then Color3.fromRGB(255, 240, 210) else Color3.fromRGB(160, 145, 120),
			TextSize = 13,
			[React.Event.MouseButton1Click] = function()
				if props.onModeChanged then props.onModeChanged(m) end
			end,
		}, { UICorner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 4) }) })
	end
	children.ModeRow = React.createElement("Frame", {
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 26),
		BackgroundTransparency = 1,
	}, modeBtns)

	-- ── Per-row entries ──────────────────────────────────────────────────
	for i, row in ipairs(rows) do
		local id = row.id
		local usedPct: number = used[id] or 0
		local target: number = targets[id] or math.max(1, math.floor(100 / math.max(n, 1)))
		local isLocked: boolean = locked[id] == true
		local isActive = mode ~= "Freeform" and isLocked
		local over = isActive and usedPct >= target - 0.05
		local barFill = if isActive
			then math.clamp(usedPct / math.max(target, 0.001), 0, 1)
			else math.clamp(usedPct / 100, 0, 1)

		-- Lock button
		local lockBtn = React.createElement("TextButton", {
			Size = UDim2.new(0, 20, 0, 20),
			Position = UDim2.new(0, 0, 0.5, -10),
			BackgroundColor3 = if isLocked then Color3.fromRGB(80, 130, 80) else Color3.fromRGB(50, 35, 22),
			BorderSizePixel = 0,
			Text = if isLocked then "🔒" else "🔓",
			FontFace = UIConfig.Font.Default,
			TextColor3 = Color3.fromRGB(255, 255, 255),
			TextSize = 11,
			[React.Event.MouseButton1Click] = function()
				if props.onLockedChanged and mode == "Custom" then
					props.onLockedChanged(id, not isLocked)
				end
			end,
		}, { UICorner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 3) }) })

		-- Target stepper (only interactive in Custom mode; shown but dim in Equal/Freeform)
		local canEdit = mode == "Custom"
		local stepperChildren: { [string]: any } = {
			UIListLayout = React.createElement("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				Padding = UDim.new(0, 2),
				VerticalAlignment = Enum.VerticalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
			MinusBtn = React.createElement("TextButton", {
				LayoutOrder = 1,
				Size = UDim2.new(0, 16, 0, 18),
				BackgroundColor3 = if canEdit then Color3.fromRGB(61, 43, 31) else Color3.fromRGB(35, 25, 15),
				BorderSizePixel = 0,
				Text = "−",
				FontFace = UIConfig.Font.Default,
				TextColor3 = if canEdit then Color3.fromRGB(200, 185, 160) else Color3.fromRGB(80, 70, 55),
				TextSize = 14,
				[React.Event.MouseButton1Click] = function()
					if canEdit and props.onTargetChanged then
						props.onTargetChanged(id, math.clamp(target - 1, 1, 100))
					end
				end,
			}, { UICorner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 2) }) }),
			ValueLabel = React.createElement("TextLabel", {
				LayoutOrder = 2,
				Size = UDim2.new(0, 30, 0, 18),
				BackgroundColor3 = Color3.fromRGB(30, 20, 12),
				BackgroundTransparency = 0,
				BorderSizePixel = 0,
				Text = tostring(math.floor(target)) .. "%",
				FontFace = UIConfig.Font.Default,
				TextColor3 = if canEdit then Color3.fromRGB(230, 215, 185) else Color3.fromRGB(100, 90, 70),
				TextSize = 12,
			}),
			PlusBtn = React.createElement("TextButton", {
				LayoutOrder = 3,
				Size = UDim2.new(0, 16, 0, 18),
				BackgroundColor3 = if canEdit then Color3.fromRGB(61, 43, 31) else Color3.fromRGB(35, 25, 15),
				BorderSizePixel = 0,
				Text = "+",
				FontFace = UIConfig.Font.Default,
				TextColor3 = if canEdit then Color3.fromRGB(200, 185, 160) else Color3.fromRGB(80, 70, 55),
				TextSize = 14,
				[React.Event.MouseButton1Click] = function()
					if canEdit and props.onTargetChanged then
						props.onTargetChanged(id, math.clamp(target + 1, 1, 100))
					end
				end,
			}, { UICorner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 2) }) }),
		}
		local stepper = React.createElement("Frame", {
			Size = UDim2.new(0, 66, 0, 20),
			Position = UDim2.new(0, 24, 0.5, -10),
			BackgroundTransparency = 1,
		}, stepperChildren)

		-- Used % label
		local usedLabel = React.createElement("TextLabel", {
			Size = UDim2.new(0, 40, 0, 18),
			Position = UDim2.new(0, 94, 0.5, -9),
			BackgroundTransparency = 1,
			Text = string.format("%.1f%%", usedPct),
			FontFace = UIConfig.Font.Default,
			TextColor3 = if over then Color3.fromRGB(255, 110, 80) else Color3.fromRGB(190, 175, 150),
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
		})

		-- Progress bar
		local bar = React.createElement("Frame", {
			Size = UDim2.new(1, -138, 0, 8),
			Position = UDim2.new(0, 138, 0.5, -4),
			BackgroundColor3 = Color3.fromRGB(30, 20, 12),
			BorderSizePixel = 0,
		}, {
			UICorner = React.createElement("UICorner", { CornerRadius = UDim.new(1, 0) }),
			Fill = React.createElement("Frame", {
				Size = UDim2.new(barFill, 0, 1, 0),
				BackgroundColor3 = if over then Color3.fromRGB(220, 70, 50) else row.color,
				BorderSizePixel = 0,
			}, { UICorner = React.createElement("UICorner", { CornerRadius = UDim.new(1, 0) }) }),
		})

		-- Row label (short)
		local labelEl = React.createElement("TextLabel", {
			Size = UDim2.new(0, 66, 1, 0),
			Position = UDim2.new(0, 24, 0, 0),
			BackgroundTransparency = 1,
			Text = row.label,
			FontFace = UIConfig.Font.Default,
			TextColor3 = Color3.fromRGB(210, 195, 170),
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
		})

		children["Row_" .. tostring(i)] = React.createElement("Frame", {
			LayoutOrder = i + 1,
			Size = UDim2.new(1, 0, 0, 34),
			BackgroundTransparency = 1,
		}, {
			LockBtn = lockBtn,
			Label = labelEl,
			Stepper = stepper,
			UsedLabel = usedLabel,
			Bar = bar,
		})
	end

	-- ── Outer layout ─────────────────────────────────────────────────────
	children.Layout = React.createElement("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		Padding = UDim.new(0, 2),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})

	local totalH = 28 + n * 36
	return React.createElement("Frame", {
		LayoutOrder = props.layoutOrder,
		Size = UDim2.new(1, 0, 0, totalH),
		BackgroundTransparency = 1,
	}, children)
end

return BudgetPanel
