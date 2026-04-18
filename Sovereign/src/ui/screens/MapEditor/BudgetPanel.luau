--!strict
-- BudgetPanel: Per-row lockable budget display used by ZonePaint and Resources.
-- Props:
--   rows              {{id:any, label:string, color:Color3}}
--   mode              "Freeform"|"Equal"|"Custom"
--   targets           {[any]:number}      target % per row id
--   locked            {[any]:boolean}     enforcement on/off per row id
--   used              {[any]:number}      actual % used per row id (nil = 0)
--   tolerance         number              Equal mode max variance % (default 5)
--   onModeChanged     (string)->()
--   onTargetChanged   (id:any, pct:number)->()
--   onLockedChanged   (id:any, locked:boolean)->()
--   onToleranceChanged (number)->()

local React = require(game.ReplicatedStorage.Packages.react)
local UIConfig = require(script.Parent.Parent.Parent.UIConfig)

local function BudgetPanel(props: any)
	local rows: { { id: any, label: string, color: Color3 } } = props.rows or {}
	local mode: string = props.mode or "Freeform"
	local targets: { [any]: number } = props.targets or {}
	local locked: { [any]: boolean } = props.locked or {}
	local used: { [any]: number } = props.used or {}
	local tolerance: number = props.tolerance or 5

	-- Split rows into territory (ids 0-4) and map-feature (ids 5-6)
	local territoryRows: { { id: any, label: string, color: Color3 } } = {}
	local featureRows:   { { id: any, label: string, color: Color3 } } = {}
	for _, row in ipairs(rows) do
		if type(row.id) == "number" and row.id >= 5 then
			table.insert(featureRows, row)
		else
			table.insert(territoryRows, row)
		end
	end
	local n = #territoryRows

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

	-- ── Per-row entries (territory zones 0-4) ───────────────────────────
	for i, row in ipairs(territoryRows) do
		local id = row.id
		local usedPct: number = used[id] or 0

		if mode == "Equal" then
			-- Equal mode: clean display — just color swatch, label, used%, bar.
			-- Lock and stepper are hidden since enforcement is handled automatically.
			local isPlayerZone = type(id) == "number" and id >= 1 and id <= 4

			-- Collect player areas to detect if this zone is the largest
			local playerAreas: { number } = {}
			for _, r in ipairs(rows) do
				if type(r.id) == "number" and r.id >= 1 and r.id <= 4 then
					table.insert(playerAreas, used[r.id] or 0)
				end
			end
			local maxArea = 0
			for _, a in ipairs(playerAreas) do
				if a > maxArea then maxArea = a end
			end
			local isMaxZone = isPlayerZone and math.abs(usedPct - maxArea) < 0.01 and maxArea > 0

			-- Bar fills relative to the largest zone so imbalance is obvious
			local barFill = if maxArea > 0
				then math.clamp(usedPct / maxArea, 0, 1)
				else math.clamp(usedPct / 100, 0, 1)

			-- Colour swatch
			local swatch = React.createElement("Frame", {
				Size = UDim2.new(0, 10, 0, 10),
				Position = UDim2.new(0, 2, 0.5, -5),
				BackgroundColor3 = row.color,
				BorderSizePixel = 0,
			}, { UICorner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 2) }) })

			local labelEl = React.createElement("TextLabel", {
				Size = UDim2.new(0, 30, 1, 0),
				Position = UDim2.new(0, 16, 0, 0),
				BackgroundTransparency = 1,
				Text = row.label,
				FontFace = UIConfig.Font.Default,
				TextColor3 = Color3.fromRGB(210, 195, 170),
				TextSize = 13,
				TextXAlignment = Enum.TextXAlignment.Left,
			})

			local usedLabel = React.createElement("TextLabel", {
				Size = UDim2.new(0, 42, 0, 18),
				Position = UDim2.new(0, 48, 0.5, -9),
				BackgroundTransparency = 1,
				Text = string.format("%.1f%%", usedPct),
				FontFace = UIConfig.Font.Default,
				TextColor3 = if isMaxZone and #playerAreas > 1
					then Color3.fromRGB(255, 200, 80)
					else Color3.fromRGB(190, 175, 150),
				TextSize = 12,
				TextXAlignment = Enum.TextXAlignment.Left,
			})

			local bar = React.createElement("Frame", {
				Size = UDim2.new(1, -94, 0, 6),
				Position = UDim2.new(0, 94, 0.5, -3),
				BackgroundColor3 = Color3.fromRGB(30, 20, 12),
				BorderSizePixel = 0,
			}, {
				UICorner = React.createElement("UICorner", { CornerRadius = UDim.new(1, 0) }),
				Fill = React.createElement("Frame", {
					Size = UDim2.new(barFill, 0, 1, 0),
					BackgroundColor3 = row.color,
					BorderSizePixel = 0,
				}, { UICorner = React.createElement("UICorner", { CornerRadius = UDim.new(1, 0) }) }),
			})

			children["Row_" .. tostring(i)] = React.createElement("Frame", {
				LayoutOrder = i + 1,
				Size = UDim2.new(1, 0, 0, 28),
				BackgroundTransparency = 1,
			}, {
				Swatch = swatch,
				Label = labelEl,
				UsedLabel = usedLabel,
				Bar = bar,
			})
		else
			-- Freeform / Custom mode: full controls (lock + stepper + bar)
			local target: number = targets[id] or math.max(1, math.floor(100 / math.max(n, 1)))
			local isLocked: boolean = locked[id] == true
			local isActive = mode ~= "Freeform" and isLocked
			local over = isActive and usedPct >= target - 0.05
			local barFill = if isActive
				then math.clamp(usedPct / math.max(target, 0.001), 0, 1)
				else math.clamp(usedPct / 100, 0, 1)

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

			local canEdit = mode == "Custom"
			local stepper = React.createElement("Frame", {
				Size = UDim2.new(0, 66, 0, 20),
				Position = UDim2.new(0, 24, 0.5, -10),
				BackgroundTransparency = 1,
			}, {
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
			})

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
	end

	-- ── Equal mode: tolerance stepper + balance indicator ────────────────
	if mode == "Equal" then
		-- Tolerance stepper
		children.ToleranceRow = React.createElement("Frame", {
			LayoutOrder = n + 2,
			Size = UDim2.new(1, 0, 0, 28),
			BackgroundTransparency = 1,
		}, {
			UIListLayout = React.createElement("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 4),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
			Label = React.createElement("TextLabel", {
				LayoutOrder = 1,
				Size = UDim2.new(0, 72, 1, 0),
				BackgroundTransparency = 1,
				Text = "Tolerance:",
				FontFace = UIConfig.Font.Default,
				TextColor3 = Color3.fromRGB(180, 165, 140),
				TextSize = 12,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			MinusBtn = React.createElement("TextButton", {
				LayoutOrder = 2,
				Size = UDim2.new(0, 20, 0, 20),
				BackgroundColor3 = Color3.fromRGB(61, 43, 31),
				BorderSizePixel = 0,
				Text = "−",
				FontFace = UIConfig.Font.Default,
				TextColor3 = Color3.fromRGB(200, 185, 160),
				TextSize = 14,
				[React.Event.MouseButton1Click] = function()
					if props.onToleranceChanged then
						props.onToleranceChanged(math.clamp(tolerance - 1, 1, 30))
					end
				end,
			}, { UICorner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 3) }) }),
			ValueLabel = React.createElement("TextLabel", {
				LayoutOrder = 3,
				Size = UDim2.new(0, 36, 0, 20),
				BackgroundColor3 = Color3.fromRGB(30, 20, 12),
				BorderSizePixel = 0,
				Text = tostring(math.floor(tolerance)) .. "%",
				FontFace = UIConfig.Font.Default,
				TextColor3 = Color3.fromRGB(230, 215, 185),
				TextSize = 12,
				TextXAlignment = Enum.TextXAlignment.Center,
			}),
			PlusBtn = React.createElement("TextButton", {
				LayoutOrder = 4,
				Size = UDim2.new(0, 20, 0, 20),
				BackgroundColor3 = Color3.fromRGB(61, 43, 31),
				BorderSizePixel = 0,
				Text = "+",
				FontFace = UIConfig.Font.Default,
				TextColor3 = Color3.fromRGB(200, 185, 160),
				TextSize = 14,
				[React.Event.MouseButton1Click] = function()
					if props.onToleranceChanged then
						props.onToleranceChanged(math.clamp(tolerance + 1, 1, 30))
					end
				end,
			}, { UICorner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 3) }) }),
		})

		-- Balance indicator
		local playerAreas: { number } = {}
		for _, row in ipairs(rows) do
			local id = row.id
			if type(id) == "number" and id >= 1 and id <= 4 then
				table.insert(playerAreas, used[id] or 0)
			end
		end

		local minArea, maxArea = math.huge, -math.huge
		for _, a in ipairs(playerAreas) do
			if a < minArea then minArea = a end
			if a > maxArea then maxArea = a end
		end
		if minArea == math.huge then minArea = 0 end
		if maxArea == -math.huge then maxArea = 0 end

		local variance = maxArea - minArea
		local color = if variance <= tolerance
			then Color3.fromRGB(80, 200, 100)
			elseif variance <= tolerance * 2
			then Color3.fromRGB(230, 180, 50)
			else Color3.fromRGB(220, 70, 50)

		local statusText = if #playerAreas < 2
			then "Paint at least 2 zones to compare"
			elseif variance <= tolerance
			then string.format("✓ Balanced  (Δ %.1f%%)", variance)
			else string.format("⚠ Unbalanced  (Δ %.1f%% > %.0f%%)", variance, tolerance)

		children.BalanceIndicator = React.createElement("Frame", {
			LayoutOrder = n + 3,
			Size = UDim2.new(1, 0, 0, 26),
			BackgroundColor3 = Color3.fromRGB(25, 18, 10),
			BackgroundTransparency = 0.3,
			BorderSizePixel = 0,
		}, {
			UICorner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 4) }),
			Label = React.createElement("TextLabel", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Text = statusText,
				FontFace = UIConfig.Font.Default,
				TextColor3 = color,
				TextSize = 12,
				TextXAlignment = Enum.TextXAlignment.Center,
			}),
		})
	end

	-- ── Map Features section (Impassable / No Build) — always freeform ──
	if #featureRows > 0 then
		-- Small divider label
		children.FeatureHeader = React.createElement("TextLabel", {
			LayoutOrder = n + 10,
			Size = UDim2.new(1, 0, 0, 18),
			BackgroundTransparency = 1,
			Text = "— Map Features —",
			FontFace = UIConfig.Font.Default,
			TextColor3 = Color3.fromRGB(140, 125, 100),
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Center,
		})

		for fi, row in ipairs(featureRows) do
			local usedPct: number = used[row.id] or 0
			local barFill = math.clamp(usedPct / 100, 0, 1)

			children["FRow_" .. tostring(fi)] = React.createElement("Frame", {
				LayoutOrder = n + 10 + fi,
				Size = UDim2.new(1, 0, 0, 24),
				BackgroundTransparency = 1,
			}, {
				Swatch = React.createElement("Frame", {
					Size = UDim2.new(0, 8, 0, 8),
					Position = UDim2.new(0, 2, 0.5, -4),
					BackgroundColor3 = row.color,
					BorderSizePixel = 0,
				}, { UICorner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 2) }) }),
				Label = React.createElement("TextLabel", {
					Size = UDim2.new(0, 54, 1, 0),
					Position = UDim2.new(0, 14, 0, 0),
					BackgroundTransparency = 1,
					Text = row.label,
					FontFace = UIConfig.Font.Default,
					TextColor3 = Color3.fromRGB(175, 160, 135),
					TextSize = 12,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				UsedLabel = React.createElement("TextLabel", {
					Size = UDim2.new(0, 38, 0, 16),
					Position = UDim2.new(0, 68, 0.5, -8),
					BackgroundTransparency = 1,
					Text = string.format("%.1f%%", usedPct),
					FontFace = UIConfig.Font.Default,
					TextColor3 = Color3.fromRGB(160, 145, 120),
					TextSize = 11,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				Bar = React.createElement("Frame", {
					Size = UDim2.new(1, -110, 0, 5),
					Position = UDim2.new(0, 110, 0.5, -2),
					BackgroundColor3 = Color3.fromRGB(30, 20, 12),
					BorderSizePixel = 0,
				}, {
					UICorner = React.createElement("UICorner", { CornerRadius = UDim.new(1, 0) }),
					Fill = React.createElement("Frame", {
						Size = UDim2.new(barFill, 0, 1, 0),
						BackgroundColor3 = row.color,
						BorderSizePixel = 0,
					}, { UICorner = React.createElement("UICorner", { CornerRadius = UDim.new(1, 0) }) }),
				}),
			})
		end
	end

	-- ── Outer layout ─────────────────────────────────────────────────────
	children.Layout = React.createElement("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		Padding = UDim.new(0, 2),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})

	-- AutomaticSize = Y: let the frame measure all rows rather than computing a
	-- hardcoded height that goes wrong when extra sections are added.
	return React.createElement("Frame", {
		LayoutOrder = props.layoutOrder,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	}, children)
end

return BudgetPanel
