--!strict
-- UnitPanel: unit selection management panel with generous padding, outer gold borders, and zero component clipping.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local React = require(ReplicatedStorage.Packages.react)

local Theme = require(script.Parent.Parent.Theme)
local FormationsData = require(ReplicatedStorage.Shared.GameData.FormationsData)
local HUDStore = require(script.Parent.Parent.state.HUDStore)

export type Props = {
	selectedUnits: { Model },
	selectedStance: string?,
	selectedFormation: string?,
	onStanceSelected: (string) -> (),
	onFormationSelected: (string) -> (),
	onCivilianOrder: ((string) -> ())?,
	compact: boolean?,
	LayoutOrder: number?,
}

local STANCE_ORDER = { "March", "Defend", "Skirmish", "Attack" }
local STANCE_ICON: { [string]: string } = {
	March = "🥾",
	Defend = "🛡",
	Skirmish = "🏹",
	Attack = "⚔",
}

local UNIT_SHADOW_ICON: { [string]: string } = {
	Peasant = "🧑‍🌾",
	Militia = "🛡️",
	Footman = "⚔️",
	Knight = "🏇",
	Archer = "🏹",
	Crossbowman = "🎯",
	Spearman = "🔱",
	Pikeman = "🗡️",
	Default = "🎖️",
}

local UNIT_STATS_SUMMARY = {
	{ name = "Peasant", hp = 50, atk = "Melee 5", def = 0, spd = 12.0, role = "Gatherer / Builder" },
	{ name = "Militia", hp = 80, atk = "Melee 12", def = 2, spd = 11.5, role = "Light Infantry" },
	{ name = "Footman", hp = 120, atk = "Melee 18", def = 5, spd = 11.0, role = "Medium Infantry" },
	{ name = "Knight", hp = 220, atk = "Melee 32", def = 10, spd = 14.0, role = "Heavy Cavalry" },
	{ name = "Archer", hp = 70, atk = "Ranged 14", def = 1, spd = 11.5, role = "Ranged Support" },
	{ name = "Crossbowman", hp = 85, atk = "Ranged 22", def = 3, spd = 10.5, role = "Armor Piercer" },
	{ name = "Spearman", hp = 100, atk = "Melee 15", def = 3, spd = 11.0, role = "Anti-Cavalry" },
	{ name = "Pikeman", hp = 130, atk = "Melee 22", def = 6, spd = 10.0, role = "Heavy Anti-Cavalry" },
}

local STANCE_SUMMARY = {
	{ name = "March", atk = "−50%", def = "+10%", spd = "+25%", desc = "Fast travel, reduced combat efficiency" },
	{ name = "Defend", atk = "−15%", def = "+35%", spd = "−20%", desc = "Hold ground, high physical armor bonus" },
	{ name = "Skirmish", atk = "+10%", def = "0%", spd = "+10%", desc = "Hit-and-run, maintain optimal range" },
	{ name = "Attack", atk = "+30%", def = "−15%", spd = "0%", desc = "Aggressive charge, maximum damage" },
}

local FORMATION_SUMMARY = {
	{ name = "Line", def = "Standard", atk = "Standard", spd = "Standard", min = 2, desc = "Balanced front-line engagement" },
	{ name = "Wedge", def = "−10%", atk = "+25%", spd = "+10%", min = 3, desc = "Aggressive spearhead penetration" },
	{ name = "Square", def = "+30%", atk = "−10%", spd = "−25%", min = 4, desc = "Defensive perimeter against flanks" },
	{ name = "Column", def = "−15%", atk = "0%", spd = "+30%", min = 2, desc = "Rapid march through narrow passes" },
	{ name = "Circle", def = "+40%", atk = "−20%", spd = "0%", min = 5, desc = "360° defensive hold around high priority targets" },
	{ name = "Echelon", def = "+10%", atk = "+15%", spd = "0%", min = 3, desc = "Staggered flank attack angle" },
}

-- Compact Modular Info Button Component (15px square)
local function InfoButton(props: { active: boolean, onActivated: () -> (), size: number?, LayoutOrder: number? })
	local btnSize = props.size or 15
	return React.createElement("TextButton", {
		Name = "InfoBtn",
		Size = UDim2.fromOffset(btnSize, btnSize),
		BackgroundColor3 = if props.active then Theme.Color.Accent else Theme.Color.SurfaceRaised,
		BackgroundTransparency = if props.active then 0 else 0.4,
		AutoButtonColor = true,
		Text = "i",
		FontFace = Theme.FontFace.BodyBold,
		TextSize = 10,
		TextColor3 = if props.active then Theme.Color.OnAccent else Theme.Color.TextSecondary,
		LayoutOrder = props.LayoutOrder,
		[React.Event.Activated] = props.onActivated,
	}, {
		Corner = React.createElement("UICorner", { CornerRadius = UDim.new(1, 0) }),
		Stroke = React.createElement("UIStroke", {
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Color = Theme.Color.Accent,
			Transparency = if props.active then 0 else 0.3,
			Thickness = 1.2,
		}),
	})
end

-- Formation Diagram Visualizer (renders clean dot grid)
local function FormationVisual(props: { shape: string, active: boolean, color: Color3 })
	local dots: { [string]: any } = {}
	local shape = props.shape or "line"

	local function addDot(key: string, xRatio: number, yRatio: number)
		dots[key] = React.createElement("Frame", {
			Size = UDim2.fromOffset(4, 4),
			Position = UDim2.new(xRatio, 0, yRatio, 0),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = props.color,
			BorderSizePixel = 0,
		}, {
			Corner = React.createElement("UICorner", { CornerRadius = UDim.new(1, 0) }),
		})
	end

	if shape == "wedge" then
		addDot("1", 0.5, 0.2)
		addDot("2", 0.35, 0.5)
		addDot("3", 0.65, 0.5)
		addDot("4", 0.2, 0.8)
		addDot("5", 0.8, 0.8)
	elseif shape == "square" then
		addDot("1", 0.25, 0.25)
		addDot("2", 0.75, 0.25)
		addDot("3", 0.25, 0.75)
		addDot("4", 0.75, 0.75)
		addDot("5", 0.5, 0.5)
	elseif shape == "column" then
		addDot("1", 0.35, 0.2)
		addDot("2", 0.65, 0.2)
		addDot("3", 0.35, 0.5)
		addDot("4", 0.65, 0.5)
		addDot("5", 0.35, 0.8)
		addDot("6", 0.65, 0.8)
	elseif shape == "circle" then
		addDot("1", 0.5, 0.15)
		addDot("2", 0.85, 0.5)
		addDot("3", 0.5, 0.85)
		addDot("4", 0.15, 0.5)
		addDot("5", 0.5, 0.5)
	elseif shape == "echelon" then
		addDot("1", 0.2, 0.2)
		addDot("2", 0.35, 0.35)
		addDot("3", 0.5, 0.5)
		addDot("4", 0.65, 0.65)
		addDot("5", 0.8, 0.8)
	else -- line
		addDot("1", 0.15, 0.5)
		addDot("2", 0.32, 0.5)
		addDot("3", 0.5, 0.5)
		addDot("4", 0.68, 0.5)
		addDot("5", 0.85, 0.5)
	end

	return React.createElement("Frame", {
		Size = UDim2.new(1, 0, 0, 30),
		Position = UDim2.new(0, 0, 0, 2),
		BackgroundTransparency = 1,
	}, dots)
end

local function UnitPanel(props: Props)
	local showUnitInfo, setShowUnitInfo = React.useState(false)
	local showStanceInfo, setShowStanceInfo = React.useState(false)
	local showFormationInfo, setShowFormationInfo = React.useState(false)

	-- Group units by type name
	local counts: { [string]: number } = {}
	local total = 0
	local hasCivilian = false

	for _, unit in props.selectedUnits do
		local kind = unit:GetAttribute("UnitType") or unit:GetAttribute("UnitKind") or unit.Name
		counts[kind] = (counts[kind] or 0) + 1
		total += 1
		if kind == "Peasant" or kind == "Builder" or kind == "Gatherer" then
			hasCivilian = true
		end
	end

	local breakdown: { { kind: string, count: number } } = {}
	local selectedKindSet: { [string]: boolean } = {}
	for kind, c in counts do
		table.insert(breakdown, { kind = kind, count = c })
		selectedKindSet[kind] = true
	end
	table.sort(breakdown, function(a, b)
		return a.count > b.count
	end)

	-- LEFT COLUMN (45% Width): Unit Breakdown + Stances
	local leftChildren: { [string]: any } = {
		Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),

		-- Header: Total Units + InfoButton
		TitleRow = React.createElement("Frame", {
			Size = UDim2.new(1, 0, 0, 22),
			BackgroundTransparency = 1,
			LayoutOrder = 1,
		}, {
			Layout = React.createElement("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 6),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
			Title = React.createElement("TextLabel", {
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.new(0, 0, 1, 0),
				BackgroundTransparency = 1,
				Text = ("👥 %d Selected"):format(total),
				FontFace = Theme.FontFace.Display,
				TextSize = Theme.TextSize.Heading,
				TextColor3 = Theme.Color.Accent,
				TextXAlignment = Enum.TextXAlignment.Left,
				LayoutOrder = 1,
			}),
			UnitInfoBtn = React.createElement(InfoButton, {
				active = showUnitInfo,
				size = 15,
				LayoutOrder = 2,
				onActivated = function()
					setShowUnitInfo(not showUnitInfo)
				end,
			}),
		}),
	}

	-- Composition: SQUARE CARDS for units (52x52px) with Outer Gold Border Stroke
	local unitSquareCards: { [string]: any } = {
		Padding = React.createElement("UIPadding", {
			PaddingTop = UDim.new(0, 3),
			PaddingBottom = UDim.new(0, 3),
			PaddingLeft = UDim.new(0, 3),
			PaddingRight = UDim.new(0, 3),
		}),
		Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}
	for i, entry in breakdown do
		local icon = UNIT_SHADOW_ICON[entry.kind] or UNIT_SHADOW_ICON.Default
		unitSquareCards[entry.kind] = React.createElement("Frame", {
			Size = UDim2.fromOffset(52, 52),
			BackgroundColor3 = Theme.Color.SurfaceRaised,
			BackgroundTransparency = Theme.Transparency.Card,
			ClipsDescendants = true,
			LayoutOrder = i,
		}, {
			Corner = React.createElement("UICorner", { CornerRadius = Theme.corner(Theme.Metrics.RadiusSmall) }),
			-- OUTER GOLD BORDER STROKE ON THE CARD CONTAINER (ApplyStrokeMode.Border)
			OuterStroke = React.createElement("UIStroke", {
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Color = Theme.Color.Accent,
				Transparency = 0.2,
				Thickness = 2,
			}),
			IconLabel = React.createElement("TextLabel", {
				Size = UDim2.new(1, 0, 0, 26),
				Position = UDim2.new(0, 0, 0, 2),
				BackgroundTransparency = 1,
				Text = icon,
				FontFace = Theme.FontFace.Display,
				TextSize = 20,
				TextColor3 = Theme.Color.TextPrimary,
				TextStrokeTransparency = 1,
			}),
			NameLabel = React.createElement("TextLabel", {
				Size = UDim2.new(1, -2, 0, 16),
				Position = UDim2.new(0, 1, 0, 30),
				BackgroundTransparency = 1,
				Text = string.format("×%d", entry.count),
				FontFace = Theme.FontFace.BodyBold,
				TextSize = 11,
				TextColor3 = Theme.Color.Accent,
				TextXAlignment = Enum.TextXAlignment.Center,
				TextStrokeTransparency = 1,
				TextTruncate = Enum.TextTruncate.AtEnd,
			}),
		})
	end

	leftChildren.CompositionFrame = React.createElement("ScrollingFrame", {
		Size = UDim2.new(1, 0, 0, 60),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollingDirection = Enum.ScrollingDirection.X,
		ScrollBarThickness = 3,
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		CanvasSize = UDim2.fromScale(0, 0),
		LayoutOrder = 2,
	}, React.createElement("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, unitSquareCards))

	-- Stances Header + InfoButton
	leftChildren.StanceHeaderFrame = React.createElement("Frame", {
		Size = UDim2.new(1, 0, 0, 22),
		BackgroundTransparency = 1,
		LayoutOrder = 3,
	}, {
		Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		Header = React.createElement("TextLabel", {
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.new(0, 0, 1, 0),
			BackgroundTransparency = 1,
			Text = "🗡 Combat Stances",
			FontFace = Theme.FontFace.Display,
			TextSize = Theme.TextSize.Heading,
			TextColor3 = Theme.Color.Accent,
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = 1,
		}),
		StanceInfoBtn = React.createElement(InfoButton, {
			active = showStanceInfo,
			size = 15,
			LayoutOrder = 2,
			onActivated = function()
				setShowStanceInfo(not showStanceInfo)
			end,
		}),
	})

	-- 4 Combat Stances + "Return to Keep" integrated directly as compact 36x36px icon-only tiles
	local stanceSquareButtons: { [string]: any } = {
		Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}
	for i, stance in STANCE_ORDER do
		local active = props.selectedStance == stance
		stanceSquareButtons[stance] = React.createElement("TextButton", {
			Name = stance,
			Size = UDim2.fromOffset(36, 36),
			BackgroundColor3 = if active then Theme.Color.CelticGreen else Theme.Color.SurfaceRaised,
			BackgroundTransparency = if active then 0 else Theme.Transparency.Card,
			AutoButtonColor = true,
			Text = "",
			ClipsDescendants = true,
			LayoutOrder = i,
			[React.Event.Activated] = function()
				props.onStanceSelected(stance)
			end,
		}, {
			Corner = React.createElement("UICorner", { CornerRadius = Theme.corner(Theme.Metrics.RadiusSmall) }),
			Stroke = React.createElement("UIStroke", {
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Color = Theme.Color.Accent,
				Transparency = if active then 0 else 0.25,
				Thickness = if active then 2.5 else 1.8,
			}),
			IconLabel = React.createElement("TextLabel", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Text = STANCE_ICON[stance] or "•",
				FontFace = Theme.FontFace.Display,
				TextSize = 20,
				TextColor3 = if active then Theme.Color.TextPrimary else Theme.Color.TextSecondary,
				TextXAlignment = Enum.TextXAlignment.Center,
				TextYAlignment = Enum.TextYAlignment.Center,
				TextStrokeTransparency = 1,
			}),
		})
	end

	-- 5th Card: Return to Keep stance button (icon-only 36x36px)
	if hasCivilian and props.onCivilianOrder then
		stanceSquareButtons.ReturnToKeep = React.createElement("TextButton", {
			Name = "ReturnToKeep",
			Size = UDim2.fromOffset(36, 36),
			BackgroundColor3 = Theme.Color.Action,
			BackgroundTransparency = Theme.Transparency.CardActive,
			AutoButtonColor = true,
			Text = "",
			ClipsDescendants = true,
			LayoutOrder = 5,
			[React.Event.Activated] = function()
				if props.onCivilianOrder then
					props.onCivilianOrder("ReturnToKeep")
				end
			end,
		}, {
			Corner = React.createElement("UICorner", { CornerRadius = Theme.corner(Theme.Metrics.RadiusSmall) }),
			Stroke = React.createElement("UIStroke", {
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Color = Theme.Color.Accent,
				Transparency = 0.2,
				Thickness = 1.8,
			}),
			IconLabel = React.createElement("TextLabel", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Text = "🏰",
				FontFace = Theme.FontFace.Display,
				TextSize = 20,
				TextColor3 = Theme.Color.TextPrimary,
				TextXAlignment = Enum.TextXAlignment.Center,
				TextYAlignment = Enum.TextYAlignment.Center,
				TextStrokeTransparency = 1,
			}),
		})
	end

	leftChildren.StanceGrid = React.createElement("Frame", {
		Size = UDim2.new(1, 0, 0, 36),
		BackgroundTransparency = 1,
		LayoutOrder = 4,
	}, stanceSquareButtons)

	-- RIGHT COLUMN (55% Width): Available Formations Grid (56x56px tiles with generous padding)
	local availableFormations = {}
	for _, name in FormationsData.Order do
		local cfg = FormationsData.get(name)
		local minUnits = (cfg and cfg.minUnits) or 1
		if total >= minUnits then
			table.insert(availableFormations, name)
		end
	end

	local formationSquareButtons: { [string]: any } = {
		Layout = React.createElement("UIGridLayout", {
			CellSize = UDim2.fromOffset(56, 56),
			CellPadding = UDim2.fromOffset(8, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}
	for i, name in availableFormations do
		local cfg = FormationsData.get(name)
		local active = props.selectedFormation == name
		local shape = (cfg and cfg.shape) or "line"

		formationSquareButtons[name] = React.createElement("TextButton", {
			Name = name,
			BackgroundColor3 = if active then Theme.Color.Accent else Theme.Color.SurfaceRaised,
			BackgroundTransparency = if active then 0 else Theme.Transparency.Card,
			AutoButtonColor = true,
			Text = "",
			ClipsDescendants = true,
			LayoutOrder = i,
			[React.Event.Activated] = function()
				props.onFormationSelected(name)
			end,
		}, {
			Corner = React.createElement("UICorner", { CornerRadius = Theme.corner(Theme.Metrics.RadiusSmall) }),
			Stroke = React.createElement("UIStroke", {
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Color = Theme.Color.Accent,
				Transparency = if active then 0 else 0.25,
				Thickness = if active then 2.5 else 1.8,
			}),
			Visual = React.createElement(FormationVisual, {
				shape = shape,
				active = active,
				color = if active then Theme.Color.OnAccent else Theme.Color.Accent,
			}),
			NameLabel = React.createElement("TextLabel", {
				Size = UDim2.new(1, 0, 0, 16),
				Position = UDim2.new(0, 0, 0, 34),
				BackgroundTransparency = 1,
				Text = name,
				FontFace = Theme.FontFace.BodyBold,
				TextSize = 10,
				TextColor3 = if active then Theme.Color.OnAccent else Theme.Color.TextPrimary,
				TextXAlignment = Enum.TextXAlignment.Center,
				TextStrokeTransparency = 1,
				TextTruncate = Enum.TextTruncate.AtEnd,
			}),
		})
	end

	-- 1. Unit Stats TABLE Rows
	local unitTableRows: { [string]: any } = {
		Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			Padding = UDim.new(0, 2),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		HeaderRow = React.createElement("Frame", {
			Size = UDim2.new(1, 0, 0, 24),
			BackgroundColor3 = Theme.Color.SurfaceRaised,
			BackgroundTransparency = 0.3,
			LayoutOrder = 0,
		}, {
			Corner = React.createElement("UICorner", { CornerRadius = Theme.corner(Theme.Metrics.RadiusSmall) }),
			Layout = React.createElement("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }),
			Padding = React.createElement("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4) }),
			ColUnit = React.createElement("TextLabel", { Size = UDim2.new(0, 100, 1, 0), BackgroundTransparency = 1, Text = "Unit", FontFace = Theme.FontFace.Display, TextSize = 16, TextColor3 = Theme.Color.Accent, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 1 }),
			ColHP = React.createElement("TextLabel", { Size = UDim2.new(0, 45, 1, 0), BackgroundTransparency = 1, Text = "HP", FontFace = Theme.FontFace.Display, TextSize = 16, TextColor3 = Theme.Color.Accent, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 2 }),
			ColAtk = React.createElement("TextLabel", { Size = UDim2.new(0, 115, 1, 0), BackgroundTransparency = 1, Text = "Attack", FontFace = Theme.FontFace.Display, TextSize = 16, TextColor3 = Theme.Color.Accent, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 3 }),
			ColArm = React.createElement("TextLabel", { Size = UDim2.new(0, 45, 1, 0), BackgroundTransparency = 1, Text = "Armor", FontFace = Theme.FontFace.Display, TextSize = 16, TextColor3 = Theme.Color.Accent, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 4 }),
			ColSpd = React.createElement("TextLabel", { Size = UDim2.new(0, 45, 1, 0), BackgroundTransparency = 1, Text = "Speed", FontFace = Theme.FontFace.Display, TextSize = 16, TextColor3 = Theme.Color.Accent, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 5 }),
			ColRole = React.createElement("TextLabel", { Size = UDim2.new(1, -350, 1, 0), BackgroundTransparency = 1, Text = "Role", FontFace = Theme.FontFace.Display, TextSize = 16, TextColor3 = Theme.Color.Accent, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 6 }),
		}),
	}
	for i, spec in UNIT_STATS_SUMMARY do
		local isSelected = selectedKindSet[spec.name] == true
		unitTableRows[spec.name] = React.createElement("Frame", {
			Size = UDim2.new(1, 0, 0, 24),
			BackgroundColor3 = if isSelected then Theme.Color.SurfaceRaised else Theme.Color.Surface,
			BackgroundTransparency = if isSelected then 0.15 else 1,
			LayoutOrder = i,
		}, {
			Corner = React.createElement("UICorner", { CornerRadius = Theme.corner(Theme.Metrics.RadiusSmall) }),
			Stroke = isSelected and React.createElement("UIStroke", { Color = Theme.Color.Accent, Thickness = 1.5, Transparency = 0.2 }) or nil,
			Layout = React.createElement("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }),
			Padding = React.createElement("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4) }),
			ColUnit = React.createElement("TextLabel", { Size = UDim2.new(0, 100, 1, 0), BackgroundTransparency = 1, Text = spec.name, FontFace = if isSelected then Theme.FontFace.BodyBold else Theme.FontFace.Body, TextSize = 15, TextColor3 = if isSelected then Theme.Color.Accent else Theme.Color.TextPrimary, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 1 }),
			ColHP = React.createElement("TextLabel", { Size = UDim2.new(0, 45, 1, 0), BackgroundTransparency = 1, Text = tostring(spec.hp), FontFace = if isSelected then Theme.FontFace.BodyBold else Theme.FontFace.Body, TextSize = 15, TextColor3 = if isSelected then Theme.Color.Accent else Theme.Color.TextSecondary, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 2 }),
			ColAtk = React.createElement("TextLabel", { Size = UDim2.new(0, 115, 1, 0), BackgroundTransparency = 1, Text = spec.atk, FontFace = if isSelected then Theme.FontFace.BodyBold else Theme.FontFace.Body, TextSize = 15, TextColor3 = if isSelected then Theme.Color.Accent else Theme.Color.TextSecondary, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 3 }),
			ColArm = React.createElement("TextLabel", { Size = UDim2.new(0, 45, 1, 0), BackgroundTransparency = 1, Text = tostring(spec.def), FontFace = if isSelected then Theme.FontFace.BodyBold else Theme.FontFace.Body, TextSize = 15, TextColor3 = if isSelected then Theme.Color.Accent else Theme.Color.TextSecondary, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 4 }),
			ColSpd = React.createElement("TextLabel", { Size = UDim2.new(0, 45, 1, 0), BackgroundTransparency = 1, Text = string.format("%.1f", spec.spd), FontFace = if isSelected then Theme.FontFace.BodyBold else Theme.FontFace.Body, TextSize = 15, TextColor3 = if isSelected then Theme.Color.Accent else Theme.Color.TextSecondary, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 5 }),
			ColRole = React.createElement("TextLabel", { Size = UDim2.new(1, -350, 1, 0), BackgroundTransparency = 1, Text = spec.role, FontFace = if isSelected then Theme.FontFace.BodyBold else Theme.FontFace.Body, TextSize = 15, TextColor3 = if isSelected then Theme.Color.Accent else Theme.Color.TextSecondary, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 6 }),
		})
	end

	-- 2. Stance Stats TABLE Rows
	local stanceTableRows: { [string]: any } = {
		Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			Padding = UDim.new(0, 2),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		HeaderRow = React.createElement("Frame", {
			Size = UDim2.new(1, 0, 0, 24),
			BackgroundColor3 = Theme.Color.SurfaceRaised,
			BackgroundTransparency = 0.3,
			LayoutOrder = 0,
		}, {
			Corner = React.createElement("UICorner", { CornerRadius = Theme.corner(Theme.Metrics.RadiusSmall) }),
			Layout = React.createElement("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }),
			Padding = React.createElement("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4) }),
			ColStance = React.createElement("TextLabel", { Size = UDim2.new(0, 90, 1, 0), BackgroundTransparency = 1, Text = "Stance", FontFace = Theme.FontFace.Display, TextSize = 16, TextColor3 = Theme.Color.Accent, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 1 }),
			ColAtk = React.createElement("TextLabel", { Size = UDim2.new(0, 55, 1, 0), BackgroundTransparency = 1, Text = "Attack", FontFace = Theme.FontFace.Display, TextSize = 16, TextColor3 = Theme.Color.Accent, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 2 }),
			ColDef = React.createElement("TextLabel", { Size = UDim2.new(0, 55, 1, 0), BackgroundTransparency = 1, Text = "Defense", FontFace = Theme.FontFace.Display, TextSize = 16, TextColor3 = Theme.Color.Accent, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 3 }),
			ColSpd = React.createElement("TextLabel", { Size = UDim2.new(0, 55, 1, 0), BackgroundTransparency = 1, Text = "Speed", FontFace = Theme.FontFace.Display, TextSize = 16, TextColor3 = Theme.Color.Accent, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 4 }),
			ColDesc = React.createElement("TextLabel", { Size = UDim2.new(1, -255, 1, 0), BackgroundTransparency = 1, Text = "Effect", FontFace = Theme.FontFace.Display, TextSize = 16, TextColor3 = Theme.Color.Accent, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 5 }),
		}),
	}
	for i, spec in STANCE_SUMMARY do
		local isSelected = props.selectedStance == spec.name
		stanceTableRows[spec.name] = React.createElement("Frame", {
			Size = UDim2.new(1, 0, 0, 24),
			BackgroundColor3 = if isSelected then Theme.Color.SurfaceRaised else Theme.Color.Surface,
			BackgroundTransparency = if isSelected then 0.15 else 1,
			LayoutOrder = i,
		}, {
			Corner = React.createElement("UICorner", { CornerRadius = Theme.corner(Theme.Metrics.RadiusSmall) }),
			Stroke = isSelected and React.createElement("UIStroke", { Color = Theme.Color.Accent, Thickness = 1.5, Transparency = 0.2 }) or nil,
			Layout = React.createElement("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }),
			Padding = React.createElement("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4) }),
			ColStance = React.createElement("TextLabel", { Size = UDim2.new(0, 90, 1, 0), BackgroundTransparency = 1, Text = spec.name, FontFace = if isSelected then Theme.FontFace.BodyBold else Theme.FontFace.Body, TextSize = 15, TextColor3 = if isSelected then Theme.Color.Accent else Theme.Color.TextPrimary, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 1 }),
			ColAtk = React.createElement("TextLabel", { Size = UDim2.new(0, 55, 1, 0), BackgroundTransparency = 1, Text = spec.atk, FontFace = if isSelected then Theme.FontFace.BodyBold else Theme.FontFace.Body, TextSize = 15, TextColor3 = if isSelected then Theme.Color.Accent else Theme.Color.TextSecondary, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 2 }),
			ColDef = React.createElement("TextLabel", { Size = UDim2.new(0, 55, 1, 0), BackgroundTransparency = 1, Text = spec.def, FontFace = if isSelected then Theme.FontFace.BodyBold else Theme.FontFace.Body, TextSize = 15, TextColor3 = if isSelected then Theme.Color.Accent else Theme.Color.TextSecondary, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 3 }),
			ColSpd = React.createElement("TextLabel", { Size = UDim2.new(0, 55, 1, 0), BackgroundTransparency = 1, Text = spec.spd, FontFace = if isSelected then Theme.FontFace.BodyBold else Theme.FontFace.Body, TextSize = 15, TextColor3 = if isSelected then Theme.Color.Accent else Theme.Color.TextSecondary, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 4 }),
			ColDesc = React.createElement("TextLabel", { Size = UDim2.new(1, -255, 1, 0), BackgroundTransparency = 1, Text = spec.desc, FontFace = if isSelected then Theme.FontFace.BodyBold else Theme.FontFace.Body, TextSize = 15, TextColor3 = if isSelected then Theme.Color.Accent else Theme.Color.TextSecondary, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 5 }),
		})
	end

	-- 3. Formation Stats TABLE Rows
	local formationTableRows: { [string]: any } = {
		Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			Padding = UDim.new(0, 2),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		HeaderRow = React.createElement("Frame", {
			Size = UDim2.new(1, 0, 0, 24),
			BackgroundColor3 = Theme.Color.SurfaceRaised,
			BackgroundTransparency = 0.3,
			LayoutOrder = 0,
		}, {
			Corner = React.createElement("UICorner", { CornerRadius = Theme.corner(Theme.Metrics.RadiusSmall) }),
			Layout = React.createElement("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }),
			Padding = React.createElement("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4) }),
			ColForm = React.createElement("TextLabel", { Size = UDim2.new(0, 105, 1, 0), BackgroundTransparency = 1, Text = "Formation", FontFace = Theme.FontFace.Display, TextSize = 16, TextColor3 = Theme.Color.Accent, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 1 }),
			ColDef = React.createElement("TextLabel", { Size = UDim2.new(0, 65, 1, 0), BackgroundTransparency = 1, Text = "Defense", FontFace = Theme.FontFace.Display, TextSize = 16, TextColor3 = Theme.Color.Accent, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 2 }),
			ColAtk = React.createElement("TextLabel", { Size = UDim2.new(0, 65, 1, 0), BackgroundTransparency = 1, Text = "Attack", FontFace = Theme.FontFace.Display, TextSize = 16, TextColor3 = Theme.Color.Accent, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 3 }),
			ColSpd = React.createElement("TextLabel", { Size = UDim2.new(0, 65, 1, 0), BackgroundTransparency = 1, Text = "Speed", FontFace = Theme.FontFace.Display, TextSize = 16, TextColor3 = Theme.Color.Accent, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 4 }),
			ColMin = React.createElement("TextLabel", { Size = UDim2.new(1, -300, 1, 0), BackgroundTransparency = 1, Text = "Min Units", FontFace = Theme.FontFace.Display, TextSize = 16, TextColor3 = Theme.Color.Accent, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 5 }),
		}),
	}
	for i, spec in FORMATION_SUMMARY do
		local isSelected = props.selectedFormation == spec.name
		formationTableRows[spec.name] = React.createElement("Frame", {
			Size = UDim2.new(1, 0, 0, 24),
			BackgroundColor3 = if isSelected then Theme.Color.SurfaceRaised else Theme.Color.Surface,
			BackgroundTransparency = if isSelected then 0.15 else 1,
			LayoutOrder = i,
		}, {
			Corner = React.createElement("UICorner", { CornerRadius = Theme.corner(Theme.Metrics.RadiusSmall) }),
			Stroke = isSelected and React.createElement("UIStroke", { Color = Theme.Color.Accent, Thickness = 1.5, Transparency = 0.2 }) or nil,
			Layout = React.createElement("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }),
			Padding = React.createElement("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4) }),
			ColForm = React.createElement("TextLabel", { Size = UDim2.new(0, 105, 1, 0), BackgroundTransparency = 1, Text = spec.name, FontFace = if isSelected then Theme.FontFace.BodyBold else Theme.FontFace.Body, TextSize = 15, TextColor3 = if isSelected then Theme.Color.Accent else Theme.Color.TextPrimary, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 1 }),
			ColDef = React.createElement("TextLabel", { Size = UDim2.new(0, 65, 1, 0), BackgroundTransparency = 1, Text = spec.def, FontFace = if isSelected then Theme.FontFace.BodyBold else Theme.FontFace.Body, TextSize = 15, TextColor3 = if isSelected then Theme.Color.Accent else Theme.Color.TextSecondary, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 2 }),
			ColAtk = React.createElement("TextLabel", { Size = UDim2.new(0, 65, 1, 0), BackgroundTransparency = 1, Text = spec.atk, FontFace = if isSelected then Theme.FontFace.BodyBold else Theme.FontFace.Body, TextSize = 15, TextColor3 = if isSelected then Theme.Color.Accent else Theme.Color.TextSecondary, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 3 }),
			ColSpd = React.createElement("TextLabel", { Size = UDim2.new(0, 65, 1, 0), BackgroundTransparency = 1, Text = spec.spd, FontFace = if isSelected then Theme.FontFace.BodyBold else Theme.FontFace.Body, TextSize = 15, TextColor3 = if isSelected then Theme.Color.Accent else Theme.Color.TextSecondary, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 4 }),
			ColMin = React.createElement("TextLabel", { Size = UDim2.new(1, -300, 1, 0), BackgroundTransparency = 1, Text = tostring(spec.min) .. " units", FontFace = if isSelected then Theme.FontFace.BodyBold else Theme.FontFace.Body, TextSize = 15, TextColor3 = if isSelected then Theme.Color.Accent else Theme.Color.TextSecondary, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 5 }),
		})
	end

	return React.createElement("Frame", {
		Name = "UnitPanel",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		LayoutOrder = props.LayoutOrder,
	}, {
		Padding = React.createElement("UIPadding", {
			PaddingTop = UDim.new(0, 8),
			PaddingBottom = UDim.new(0, 8),
			PaddingLeft = UDim.new(0, 10),
			PaddingRight = UDim.new(0, 10),
		}),
		-- COMBINED LEFT COLUMN: Units breakdown + Return to Keep + Combat Stances
		LeftCol = React.createElement("Frame", {
			Size = UDim2.new(0.46, -4, 1, 0),
			Position = UDim2.new(0, 0, 0, 0),
			BackgroundTransparency = 1,
		}, leftChildren),

		-- RIGHT COLUMN: Formations Grid + Modular InfoButton next to title
		RightCol = React.createElement("Frame", {
			Size = UDim2.new(0.54, -4, 1, 0),
			Position = UDim2.new(0.46, 4, 0, 0),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
		}, {
			HeaderFrame = React.createElement("Frame", {
				Size = UDim2.new(1, 0, 0, 22),
				BackgroundTransparency = 1,
			}, {
				Layout = React.createElement("UIListLayout", {
					FillDirection = Enum.FillDirection.Horizontal,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					Padding = UDim.new(0, 6),
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
				Header = React.createElement("TextLabel", {
					AutomaticSize = Enum.AutomaticSize.X,
					Size = UDim2.new(0, 0, 1, 0),
					BackgroundTransparency = 1,
					Text = "📐 Formations",
					FontFace = Theme.FontFace.Display,
					TextSize = Theme.TextSize.Heading,
					TextColor3 = Theme.Color.Accent,
					TextXAlignment = Enum.TextXAlignment.Left,
					LayoutOrder = 1,
				}),
				FormationInfoBtn = React.createElement(InfoButton, {
					active = showFormationInfo,
					size = 15,
					LayoutOrder = 2,
					onActivated = function()
						setShowFormationInfo(not showFormationInfo)
					end,
				}),
			}),

			FormationGrid = React.createElement("Frame", {
				Size = UDim2.new(1, 0, 1, -26),
				Position = UDim2.new(0, 0, 0, 26),
				BackgroundTransparency = 1,
			}, formationSquareButtons),
		}),

		-- FLOATING TABLE POPUPS FLOATING *ABOVE* THE PANEL
		UnitInfoPopup = showUnitInfo and React.createElement("Frame", {
			Size = UDim2.new(0, 510, 0, 175),
			Position = UDim2.new(0, 0, 0, -185),
			BackgroundColor3 = Color3.fromRGB(24, 20, 15),
			BackgroundTransparency = 0.02,
			ZIndex = 100,
		}, {
			Corner = React.createElement("UICorner", { CornerRadius = Theme.corner() }),
			Stroke = React.createElement("UIStroke", Theme.celticStrokeProps()),
			Padding = React.createElement("UIPadding", { PaddingTop = UDim.new(0, 5), PaddingBottom = UDim.new(0, 5), PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 5) }),
			Table = React.createElement("Frame", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
			}, unitTableRows),
		}) or nil,

		StanceInfoPopup = showStanceInfo and React.createElement("Frame", {
			Size = UDim2.new(0, 480, 0, 175),
			Position = UDim2.new(0.02, 0, 0, -185),
			BackgroundColor3 = Color3.fromRGB(24, 20, 15),
			BackgroundTransparency = 0.02,
			ZIndex = 100,
		}, {
			Corner = React.createElement("UICorner", { CornerRadius = Theme.corner() }),
			Stroke = React.createElement("UIStroke", Theme.celticStrokeProps()),
			Padding = React.createElement("UIPadding", { PaddingTop = UDim.new(0, 5), PaddingBottom = UDim.new(0, 5), PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 5) }),
			Table = React.createElement("Frame", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
			}, stanceTableRows),
		}) or nil,

		FormationInfoPopup = showFormationInfo and React.createElement("Frame", {
			Size = UDim2.new(0, 480, 0, 195),
			Position = UDim2.new(0.40, 0, 0, -205),
			BackgroundColor3 = Color3.fromRGB(24, 20, 15),
			BackgroundTransparency = 0.02,
			ZIndex = 100,
		}, {
			Corner = React.createElement("UICorner", { CornerRadius = Theme.corner() }),
			Stroke = React.createElement("UIStroke", Theme.celticStrokeProps()),
			Padding = React.createElement("UIPadding", { PaddingTop = UDim.new(0, 5), PaddingBottom = UDim.new(0, 5), PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 5) }),
			Table = React.createElement("Frame", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
			}, formationTableRows),
		}) or nil,
	})
end

return UnitPanel
