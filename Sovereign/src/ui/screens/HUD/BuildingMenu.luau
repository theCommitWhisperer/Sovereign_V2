local React = require(game.ReplicatedStorage.Packages.react)
local UIConfig = require(script.Parent.Parent.Parent.UIConfig)
local GameData = require(game.ReplicatedStorage.Shared.GameData)
local UserInputService = game:GetService("UserInputService")

local BuildingMenu = React.Component:extend("BuildingMenu")

function BuildingMenu:init()
	self:setState({
		hoveredBuilding = nil,
	})
end

local BUILDING_CATEGORIES = {
	-- Defense: Walls, towers, military buildings
	Defense = {
		-- Keep is built during tutorial only, not available in menu
		"Wooden_Palisade",
		-- The new wall system is initiated with this single button.
		-- Players can then cycle through pieces with the 'T' key.
		"Stone_Wall",
		-- Other defense
		"Watch_Tower",
		"Arrow_Tower",
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
	local currentWallPiece = self.props.currentWallPiece or "Wall Segment"
	local isPlacingWall = self.props.isPlacingWall or false

	-- Map wall piece names to building IDs
	local wallPieceMapping = {
		["Wall Segment"] = "Wall_Segment",
		["Wall Corner"] = "Wall_Corner",
		["Wall Corner Reverse"] = "Wall_Corner_Reverse",
		["Tower"] = "Wall_Tower",
		["Gatehouse"] = "Wall_Gatehouse",
		["Ladder Wall Segment"] = "Ladder_Wall_Segment",
	}

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
			local canAfford = true
			for resource, cost in pairs(buildingInfo.cost) do
				if (resources[resource] or 0) < cost then
					canAfford = false
					break
				end
			end

			local costText = ""
			for resource, cost in pairs(buildingInfo.cost) do
				if costText ~= "" then
					costText = costText .. "\n"
				end
				costText = costText .. resource:gsub("_", " ") .. ": " .. cost
			end

			-- Check if this wall piece is currently selected (only highlight when actively placing walls)
			local isSelectedWallPiece = isPlacingWall and wallPieceMapping[currentWallPiece] == buildingName

			local buttonChildren = {
				Border = React.createElement("UIStroke", {
					Color = isSelectedWallPiece and Color3.fromRGB(255, 215, 100) or UIConfig.HUD.StrokeColor,
					Thickness = isSelectedWallPiece and 3 or UIConfig.HUD.StrokeThickness,
				}),

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
					-- Show a nicer name for the Stone Wall button; other
					-- buildings still just use their ID with spaces.
					Text = (buildingName == "Stone_Wall" and "Stone Walls")
						or buildingName:gsub("_", " "),
					FontFace = UIConfig.Font.Title,
					TextSize = 11,
					TextColor3 = UIConfig.HUD.PanelTextColor,
					BackgroundTransparency = 1,
					TextWrapped = true,
					Active = false,
				}),

				Cost = React.createElement("TextLabel", {
					Size = UDim2.new(1, 0, 1, -21),
					Text = costText,
					FontFace = UIConfig.Font.Default,
					TextSize = 9,
					TextColor3 = canAfford and UIConfig.HUD.StatLabelColor or Color3.fromRGB(255, 100, 100),
					BackgroundTransparency = 1,
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					Active = false,
				}),
			}

			local buttonRef = React.createRef()

			buildingButtons[buildingName] = React.createElement("TextButton", {
				ref = buttonRef,
				Size = UDim2.new(0, UIConfig.HUD.BuildingButtonSize, 0, UIConfig.HUD.BuildingButtonSize),
				Text = "",
				BackgroundColor3 = isSelectedWallPiece and Color3.fromRGB(255, 255, 255)
					or (canAfford and UIConfig.HUD.BuildingButtonAffordable or UIConfig.HUD.BuildingButtonUnaffordable),
				BorderSizePixel = 0,
				LayoutOrder = i,
				[React.Event.MouseButton1Click] = function()
					if canAfford and self.props.onBuildingSelected then
						self.props.onBuildingSelected(buildingName)
					end
				end,
				[React.Event.MouseEnter] = function()
					if self.props.tooltip then
						-- Build compact tooltip with icons
						local tooltipLines = {}

						-- Title
						tooltipLines[#tooltipLines + 1] = buildingName:gsub("_", " ")

						-- Subtype
						if buildingInfo.subtype then
							tooltipLines[#tooltipLines + 1] = buildingInfo.subtype
						end

						-- Description
						if buildingInfo.description then
							tooltipLines[#tooltipLines + 1] = "\n" .. buildingInfo.description
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
							tooltipLines[#tooltipLines + 1] = "\n" .. statsLine
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
						tooltipLines[#tooltipLines + 1] = "\n⏱️ " .. buildingInfo.construction.build_time_seconds .. "s"

						local tooltipText = table.concat(tooltipLines, "\n")
						self.props.tooltip.show(tooltipText, buttonRef.current)
					end
				end,
				[React.Event.MouseLeave] = function()
					if self.props.tooltip then
						self.props.tooltip.hide()
					end
				end,
			}, buttonChildren)
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
