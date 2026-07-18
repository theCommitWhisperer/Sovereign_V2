--!strict
-- BattleSetup: Battle Arena army builder panel.
-- Shown only in the "Battle Arena" game mode (gameStartData.mode == "BattleArena").
-- Each unit row has a drag slider per side plus +/- buttons for precision
-- (left-click ±1, right-click ±10).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local React = require(game.ReplicatedStorage.Packages.react)
local UIConfig = require(script.Parent.Parent.Parent.UIConfig)
local GameData = require(ReplicatedStorage.Shared.GameData)
local CombatConfig = require(ReplicatedStorage.Shared.GameData.CombatConfig)
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)

local BattleSetupDebug = DebugManager.createChannel("BattleSetup", false)

local ENEMY_FACTIONS = { "Viking", "Empire", "Tribes", "IronLegion" }
local CAP_OPTIONS = { 50, 100, 150, 200 }
local SLIDER_MAX = 50 -- per-unit slider range; +/- buttons go beyond if needed

local PANEL_WIDTH = 400
local ROW_HEIGHT = 44

local COLOR_BG = Color3.fromRGB(45, 35, 25)
local COLOR_ROW = Color3.fromRGB(60, 45, 30)
local COLOR_TRACK = Color3.fromRGB(35, 28, 20)
local COLOR_GOLD = Color3.fromRGB(200, 170, 90)
local COLOR_TEXT = Color3.fromRGB(230, 215, 185)
local COLOR_MINE = Color3.fromRGB(110, 170, 110)
local COLOR_ENEMY = Color3.fromRGB(190, 90, 80)

-- Build the pickable unit list once: combat-capable, non-civilian
local function buildUnitList(): { string }
	local list = {}
	for unitType, unitData in GameData.Units :: { [string]: any } do
		if unitData.combat then
			local profile = CombatConfig.getProfile(unitType, unitData.subtype)
			if not CombatConfig.hasTag(profile, "civilian") then
				table.insert(list, unitType)
			end
		end
	end
	table.sort(list)
	return list
end

-- ═══════════════════════════════════════════════════════════════════════════
-- CountSlider: compact controlled drag-slider (value comes from props)
-- ═══════════════════════════════════════════════════════════════════════════

local CountSlider = React.Component:extend("CountSlider")

function CountSlider:init()
	self.moveConnection = nil
	self.upConnection = nil

	self.applyFromX = function(trackInstance: GuiObject, mouseX: number)
		local relative = math.clamp(
			(mouseX - trackInstance.AbsolutePosition.X) / math.max(trackInstance.AbsoluteSize.X, 1),
			0,
			1
		)
		local newValue = math.floor(relative * self.props.max + 0.5)
		if newValue ~= self.props.value then
			self.props.onChanged(newValue)
		end
	end

	self.disconnect = function()
		if self.moveConnection then
			self.moveConnection:Disconnect()
			self.moveConnection = nil
		end
		if self.upConnection then
			self.upConnection:Disconnect()
			self.upConnection = nil
		end
	end

	self.startDrag = function(trackInstance: GuiObject)
		self.disconnect()
		self.applyFromX(trackInstance, UserInputService:GetMouseLocation().X)

		self.moveConnection = UserInputService.InputChanged:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch
			then
				self.applyFromX(trackInstance, UserInputService:GetMouseLocation().X)
			end
		end)
		self.upConnection = UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				self.disconnect()
			end
		end)
	end
end

function CountSlider:willUnmount()
	self.disconnect()
end

function CountSlider:render()
	local fillRatio = math.clamp(self.props.value / self.props.max, 0, 1)

	return React.createElement("TextButton", {
		Size = self.props.Size,
		Position = self.props.Position,
		BackgroundColor3 = COLOR_TRACK,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		[React.Event.MouseButton1Down] = function(rbx)
			self.startDrag(rbx)
		end,
	}, {
		Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 3) }),
		Fill = React.createElement("Frame", {
			Size = UDim2.new(fillRatio, 0, 1, 0),
			BackgroundColor3 = self.props.color,
			BackgroundTransparency = 0.25,
			BorderSizePixel = 0,
			ZIndex = 2,
		}, {
			Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 3) }),
		}),
		Handle = React.createElement("Frame", {
			Size = UDim2.new(0, 4, 1, 2),
			Position = UDim2.new(fillRatio, -2, 0, -1),
			BackgroundColor3 = COLOR_TEXT,
			BorderSizePixel = 0,
			ZIndex = 3,
		}),
	})
end

-- ═══════════════════════════════════════════════════════════════════════════
-- BattleSetup panel
-- ═══════════════════════════════════════════════════════════════════════════

local BattleSetup = React.Component:extend("BattleSetup")

function BattleSetup:init()
	self.unitList = buildUnitList()

	local counts = {}
	for _, unitType in self.unitList do
		counts[unitType] = { mine = 0, enemy = 0 }
	end

	self:setState({
		open = true,
		counts = counts,
		cap = self.props.armyCap or 100,
		enemyFactionIndex = 1,
	})

	local remoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
	self.gameEvent = remoteEvents:WaitForChild("GameEvent")

	self.setCount = function(unitType: string, side: string, value: number)
		local newCounts = table.clone(self.state.counts)
		local entry = table.clone(newCounts[unitType])
		entry[side] = math.max(0, value)
		newCounts[unitType] = entry
		self:setState({ counts = newCounts })
	end

	self.adjust = function(unitType: string, side: string, delta: number)
		self.setCount(unitType, side, self.state.counts[unitType][side] + delta)
	end

	self.totals = function(): (number, number)
		local mine, enemy = 0, 0
		for _, entry in self.state.counts :: { [string]: { mine: number, enemy: number } } do
			mine += entry.mine
			enemy += entry.enemy
		end
		return mine, enemy
	end

	self.fight = function()
		local mine, enemy = {}, {}
		for unitType, entry in self.state.counts :: { [string]: { mine: number, enemy: number } } do
			if entry.mine > 0 then
				table.insert(mine, { unitType = unitType, count = entry.mine })
			end
			if entry.enemy > 0 then
				table.insert(enemy, { unitType = unitType, count = entry.enemy })
			end
		end
		BattleSetupDebug:info("Fight!", { mine = #mine, enemy = #enemy })
		self.gameEvent:FireServer("ArenaSpawnArmies", {
			mine = mine,
			enemy = enemy,
			enemyFaction = ENEMY_FACTIONS[self.state.enemyFactionIndex],
		})
	end

	self.clearArena = function()
		self.gameEvent:FireServer("ArenaClear")
	end

	self.resetCounts = function()
		local counts = {}
		for _, unitType in self.unitList do
			counts[unitType] = { mine = 0, enemy = 0 }
		end
		self:setState({ counts = counts })
	end

	self.cycleCap = function()
		local index = table.find(CAP_OPTIONS, self.state.cap) or 2
		local nextCap = CAP_OPTIONS[(index % #CAP_OPTIONS) + 1]
		self:setState({ cap = nextCap })
		self.gameEvent:FireServer("ArenaSetCap", nextCap)
	end

	self.cycleEnemyFaction = function()
		self:setState({
			enemyFactionIndex = (self.state.enemyFactionIndex % #ENEMY_FACTIONS) + 1,
		})
	end
end

-- Small +/- button; left-click ±1, right-click ±10
local function stepButton(text: string, color: Color3, position: UDim2, onStep: (number) -> ())
	local sign = if text == "+" then 1 else -1
	return React.createElement("TextButton", {
		Size = UDim2.new(0, 16, 0, 18),
		Position = position,
		BackgroundColor3 = color,
		BackgroundTransparency = 0.4,
		BorderSizePixel = 0,
		Text = text,
		FontFace = UIConfig.Font.Title,
		TextSize = 14,
		TextColor3 = COLOR_TEXT,
		[React.Event.MouseButton1Click] = function()
			onStep(sign * 1)
		end,
		[React.Event.MouseButton2Click] = function()
			onStep(sign * 10)
		end,
	}, {
		Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 3) }),
	})
end

function BattleSetup:renderSideControls(unitType: string, side: string, color: Color3, xPos: number)
	local value = self.state.counts[unitType][side]

	return React.createElement("Frame", {
		Size = UDim2.new(0, 188, 0, 20),
		Position = UDim2.new(0, xPos, 0, 21),
		BackgroundTransparency = 1,
	}, {
		Minus = stepButton("-", color, UDim2.new(0, 0, 0, 1), function(delta)
			self.adjust(unitType, side, delta)
		end),
		Count = React.createElement("TextLabel", {
			Size = UDim2.new(0, 28, 0, 20),
			Position = UDim2.new(0, 17, 0, 0),
			BackgroundTransparency = 1,
			Text = tostring(value),
			FontFace = UIConfig.Font.Title,
			TextSize = 14,
			TextColor3 = if value > 0 then color else COLOR_TEXT,
		}),
		Plus = stepButton("+", color, UDim2.new(0, 46, 0, 1), function(delta)
			self.adjust(unitType, side, delta)
		end),
		Slider = React.createElement(CountSlider, {
			Size = UDim2.new(0, 118, 0, 12),
			Position = UDim2.new(0, 68, 0, 4),
			value = math.min(value, SLIDER_MAX),
			max = SLIDER_MAX,
			color = color,
			onChanged = function(newValue: number)
				self.setCount(unitType, side, newValue)
			end,
		}),
	})
end

function BattleSetup:renderUnitRow(unitType: string, layoutOrder: number)
	return React.createElement("Frame", {
		Size = UDim2.new(1, -6, 0, ROW_HEIGHT),
		LayoutOrder = layoutOrder,
		BackgroundColor3 = COLOR_ROW,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
	}, {
		Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 3) }),
		Name = React.createElement("TextLabel", {
			Size = UDim2.new(1, -12, 0, 18),
			Position = UDim2.new(0, 6, 0, 2),
			BackgroundTransparency = 1,
			Text = unitType,
			FontFace = UIConfig.Font.Default,
			TextSize = 13,
			TextColor3 = COLOR_TEXT,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}),
		Mine = self:renderSideControls(unitType, "mine", COLOR_MINE, 4),
		Enemy = self:renderSideControls(unitType, "enemy", COLOR_ENEMY, 198),
	})
end

function BattleSetup:render()
	return React.createElement("ScreenGui", {
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 50, -- above the HUD
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, {
		Content = self:renderContent(),
	})
end

function BattleSetup:renderContent()
	-- Collapsed: just the reopen button
	if not self.state.open then
		return React.createElement("TextButton", {
			Size = UDim2.new(0, 140, 0, 34),
			Position = UDim2.new(1, -150, 0, 90),
			BackgroundColor3 = COLOR_BG,
			BackgroundTransparency = 0.15,
			BorderSizePixel = 0,
			Text = "⚔ Battle Setup",
			FontFace = UIConfig.Font.Title,
			TextSize = 15,
			TextColor3 = COLOR_GOLD,
			[React.Event.MouseButton1Click] = function()
				self:setState({ open = true })
			end,
		}, {
			Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 5) }),
			Stroke = React.createElement("UIStroke", { Color = COLOR_GOLD, Thickness = 1.5 }),
		})
	end

	local mineTotal, enemyTotal = self.totals()
	local cap = self.state.cap
	local overCap = mineTotal > cap or enemyTotal > cap

	local rows = {
		Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			Padding = UDim.new(0, 3),
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
		}),
	}
	for index, unitType in self.unitList do
		rows[unitType] = self:renderUnitRow(unitType, index)
	end

	local function footerButton(text: string, position: UDim2, width: number, onClick: () -> ())
		return React.createElement("TextButton", {
			Size = UDim2.new(0, width, 0, 26),
			Position = position,
			BackgroundColor3 = COLOR_ROW,
			BackgroundTransparency = 0.25,
			BorderSizePixel = 0,
			Text = text,
			FontFace = UIConfig.Font.Title,
			TextSize = 14,
			TextColor3 = COLOR_TEXT,
			[React.Event.MouseButton1Click] = onClick,
		}, {
			Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 4) }),
		})
	end

	return React.createElement("Frame", {
		Size = UDim2.new(0, PANEL_WIDTH, 0, 560),
		Position = UDim2.new(1, -(PANEL_WIDTH + 10), 0.5, -280),
		BackgroundColor3 = COLOR_BG,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
	}, {
		Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 6) }),
		Stroke = React.createElement("UIStroke", { Color = COLOR_GOLD, Thickness = 2 }),

		Title = React.createElement("TextLabel", {
			Size = UDim2.new(1, 0, 0, 30),
			BackgroundTransparency = 1,
			Text = "⚔ Battle Setup",
			FontFace = UIConfig.Font.Title,
			TextSize = 18,
			TextColor3 = COLOR_GOLD,
		}),
		CloseButton = React.createElement("TextButton", {
			Size = UDim2.new(0, 24, 0, 24),
			Position = UDim2.new(1, -28, 0, 4),
			BackgroundTransparency = 1,
			Text = "✕",
			FontFace = UIConfig.Font.Title,
			TextSize = 16,
			TextColor3 = COLOR_TEXT,
			[React.Event.MouseButton1Click] = function()
				self:setState({ open = false })
			end,
		}),
		Hint = React.createElement("TextLabel", {
			Size = UDim2.new(1, -12, 0, 16),
			Position = UDim2.new(0, 6, 0, 28),
			BackgroundTransparency = 1,
			Text = "Drag sliders  ·  Left-click ±1  ·  Right-click ±10",
			FontFace = UIConfig.Font.Default,
			TextSize = 12,
			TextColor3 = COLOR_TEXT,
			TextTransparency = 0.35,
		}),
		ColumnHeader = React.createElement("Frame", {
			Size = UDim2.new(1, -6, 0, 18),
			Position = UDim2.new(0, 3, 0, 46),
			BackgroundTransparency = 1,
		}, {
			MineLabel = React.createElement("TextLabel", {
				Size = UDim2.new(0, 188, 1, 0),
				Position = UDim2.new(0, 4, 0, 0),
				BackgroundTransparency = 1,
				Text = `Yours ({mineTotal}/{cap})`,
				FontFace = UIConfig.Font.Default,
				TextSize = 12,
				TextColor3 = COLOR_MINE,
			}),
			EnemyLabel = React.createElement("TextLabel", {
				Size = UDim2.new(0, 188, 1, 0),
				Position = UDim2.new(0, 198, 0, 0),
				BackgroundTransparency = 1,
				Text = `Enemy ({enemyTotal}/{cap})`,
				FontFace = UIConfig.Font.Default,
				TextSize = 12,
				TextColor3 = COLOR_ENEMY,
			}),
		}),

		UnitScroll = React.createElement("ScrollingFrame", {
			Size = UDim2.new(1, -8, 1, -180),
			Position = UDim2.new(0, 4, 0, 66),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 4,
			ScrollBarImageColor3 = COLOR_GOLD,
			CanvasSize = UDim2.new(0, 0, 0, #self.unitList * (ROW_HEIGHT + 3) + 8),
		}, rows),

		EnemyFactionButton = footerButton(
			`Enemy: {ENEMY_FACTIONS[self.state.enemyFactionIndex]}`,
			UDim2.new(0, 8, 1, -32),
			130,
			self.cycleEnemyFaction
		),
		CapButton = footerButton(`Cap: {cap}`, UDim2.new(0, 146, 1, -32), 76, self.cycleCap),
		ResetButton = footerButton("Reset", UDim2.new(0, 230, 1, -32), 64, self.resetCounts),

		FightButton = React.createElement("TextButton", {
			Size = UDim2.new(0, 170, 0, 34),
			Position = UDim2.new(0, 8, 1, -74),
			BackgroundColor3 = if overCap then Color3.fromRGB(90, 60, 50) else Color3.fromRGB(150, 60, 40),
			BackgroundTransparency = 0.1,
			BorderSizePixel = 0,
			Text = if overCap then "OVER CAP" else "⚔ FIGHT",
			FontFace = UIConfig.Font.Title,
			TextSize = 17,
			TextColor3 = if overCap then Color3.fromRGB(180, 160, 140) else Color3.fromRGB(255, 235, 200),
			[React.Event.MouseButton1Click] = function()
				if not overCap and mineTotal > 0 and enemyTotal > 0 then
					self.fight()
				end
			end,
		}, {
			Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 5) }),
			Stroke = React.createElement("UIStroke", { Color = COLOR_GOLD, Thickness = 1.5 }),
		}),
		ClearButton = React.createElement("TextButton", {
			Size = UDim2.new(0, 120, 0, 34),
			Position = UDim2.new(0, 190, 1, -74),
			BackgroundColor3 = Color3.fromRGB(80, 50, 40),
			BackgroundTransparency = 0.25,
			BorderSizePixel = 0,
			Text = "Clear Arena",
			FontFace = UIConfig.Font.Title,
			TextSize = 14,
			TextColor3 = COLOR_TEXT,
			[React.Event.MouseButton1Click] = self.clearArena,
		}, {
			Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 5) }),
		}),
	})
end

return BattleSetup
