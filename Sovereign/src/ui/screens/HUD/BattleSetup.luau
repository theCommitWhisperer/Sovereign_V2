--!strict
-- BattleSetup: Battle Arena army builder panel.
-- Shown only in the "Battle Arena" game mode (gameStartData.mode == "BattleArena").
-- Pick counts for your army and the enemy army, then FIGHT.
-- Left-click +/- changes by 1, right-click by 10.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(game.ReplicatedStorage.Packages.react)
local UIConfig = require(script.Parent.Parent.Parent.UIConfig)
local GameData = require(ReplicatedStorage.Shared.GameData)
local CombatConfig = require(ReplicatedStorage.Shared.GameData.CombatConfig)
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)

local BattleSetupDebug = DebugManager.createChannel("BattleSetup", false)

local ENEMY_FACTIONS = { "Viking", "Empire", "Tribes", "IronLegion" }
local CAP_OPTIONS = { 50, 100, 150, 200 }

local COLOR_BG = Color3.fromRGB(45, 35, 25)
local COLOR_ROW = Color3.fromRGB(60, 45, 30)
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

	self.adjust = function(unitType: string, side: string, delta: number)
		local newCounts = table.clone(self.state.counts)
		local entry = table.clone(newCounts[unitType])
		entry[side] = math.max(0, entry[side] + delta)
		newCounts[unitType] = entry
		self:setState({ counts = newCounts })
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
		local current = self.state.cap
		local index = table.find(CAP_OPTIONS, current) or 2
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
local function stepButton(text: string, color: Color3, layoutOrder: number, onStep: (number) -> ())
	local sign = if text == "+" then 1 else -1
	return React.createElement("TextButton", {
		Size = UDim2.new(0, 18, 0, 18),
		LayoutOrder = layoutOrder,
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

function BattleSetup:renderUnitRow(unitType: string, layoutOrder: number)
	local entry = self.state.counts[unitType]

	local function sideControls(side: string, color: Color3, xPos: number)
		return React.createElement("Frame", {
			Size = UDim2.new(0, 92, 1, 0),
			Position = UDim2.new(0, xPos, 0, 0),
			BackgroundTransparency = 1,
		}, {
			Layout = React.createElement("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				Padding = UDim.new(0, 3),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
			Minus = stepButton("-", color, 1, function(delta)
				self.adjust(unitType, side, delta)
			end),
			Count = React.createElement("TextLabel", {
				Size = UDim2.new(0, 32, 0, 18),
				LayoutOrder = 2,
				BackgroundTransparency = 1,
				Text = tostring(entry[side]),
				FontFace = UIConfig.Font.Title,
				TextSize = 14,
				TextColor3 = if entry[side] > 0 then color else COLOR_TEXT,
			}),
			Plus = stepButton("+", color, 3, function(delta)
				self.adjust(unitType, side, delta)
			end),
		})
	end

	return React.createElement("Frame", {
		Size = UDim2.new(1, -6, 0, 24),
		LayoutOrder = layoutOrder,
		BackgroundColor3 = COLOR_ROW,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
	}, {
		Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 3) }),
		Name = React.createElement("TextLabel", {
			Size = UDim2.new(0, 116, 1, 0),
			Position = UDim2.new(0, 6, 0, 0),
			BackgroundTransparency = 1,
			Text = unitType,
			FontFace = UIConfig.Font.Default,
			TextSize = 13,
			TextColor3 = COLOR_TEXT,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}),
		Mine = sideControls("mine", COLOR_MINE, 122),
		Enemy = sideControls("enemy", COLOR_ENEMY, 218),
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

	local function footerButton(text: string, color: Color3, xScale: number, width: number, onClick: () -> ())
		return React.createElement("TextButton", {
			Size = UDim2.new(0, width, 0, 26),
			Position = UDim2.new(xScale, 0, 1, -32),
			BackgroundColor3 = color,
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
		Size = UDim2.new(0, 330, 0, 520),
		Position = UDim2.new(1, -340, 0.5, -260),
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
			Text = "Left-click ±1  ·  Right-click ±10",
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
				Size = UDim2.new(0, 92, 1, 0),
				Position = UDim2.new(0, 122, 0, 0),
				BackgroundTransparency = 1,
				Text = `Yours ({mineTotal}/{cap})`,
				FontFace = UIConfig.Font.Default,
				TextSize = 12,
				TextColor3 = COLOR_MINE,
			}),
			EnemyLabel = React.createElement("TextLabel", {
				Size = UDim2.new(0, 92, 1, 0),
				Position = UDim2.new(0, 218, 0, 0),
				BackgroundTransparency = 1,
				Text = `Enemy ({enemyTotal}/{cap})`,
				FontFace = UIConfig.Font.Default,
				TextSize = 12,
				TextColor3 = COLOR_ENEMY,
			}),
		}),

		UnitScroll = React.createElement("ScrollingFrame", {
			Size = UDim2.new(1, -8, 1, -140),
			Position = UDim2.new(0, 4, 0, 66),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 4,
			ScrollBarImageColor3 = COLOR_GOLD,
			CanvasSize = UDim2.new(0, 0, 0, #self.unitList * 27 + 8),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
		}, rows),

		EnemyFactionButton = footerButton(
			`Enemy: {ENEMY_FACTIONS[self.state.enemyFactionIndex]}`,
			COLOR_ROW,
			0.02,
			120,
			self.cycleEnemyFaction
		),
		CapButton = footerButton(`Cap: {cap}`, COLOR_ROW, 0.42, 70, self.cycleCap),
		ResetButton = footerButton("Reset", COLOR_ROW, 0.68, 60, self.resetCounts),

		FightButton = React.createElement("TextButton", {
			Size = UDim2.new(0, 150, 0, 32),
			Position = UDim2.new(0.02, 0, 1, -70),
			BackgroundColor3 = if overCap then Color3.fromRGB(90, 60, 50) else Color3.fromRGB(150, 60, 40),
			BackgroundTransparency = 0.1,
			BorderSizePixel = 0,
			Text = if overCap then "OVER CAP" else "⚔ FIGHT",
			FontFace = UIConfig.Font.Title,
			TextSize = 17,
			TextColor3 = if overCap then Color3.fromRGB(180, 160, 140) else Color3.fromRGB(255, 235, 200),
			[React.Event.MouseButton1Click] = function()
				if not overCap and (mineTotal > 0 and enemyTotal > 0) then
					self.fight()
				end
			end,
		}, {
			Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 5) }),
			Stroke = React.createElement("UIStroke", { Color = COLOR_GOLD, Thickness = 1.5 }),
		}),
		ClearButton = React.createElement("TextButton", {
			Size = UDim2.new(0, 120, 0, 32),
			Position = UDim2.new(0.55, 0, 1, -70),
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
