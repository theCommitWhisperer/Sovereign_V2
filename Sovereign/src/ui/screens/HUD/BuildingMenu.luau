local React = require(game.ReplicatedStorage.Packages.react)
local UIConfig = require(script.Parent.Parent.Parent.UIConfig)
local GameData = require(game.ReplicatedStorage.Shared.GameData)

local BuildingMenu = React.Component:extend("BuildingMenu")

function BuildingMenu:init()
	self:setState({
		hoveredBuilding = nil, -- Track which building is being hovered for tooltip
	})
end

-- Map category names to buildings (5 main categories)
local BUILDING_CATEGORIES = {
	-- Defense: Walls, towers, military buildings
	Defense = {
		"Keep",
		"Wooden_Palisade",
		"Stone_Wall",
		"Watch_Tower",
		"Arrow_Tower",
		"Gatehouse",
		"Barracks",
		"Guard_House",
		"Crannog",
		"Round_Tower",
	},
	-- Economy: Resource production, commerce, storage
	Economy = {
		"Woodcutters_Post",
		"Stone_Quarry",
		"Iron_Mine",
		"Smithy",
		"Weaponsmith",
		"Storehouse",
		"Granary",
		"Market",
		"Trading_Post",
		"Tannery",
		"Carpenter",
	},
	-- Housing: All residential and population buildings
	Housing = {
		"Hovel",
		"Clachan",
		"Inn",
		"Monastery",
	},
	-- Food: Food production, processing, and service
	Food = {
		"Farm",
		"Fishermans_Hut",
		"Windmill",
		"Water_Mill",
		"Bakery",
		"Brewery",
		"Kitchen",
		"Restaurant",
		"Tavern",
		"Mead_Hall",
	},
	-- Culture: Religious, cultural, and special Irish buildings
	Culture = {
		"Chapel",
		"Church",
		"Scriptorium",
		"Town_Hall",
		"Brehon_Court",
		"Dolmen",
		"Stone_Circle",
		"Celtic_Cross",
		"Forge_of_the_Tuatha",
	},
}

function BuildingMenu:render()
	local resources = self.props.resources or {}
	local selectedCategory = self.props.selectedCategory or "Defense"

	-- Building buttons for selected category
	local buildingButtons = {}
	buildingButtons.Layout = React.createElement("UIGridLayout", {
		CellSize = UDim2.new(0, UIConfig.HUD.BuildingButtonSize, 0, UIConfig.HUD.BuildingButtonSize),
		CellPadding = UDim2.new(0, 8, 0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})

	local buildingsInCategory = BUILDING_CATEGORIES[selectedCategory] or {}

	for i, buildingName in ipairs(buildingsInCategory) do
		local buildingInfo = GameData.Buildings[buildingName]
		if buildingInfo then
			-- Check if player can afford
			local canAfford = true
			for resource, cost in pairs(buildingInfo.cost) do
				if (resources[resource] or 0) < cost then
					canAfford = false
					break
				end
			end

			-- Create cost string (compact)
			local costText = ""
			for resource, cost in pairs(buildingInfo.cost) do
				if costText ~= "" then
					costText = costText .. "\n"
				end
				costText = costText .. resource:gsub("_", " ") .. ": " .. cost
			end

			-- Create children for the button
			local buttonChildren = {
				Padding = React.createElement("UIPadding", {
					PaddingTop = UDim.new(0, 4),
					PaddingBottom = UDim.new(0, 4),
					PaddingLeft = UDim.new(0, 4),
					PaddingRight = UDim.new(0, 4),
				}),

				Layout = React.createElement("UIListLayout", {
					FillDirection = Enum.FillDirection.Vertical,
					HorizontalAlignment = Enum.HorizontalAlignment.Center,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					Padding = UDim.new(0, 3),
				}),

				Name = React.createElement("TextLabel", {
					Size = UDim2.new(1, 0, 0, 18),
					Text = buildingName:gsub("_", " "),
					Font = Enum.Font.GothamBold,
					TextSize = 11,
					TextColor3 = UIConfig.HUD.PanelTextColor,
					BackgroundTransparency = 1,
					TextWrapped = true,
				}),

				Cost = React.createElement("TextLabel", {
					Size = UDim2.new(1, 0, 1, -21),
					Text = costText,
					Font = Enum.Font.Gotham,
					TextSize = 9,
					TextColor3 = canAfford and UIConfig.HUD.StatLabelColor or Color3.fromRGB(255, 100, 100),
					BackgroundTransparency = 1,
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
				}),
			}

			-- Add tooltip if this building is being hovered
			if self.state.hoveredBuilding == buildingName then
				-- Build compact tooltip with icons
				local tooltipLines = {}

				-- Title
				tooltipLines[#tooltipLines + 1] = buildingName:gsub("_", " ")

				-- Subtype
				if buildingInfo.subtype then
					tooltipLines[#tooltipLines + 1] = buildingInfo.subtype
				end

				-- Stats with icons
				local statsLine = ""

				-- Defense
				if buildingInfo.defense_value then
					statsLine = statsLine .. "🛡️ " .. buildingInfo.defense_value .. "  "
				end

				-- Attack
				if buildingInfo.attack_damage then
					statsLine = statsLine .. "⚔️ " .. buildingInfo.attack_damage .. "  "
				end

				-- Housing
				if buildingInfo.housing_capacity then
					statsLine = statsLine .. "🏠 " .. buildingInfo.housing_capacity .. "  "
				end

				-- Popularity
				if buildingInfo.popularity_impact then
					local sign = buildingInfo.popularity_impact > 0 and "+" or ""
					statsLine = statsLine .. "❤️ " .. sign .. buildingInfo.popularity_impact .. "  "
				end

				if statsLine ~= "" then
					tooltipLines[#tooltipLines + 1] = statsLine
				end

				-- Production info
				if buildingInfo.produces_resource then
					local prodLine = "📦 " .. buildingInfo.produces_resource:gsub("_", " ")
					if buildingInfo.production_rate then
						prodLine = prodLine .. " (" .. buildingInfo.production_rate .. "/s)"
					end
					tooltipLines[#tooltipLines + 1] = prodLine
				end

				-- Consumption info
				if buildingInfo.consumes_resource then
					tooltipLines[#tooltipLines + 1] = "⚙️ Uses " .. buildingInfo.consumes_resource:gsub("_", " ")
				end

				-- Training
				if buildingInfo.can_train_units then
					tooltipLines[#tooltipLines + 1] = "⚔️ Trains: "
						.. table.concat(buildingInfo.can_train_units, ", ")
				end

				-- Build time
				tooltipLines[#tooltipLines + 1] = "⏱️ " .. buildingInfo.construction.build_time_seconds .. "s"

				local tooltipText = table.concat(tooltipLines, "\n")

				buttonChildren.Tooltip = React.createElement("Frame", {
					Position = UDim2.fromScale(-1, 1), -- Above the button (relative positioning)
					Size = UDim2.fromScale(1, 1), -- Auto-height based on content
					AutomaticSize = Enum.AutomaticSize.Y,
					BackgroundColor3 = Color3.fromRGB(20, 20, 25),
					BackgroundTransparency = 0.05,
					BorderSizePixel = 0,
					ZIndex = 1000,
					AnchorPoint = Vector2.new(0.5, 1), -- Anchor at bottom center
				}, {
					Corner = React.createElement("UICorner", {
						CornerRadius = UDim.new(0, 6),
					}),

					Stroke = React.createElement("UIStroke", {
						Color = Color3.fromRGB(100, 100, 120),
						Thickness = 1,
						Transparency = 0.3,
					}),

					Padding = React.createElement("UIPadding", {
						PaddingTop = UDim.new(0, 6),
						PaddingBottom = UDim.new(0, 6),
						PaddingLeft = UDim.new(0, 8),
						PaddingRight = UDim.new(0, 8),
					}),

					TooltipText = React.createElement("TextLabel", {
						Size = UDim2.fromScale(1, 1),
						AutomaticSize = Enum.AutomaticSize.Y,
						BackgroundTransparency = 1,
						Text = tooltipText,
						TextColor3 = Color3.fromRGB(230, 230, 240),
						Font = Enum.Font.GothamMedium,
						TextSize = 11,
						TextXAlignment = Enum.TextXAlignment.Left,
						TextYAlignment = Enum.TextYAlignment.Top,
						TextWrapped = true,
						RichText = true, -- Enable emoji support
					}),
				})
			end

			buildingButtons[buildingName] = React.createElement("TextButton", {
				Size = UDim2.new(0, UIConfig.HUD.BuildingButtonSize, 0, UIConfig.HUD.BuildingButtonSize),
				Text = "",
				BackgroundColor3 = canAfford and UIConfig.HUD.BuildingButtonAffordable
					or UIConfig.HUD.BuildingButtonUnaffordable,
				BorderSizePixel = 1,
				BorderColor3 = UIConfig.HUD.BuildingButtonBorder,
				LayoutOrder = i,
				ClipsDescendants = false, -- Allow tooltip to overflow
				[React.Event.MouseButton1Click] = function()
					if canAfford and self.props.onBuildingSelected then
						self.props.onBuildingSelected(buildingName)
					end
				end,
				[React.Event.MouseEnter] = function()
					self:setState({ hoveredBuilding = buildingName })
				end,
				[React.Event.MouseLeave] = function()
					self:setState({ hoveredBuilding = nil })
				end,
			}, buttonChildren)
		end
	end

	return React.createElement("Frame", {
		Name = "BuildingMenu",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ClipsDescendants = false, -- Allow tooltips to overflow
	}, {
		Padding = React.createElement("UIPadding", {
			PaddingTop = UDim.new(0, 8),
			PaddingBottom = UDim.new(0, 8),
			PaddingLeft = UDim.new(0, 8),
			PaddingRight = UDim.new(0, 8),
		}),

		BuildingsGrid = React.createElement("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ClipsDescendants = false, -- Allow tooltips to overflow
		}, buildingButtons),
	})
end

return BuildingMenu
