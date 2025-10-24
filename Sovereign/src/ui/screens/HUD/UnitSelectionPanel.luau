local React = require(game.ReplicatedStorage.Packages.react)
local UIConfig = require(script.Parent.Parent.Parent.UIConfig)

local UnitSelectionPanel = React.Component:extend("UnitSelectionPanel")

-- Formation types
local FORMATIONS = {
	{ name = "Line", icon = "━━━", tooltip = "Line Formation" },
	{ name = "Column", icon = "║", tooltip = "Column Formation" },
	{ name = "Box", icon = "▢", tooltip = "Box Formation" },
	{ name = "Wedge", icon = "▶", tooltip = "Wedge Formation" },
	{ name = "Scatter", icon = "⋯", tooltip = "Scatter Formation" },
}

function UnitSelectionPanel:render()
	local selectedUnits = self.props.selectedUnits or {}
	local unitCount = #selectedUnits

	if unitCount == 0 then
		return nil
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

	-- Create formation control elements
	local formationControls = {}
	formationControls.Layout = React.createElement("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})

	for i, formation in ipairs(FORMATIONS) do
		formationControls[formation.name] = React.createElement("TextButton", {
			Name = formation.name .. "Button",
			Size = UDim2.new(0, UIConfig.HUD.FormationButtonSize, 0, UIConfig.HUD.FormationButtonSize),
			BackgroundColor3 = UIConfig.HUD.FormationButtonBackground,
			BorderSizePixel = 2,
			BorderColor3 = UIConfig.HUD.FormationButtonBorder,
			Text = formation.icon,
			Font = Enum.Font.GothamBold,
			TextSize = 20,
			TextColor3 = UIConfig.HUD.PanelTextColor,
			LayoutOrder = i,
			[React.Event.MouseButton1Click] = function()
				if self.props.onFormationSelected then
					self.props.onFormationSelected(formation.name)
				end
			end,
		})
	end

	-- Create stance control elements (moved from unit controls)
	local STANCES = {
		{ name = "Aggressive", icon = "⚔️" },
		{ name = "Defensive", icon = "🛡️" },
		{ name = "HoldPosition", icon = "✋" },
	}

	local stanceControls = {}
	stanceControls.Layout = React.createElement("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})

	for i, stance in ipairs(STANCES) do
		stanceControls[stance.name .. "Button"] = React.createElement("TextButton", {
			Name = stance.name .. "StanceButton",
			Size = UDim2.new(0, UIConfig.HUD.FormationButtonSize, 0, UIConfig.HUD.FormationButtonSize),
			BackgroundColor3 = UIConfig.HUD.FormationButtonBackground,
			BorderSizePixel = 2,
			BorderColor3 = UIConfig.HUD.FormationButtonBorder,
			Text = stance.icon,
			Font = Enum.Font.GothamBold,
			TextSize = 22,
			LayoutOrder = i,
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
	})
end

return UnitSelectionPanel
