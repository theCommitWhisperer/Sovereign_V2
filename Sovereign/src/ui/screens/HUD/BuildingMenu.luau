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
	-- Defense: Castle structures and fortifications (Castle Tower icon)
	Defense = {
		"Stone Wall",
		"Short Tower",
		"Wall Gatehouse",
		"Wall Ladder",
		"Round Tower",
		"Wooden Palisade",
		"Arrow Tower",
		"Moat",
		"Fire Pit",
	},
	-- Military: Weapons, armor, and military buildings (Sword icon)
	Military = {
		"Barracks",
		"Guard House",
		"Smelter",
		"Weaponsmith",
		"Armory",
		"Training Ground",
		"Siege Workshop",
		"Stables",
		"Archery Range",
	},
	-- Industry: Resource production, commerce, storage (Hammer icon)
	Industry = {
		"Lumberjack",
		"Stone Quarry",
		"Iron Mine",
		"Storehouse",
		"Market",
		"Trading Post",
		"Tannery",
		"Carpenter",
		"Coal Mine",
	},
	-- Food: Food production, processing, and storage (Wheat icon)
	Food = {
		"Potato Farm",
		"Sheep Farm",
		"Cow Farm",
		"Fishermans Hut",
		"Water Mill",
		"Windmill",
		"Brewery",
		"Granary",
		"Bakery",
	},
	-- Housing: All residential and community buildings (Medieval House icon)
	Housing = {
		"Hovel",
		"Clachan",
		"Inn",
		"Monastery",
		"Tavern",
		"Church",
		"Town Hall",
		"Scriptorium",
		"Celtic Cross",
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
		CellSize = UDim2.fromOffset(60, 60),
		CellPadding = UDim2.fromOffset(17, 15),
		SortOrder = Enum.SortOrder.LayoutOrder,
		FillDirectionMaxCells = 3,
		FillDirection = Enum.FillDirection.Horizontal,
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

			local buttonChildren = {}

			-- Add icon if available
			if buildingInfo.icon_asset_id then
				buttonChildren.Icon = React.createElement("ImageLabel", {
					Size = UDim2.fromScale(1, 1),
					Image = buildingInfo.icon_asset_id,
					BackgroundTransparency = 1,
					ScaleType = Enum.ScaleType.Fit,
				})
			end

			local buttonRef = React.createRef()

			buildingButtons[buildingName] = React.createElement("ImageButton", {
				ref = buttonRef,
				Size = UDim2.fromOffset(60, 60),
				BackgroundTransparency = 1,
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
							tooltipLines[#tooltipLines + 1] = "⚙️ Uses "
								.. buildingInfo.consumes_resource:gsub("_", " ")
						end

						-- Training
						if buildingInfo.can_train_units then
							tooltipLines[#tooltipLines + 1] = "⚔️ Trains: "
								.. table.concat(buildingInfo.can_train_units, ", ")
						end

						-- Build time
						tooltipLines[#tooltipLines + 1] = "\n⏱️ "
							.. buildingInfo.construction.build_time_seconds
							.. "s"

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
			PaddingTop = UDim.new(0, 0),
			PaddingBottom = UDim.new(0, 0),
			PaddingLeft = UDim.new(0, 0),
			PaddingRight = UDim.new(0, 0),
		}),

		BuildingsGrid = React.createElement("Frame", {
			Size = UDim2.fromScale(1, 1),
			Position = UDim2.fromOffset(0, 0),
			AnchorPoint = Vector2.new(0, 0),
			BackgroundTransparency = 1,
		}, buildingButtons),
	})
end

return BuildingMenu
