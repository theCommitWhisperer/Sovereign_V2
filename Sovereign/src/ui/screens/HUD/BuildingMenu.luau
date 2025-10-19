local React = require(game.ReplicatedStorage.Packages.react)
local UIConfig = require(script.Parent.Parent.Parent.UIConfig)

local BuildingMenu = React.Component:extend("BuildingMenu")

local BUILDING_CATEGORIES = {
	{
		name = "Housing",
		buildings = { "Hovel" },
	},
	{
		name = "Storage",
		buildings = { "Storehouse", "Granary" },
	},
	{
		name = "Resources",
		buildings = { "Woodcutters_Post", "Stone_Quarry" },
	},
	{
		name = "Food",
		buildings = { "Farm", "Kitchen", "Restaurant" },
	},
	{
		name = "Military",
		buildings = { "Barracks" },
	},
}

function BuildingMenu:init()
	self:setState({
		selectedCategory = 1,
	})
end

function BuildingMenu:render()
	local resources = self.props.resources or {}

	-- Category tabs
	local categoryTabs = {}
	categoryTabs.Layout = React.createElement("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 5),
	})

	for i, category in ipairs(BUILDING_CATEGORIES) do
		categoryTabs[category.name] = React.createElement("TextButton", {
			Size = UDim2.new(0, 120, 0, 40),
			Text = category.name,
			Font = Enum.Font.GothamBold,
			TextSize = 14,
			TextColor3 = self.state.selectedCategory == i and Color3.fromRGB(255, 255, 255)
				or Color3.fromRGB(150, 150, 150),
			BackgroundColor3 = self.state.selectedCategory == i and Color3.fromRGB(60, 60, 70)
				or Color3.fromRGB(40, 40, 50),
			BorderSizePixel = 0,
			[React.Event.MouseButton1Click] = function()
				self:setState({ selectedCategory = i })
			end,
		})
	end

	-- Building buttons
	local buildingButtons = {}
	buildingButtons.Layout = React.createElement("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 10),
	})

	local selectedCategoryData = BUILDING_CATEGORIES[self.state.selectedCategory]
	if selectedCategoryData then
		local GameData = require(game.ReplicatedStorage.Shared.GameData)

		for i, buildingName in ipairs(selectedCategoryData.buildings) do
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

				-- Create cost string
				local costText = ""
				for resource, cost in pairs(buildingInfo.cost) do
					if costText ~= "" then
						costText = costText .. ", "
					end
					costText = costText .. resource:gsub("_", " ") .. ": " .. cost
				end

				buildingButtons[buildingName] = React.createElement("TextButton", {
					Size = UDim2.new(0, 120, 1, -50),
					Text = "",
					BackgroundColor3 = canAfford and Color3.fromRGB(50, 50, 60) or Color3.fromRGB(80, 40, 40),
					BorderSizePixel = 1,
					BorderColor3 = Color3.fromRGB(100, 100, 100),
					[React.Event.MouseButton1Click] = function()
						if canAfford and self.props.onBuildingSelected then
							self.props.onBuildingSelected(buildingName)
						end
					end,
				}, {
					Layout = React.createElement("UIListLayout", {
						FillDirection = Enum.FillDirection.Vertical,
						VerticalAlignment = Enum.VerticalAlignment.Center,
						Padding = UDim.new(0, 5),
					}),

					Name = React.createElement("TextLabel", {
						Size = UDim2.new(1, 0, 0, 20),
						Text = buildingName:gsub("_", " "),
						Font = Enum.Font.GothamBold,
						TextSize = 14,
						TextColor3 = Color3.fromRGB(255, 255, 255),
						BackgroundTransparency = 1,
					}),

					Cost = React.createElement("TextLabel", {
						Size = UDim2.new(1, 0, 0, 30),
						Text = costText,
						Font = Enum.Font.Gotham,
						TextSize = 10,
						TextColor3 = canAfford and Color3.fromRGB(200, 200, 200) or Color3.fromRGB(255, 100, 100),
						BackgroundTransparency = 1,
						TextWrapped = true,
					}),
				})
			end
		end
	end

	return React.createElement("Frame", {
		Name = "BuildingMenu",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
	}, {
		CategoryTabs = React.createElement("Frame", {
			Size = UDim2.new(1, 0, 0, 40),
			BackgroundTransparency = 1,
		}, categoryTabs),

		BuildingsGrid = React.createElement("Frame", {
			Size = UDim2.new(1, 0, 1, -50),
			Position = UDim2.new(0, 0, 0, 45),
			BackgroundTransparency = 1,
		}, buildingButtons),
	})
end

return BuildingMenu
