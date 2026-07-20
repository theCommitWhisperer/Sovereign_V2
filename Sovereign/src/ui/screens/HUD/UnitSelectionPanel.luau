local React = require(game.ReplicatedStorage.Packages.react)
local UIConfig = require(script.Parent.Parent.Parent.UIConfig)
local GameData = require(game.ReplicatedStorage.Shared.GameData)

local UnitSelectionPanel = React.Component:extend("UnitSelectionPanel")

-- Peasants and worker-subtype job units are "civilians" and get their own orders.
local function isCivilianUnit(unit: Instance): boolean
	local t = unit:GetAttribute("UnitType")
	if t == "Peasant" then
		return true
	end
	local data = t and GameData.Units[t]
	return data ~= nil and data.subtype == "Worker"
end

-- Fire a civilian order (ReturnToKeep / UnassignWorkers) for the selection.
local function fireCivilianOrder(selectedUnits, action: string)
	local remotes = game.ReplicatedStorage:FindFirstChild("RemoteEvents")
	local gameEvent = remotes and remotes:FindFirstChild("GameEvent")
	if not gameEvent then
		return
	end
	local ids = {}
	for _, unit in selectedUnits do
		table.insert(ids, unit:GetAttribute("UnitId") or unit.Name)
	end
	gameEvent:FireServer(action, { unitIds = ids })
end

-- Formation types (must match FormationManager names)
local FORMATIONS = {
	{ name = "Line", icon = "━━━", tooltip = "Line Formation" },
	{ name = "Phalanx", icon = "▤", tooltip = "Phalanx — deep four-rank block" },
	{ name = "Column", icon = "║", tooltip = "Column Formation" },
	{ name = "ShieldWall", icon = "🛡️", tooltip = "Shield Wall" },
	{ name = "Wedge", icon = "▶", tooltip = "Wedge Formation" },
	{ name = "Crescent", icon = "◠", tooltip = "Crescent — enveloping wings" },
	{ name = "Circle", icon = "◯", tooltip = "Circle — all-round defense" },
	{ name = "Schiltron", icon = "▦", tooltip = "Schiltron — dense pike square" },
	{ name = "Skirmish", icon = "⁘", tooltip = "Skirmish — staggered open order" },
	{ name = "Loose", icon = "⋯", tooltip = "Loose Formation" },
}

function UnitSelectionPanel:render()
	local selectedUnits = self.props.selectedUnits or {}
	local unitCount = #selectedUnits

	if unitCount == 0 then
		return nil
	end

	-- Does the selection include any civilians (peasants / workers)?
	local hasCivilians = false
	for _, unit in selectedUnits do
		if isCivilianUnit(unit) then
			hasCivilians = true
			break
		end
	end

	-- Group units by type for display
	local unitGroups = {}
	local unitGroupList = {} -- Preserve order
	for _, unit in selectedUnits do
		local unitType = unit:GetAttribute("UnitType") or "Unknown"
		if not unitGroups[unitType] then
			unitGroups[unitType] = {
				type = unitType,
				count = 0,
				units = {},
			}
			table.insert(unitGroupList, unitGroups[unitType])
		end
		unitGroups[unitType].count = unitGroups[unitType].count + 1
		table.insert(unitGroups[unitType].units, unit)
	end

	-- Create unit portrait elements
	local unitPortraits = {}
	unitPortraits.Layout = React.createElement("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Top,
		Padding = UDim.new(0, UIConfig.HUD.UnitPortraitSpacing),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})

	for i, group in ipairs(unitGroupList) do
		-- Create portrait for each unit type
		unitPortraits[group.type .. i] = React.createElement("Frame", {
			Name = group.type .. "Portrait",
			Size = UDim2.new(0, UIConfig.HUD.UnitPortraitSize, 0, UIConfig.HUD.UnitPortraitSize),
			BackgroundColor3 = UIConfig.HUD.BuildingButtonBackground,
			BorderSizePixel = 2,
			BorderColor3 = UIConfig.HUD.BuildingButtonBorder,
			LayoutOrder = i,
		}, {
			-- Unit type icon/label
			UnitIcon = React.createElement("TextLabel", {
				Size = UDim2.new(1, 0, 0.7, 0),
				BackgroundTransparency = 1,
				Text = group.type:sub(1, 1), -- First letter as icon
				Font = Enum.Font.GothamBold,
				TextSize = 32,
				TextColor3 = UIConfig.HUD.PanelTextColor,
			}),

			-- Count badge
			CountLabel = React.createElement("TextLabel", {
				Size = UDim2.new(1, 0, 0.3, 0),
				Position = UDim2.new(0, 0, 0.7, 0),
				BackgroundColor3 = UIConfig.HUD.ResourceBackgroundColor,
				BorderSizePixel = 0,
				Text = group.count > 1 and tostring(group.count) or "",
				Font = Enum.Font.GothamBold,
				TextSize = 14,
				TextColor3 = Color3.fromRGB(255, 255, 255),
			}),
		})
	end

	-- Create formation control elements (grid: 10 formations wrap into rows)
	local formationControls = {}
	formationControls.Layout = React.createElement("UIGridLayout", {
		CellSize = UDim2.new(0, 36, 0, 36),
		CellPadding = UDim2.new(0, 5, 0, 5),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
	})

	for i, formation in ipairs(FORMATIONS) do
		local isSelected = self.props.selectedFormation == formation.name
		formationControls[formation.name] = React.createElement("TextButton", {
			Name = formation.name .. "Button",
			BackgroundColor3 = isSelected and UIConfig.HUD.CategoryButtonSelected or UIConfig.HUD.FormationButtonBackground,
			BorderSizePixel = 2,
			BorderColor3 = isSelected and Color3.fromRGB(255, 200, 100) or UIConfig.HUD.FormationButtonBorder,
			Text = formation.icon,
			Font = Enum.Font.GothamBold,
			TextSize = 16,
			TextColor3 = UIConfig.HUD.PanelTextColor,
			LayoutOrder = i,
			[React.Event.MouseButton1Click] = function()
				if self.props.onFormationSelected then
					self.props.onFormationSelected(formation.name)
				end
			end,
		})
	end

	-- Stance controls (must match FormationManager / CombatConfig stance names)
	local STANCES = {
		{ name = "March", icon = "🚶", tooltip = "March — move together, don't fight (default)" },
		{ name = "Attack", icon = "⚔️", tooltip = "Attack — seek out and charge enemies" },
		{ name = "Defend", icon = "🛡️", tooltip = "Defend — hold ground, guard this spot" },
		{ name = "Skirmish", icon = "🏹", tooltip = "Skirmish — harass and fall back" },
	}

	local selectedStance = self.props.selectedStance or "March"

	local stanceControls = {}
	stanceControls.Layout = React.createElement("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})

	for i, stance in ipairs(STANCES) do
		local isSelected = selectedStance == stance.name
		stanceControls[stance.name .. "Button"] = React.createElement("TextButton", {
			Name = stance.name .. "StanceButton",
			Size = UDim2.new(0, UIConfig.HUD.FormationButtonSize, 0, UIConfig.HUD.FormationButtonSize),
			BackgroundColor3 = isSelected and UIConfig.HUD.CategoryButtonSelected or UIConfig.HUD.FormationButtonBackground,
			BorderSizePixel = 2,
			BorderColor3 = isSelected and Color3.fromRGB(255, 200, 100) or UIConfig.HUD.FormationButtonBorder,
			Text = stance.icon,
			Font = Enum.Font.GothamBold,
			TextSize = 22,
			LayoutOrder = i,
			[React.Event.MouseButton1Click] = function()
				if self.props.onStanceSelected then
					self.props.onStanceSelected(stance.name)
				end
			end,
		})
	end

	return React.createElement("Frame", {
		Name = "UnitSelectionPanel",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, {
		-- Selected units label
		Header = React.createElement("TextLabel", {
			Name = "Header",
			Size = UDim2.new(1, 0, 0, 25),
			BackgroundTransparency = 1,
			Text = `Selected: {unitCount} unit{unitCount > 1 and "s" or ""}`,
			Font = Enum.Font.GothamBold,
			TextSize = 16,
			TextColor3 = UIConfig.HUD.PanelHeaderColor,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),

		-- Unit portraits section
		PortraitsSection = React.createElement("Frame", {
			Name = "PortraitsSection",
			Size = UDim2.new(1, 0, 0, UIConfig.HUD.UnitPortraitSize),
			Position = UDim2.new(0, 0, 0, 30),
			BackgroundTransparency = 1,
		}, unitPortraits),

		-- Formation controls section
		FormationSection = React.createElement("Frame", {
			Name = "FormationSection",
			Size = UDim2.new(0.5, -5, 0, UIConfig.HUD.FormationButtonSize + 30),
			Position = UDim2.new(0, 0, 0, 110),
			BackgroundTransparency = 1,
		}, {
			Label = React.createElement("TextLabel", {
				Size = UDim2.new(1, 0, 0, 20),
				BackgroundTransparency = 1,
				Text = "Formation",
				Font = Enum.Font.GothamBold,
				TextSize = 14,
				TextColor3 = UIConfig.HUD.PanelHeaderColor,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),

			Controls = React.createElement("Frame", {
				Size = UDim2.new(1, 0, 1, -25),
				Position = UDim2.new(0, 0, 0, 25),
				BackgroundTransparency = 1,
			}, formationControls),
		}),

		-- Stance controls section
		StanceSection = React.createElement("Frame", {
			Name = "StanceSection",
			Size = UDim2.new(0.5, -5, 0, UIConfig.HUD.FormationButtonSize + 30),
			Position = UDim2.new(0.5, 5, 0, 110),
			BackgroundTransparency = 1,
		}, {
			Label = React.createElement("TextLabel", {
				Size = UDim2.new(1, 0, 0, 20),
				BackgroundTransparency = 1,
				Text = "Stance",
				Font = Enum.Font.GothamBold,
				TextSize = 14,
				TextColor3 = UIConfig.HUD.PanelHeaderColor,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),

			Controls = React.createElement("Frame", {
				Size = UDim2.new(1, 0, 1, -25),
				Position = UDim2.new(0, 0, 0, 25),
				BackgroundTransparency = 1,
			}, stanceControls),
		}),

		-- Civilian orders (only when peasants/workers are selected). Move is right-click.
		CivilianSection = hasCivilians and React.createElement("Frame", {
			Name = "CivilianSection",
			Size = UDim2.new(1, 0, 0, 52),
			Position = UDim2.new(0, 0, 0, 165),
			BackgroundTransparency = 1,
		}, {
			Label = React.createElement("TextLabel", {
				Size = UDim2.new(1, 0, 0, 18),
				BackgroundTransparency = 1,
				Text = "Workers  (right-click ground to move)",
				Font = Enum.Font.GothamBold,
				TextSize = 13,
				TextColor3 = UIConfig.HUD.PanelHeaderColor,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),

			ToKeep = React.createElement("TextButton", {
				Size = UDim2.new(0.5, -4, 0, 28),
				Position = UDim2.new(0, 0, 0, 22),
				BackgroundColor3 = UIConfig.HUD.FormationButtonBackground,
				BorderSizePixel = 2,
				BorderColor3 = UIConfig.HUD.FormationButtonBorder,
				Text = "🏠 To Keep",
				Font = Enum.Font.GothamBold,
				TextSize = 14,
				TextColor3 = UIConfig.HUD.PanelTextColor,
				[React.Event.MouseButton1Click] = function()
					fireCivilianOrder(selectedUnits, "ReturnToKeep")
				end,
			}),

			Unassign = React.createElement("TextButton", {
				Size = UDim2.new(0.5, -4, 0, 28),
				Position = UDim2.new(0.5, 4, 0, 22),
				BackgroundColor3 = UIConfig.HUD.FormationButtonBackground,
				BorderSizePixel = 2,
				BorderColor3 = UIConfig.HUD.FormationButtonBorder,
				Text = "✋ Unassign",
				Font = Enum.Font.GothamBold,
				TextSize = 14,
				TextColor3 = UIConfig.HUD.PanelTextColor,
				[React.Event.MouseButton1Click] = function()
					fireCivilianOrder(selectedUnits, "UnassignWorkers")
				end,
			}),
		}) or nil,
	})
end

return UnitSelectionPanel
