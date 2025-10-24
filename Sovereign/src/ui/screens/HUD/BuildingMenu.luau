local React = require(game.ReplicatedStorage.Packages.react)
local UIConfig = require(script.Parent.Parent.Parent.UIConfig)

local BuildingMenu = React.Component:extend("BuildingMenu")

-- Map category names to buildings (Castle = walls/towers/gates, Industry = resources/storage)
local BUILDING_CATEGORIES = {
	Castle = { "Wall", "Tower", "Gatehouse", "Keep" },
	Military = { "Barracks", "Archery_Range", "Armory" },
	Housing = { "Hovel", "House", "Manor" },
	Food = { "Farm", "Kitchen", "Restaurant", "Bakery" },
	Industry = { "Woodcutters_Post", "Stone_Quarry", "Storehouse", "Granary" },
}

function BuildingMenu:render()
	local resources = self.props.resources or {}
	local selectedCategory = self.props.selectedCategory or "Castle"

	-- Building buttons for selected category
	local buildingButtons = {}
	buildingButtons.Layout = React.createElement("UIGridLayout", {
		CellSize = UDim2.new(0, UIConfig.HUD.BuildingButtonSize, 0, UIConfig.HUD.BuildingButtonSize),
		CellPadding = UDim2.new(0, 8, 0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})

	local buildingsInCategory = BUILDING_CATEGORIES[selectedCategory] or {}
	local GameData = require(game.ReplicatedStorage.Shared.GameData)

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

			buildingButtons[buildingName] = React.createElement("TextButton", {
				Size = UDim2.new(0, UIConfig.HUD.BuildingButtonSize, 0, UIConfig.HUD.BuildingButtonSize),
				Text = "",
				BackgroundColor3 = canAfford and UIConfig.HUD.BuildingButtonAffordable
					or UIConfig.HUD.BuildingButtonUnaffordable,
				BorderSizePixel = 1,
				BorderColor3 = UIConfig.HUD.BuildingButtonBorder,
				LayoutOrder = i,
				[React.Event.MouseButton1Click] = function()
					if canAfford and self.props.onBuildingSelected then
						self.props.onBuildingSelected(buildingName)
					end
				end,
			}, {
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
					TextColor3 = canAfford and UIConfig.HUD.StatLabelColor
						or Color3.fromRGB(255, 100, 100),
					BackgroundTransparency = 1,
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
				}),
			})
		end
	end

	return React.createElement("Frame", {
		Name = "BuildingMenu",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
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
		}, buildingButtons),
	})
end

return BuildingMenu
