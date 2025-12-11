--!strict
-- MultiDeleteModal: Shows confirmation dialog for deleting multiple buildings at once

local React = require(game.ReplicatedStorage.Packages.react)
local UIConfig = require(script.Parent.Parent.Parent.UIConfig)

local MultiDeleteModal = {}

export type BuildingInfo = {
	name: string,
	type: string,
	model: Model,
	isWall: boolean,
}

export type Props = {
	buildings: { BuildingInfo },
	totalRefund: string?,
	onConfirm: (selectedBuildings: { BuildingInfo }) -> (),
	onCancel: () -> (),
}

-- Map building types to friendly display names
local FRIENDLY_NAMES: { [string]: string } = {
	Stone_Wall = "Stone Wall",
	Wooden_Wall = "Wooden Wall",
	Wall_Gatehouse = "Gatehouse",
	Wall_Tower = "Wall Tower",
	Keep = "Keep",
	Storehouse = "Storehouse",
	Granary = "Granary",
	Barracks = "Barracks",
	House = "House",
	Farm = "Farm",
	Mine = "Mine",
	Quarry = "Quarry",
	Lumber_Mill = "Lumber Mill",
	Blacksmith = "Blacksmith",
	Market = "Market",
}

local function getFriendlyName(buildingType: string): string
	return FRIENDLY_NAMES[buildingType] or buildingType
end

local function MultiDeleteModalComponent(props: Props)
	local buildingCount = #props.buildings

	-- State for which buildings are selected (all selected by default)
	local selectedStates, setSelectedStates = React.useState(function()
		local states = {}
		for i = 1, buildingCount do
			states[i] = true
		end
		return states
	end)

	-- Calculate selected count and summary
	local selectedCount = 0
	local buildingsByType: { [string]: number } = {}
	for i, building in props.buildings do
		if selectedStates[i] then
			selectedCount = selectedCount + 1
			buildingsByType[building.type] = (buildingsByType[building.type] or 0) + 1
		end
	end

	-- Create summary text with friendly names
	local summaryParts = {}
	for buildingType, count in pairs(buildingsByType) do
		local friendlyName = getFriendlyName(buildingType)
		local displayName = count > 1 and friendlyName .. "s" or friendlyName
		table.insert(summaryParts, string.format("%d %s", count, displayName))
	end
	local summaryText = if #summaryParts > 0 then table.concat(summaryParts, ", ") else "None selected"

	-- Build list of checkboxes
	local buildingListElements = {}
	for i, building in props.buildings do
		local friendlyName = getFriendlyName(building.type)

		buildingListElements["Building" .. i] = React.createElement("Frame", {
			Size = UDim2.new(1, -10, 0, 28),
			BackgroundColor3 = Color3.fromRGB(35, 28, 20),
			BackgroundTransparency = 0.3,
			BorderSizePixel = 0,
			LayoutOrder = i,
		}, {
			Checkbox = React.createElement("TextButton", {
				Size = UDim2.fromOffset(20, 20),
				Position = UDim2.fromOffset(5, 4),
				BackgroundColor3 = Color3.fromRGB(80, 65, 50),
				BorderSizePixel = 1,
				BorderColor3 = Color3.fromRGB(120, 100, 80),
				Text = selectedStates[i] and "X" or "",
				Font = Enum.Font.GothamBold,
				TextSize = 16,
				TextColor3 = Color3.fromRGB(255, 220, 180),
				[React.Event.MouseButton1Click] = function()
					local newStates = table.clone(selectedStates)
					newStates[i] = not newStates[i]
					setSelectedStates(newStates)
				end,
			}),

			Label = React.createElement("TextLabel", {
				Size = UDim2.new(1, -35, 1, 0),
				Position = UDim2.fromOffset(30, 0),
				BackgroundTransparency = 1,
				Text = friendlyName,
				Font = Enum.Font.Gotham,
				TextSize = 13,
				TextColor3 = Color3.fromRGB(220, 200, 170),
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
		})
	end

	local listHeight = math.min(buildingCount * 28, 150)

	return React.createElement("Frame", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.3,
		ZIndex = 1000,
	}, {
		DialogBox = React.createElement("Frame", {
			Size = UDim2.fromOffset(420, 300 + listHeight),
			Position = UDim2.new(0.5, 0, 0.5, 0),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Color3.fromRGB(45, 35, 25), -- Dark medieval brown
			BorderSizePixel = 3,
			BorderColor3 = Color3.fromRGB(80, 60, 40), -- Medieval border
			ZIndex = 1001,
		}, {
			UICorner = React.createElement("UICorner", {
				CornerRadius = UDim.new(0, 6),
			}),

			Padding = React.createElement("UIPadding", {
				PaddingTop = UDim.new(0, 20),
				PaddingBottom = UDim.new(0, 20),
				PaddingLeft = UDim.new(0, 25),
				PaddingRight = UDim.new(0, 25),
			}),

			Layout = React.createElement("UIListLayout", {
				FillDirection = Enum.FillDirection.Vertical,
				Padding = UDim.new(0, 8),
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Top,
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),

			Title = React.createElement("TextLabel", {
				Size = UDim2.new(1, 0, 0, 30),
				BackgroundTransparency = 1,
				Text = "CONFIRM DESTRUCTION",
				Font = Enum.Font.Garamond,
				TextSize = 22,
				TextColor3 = Color3.fromRGB(220, 180, 120), -- Medieval gold
				TextXAlignment = Enum.TextXAlignment.Center,
				LayoutOrder = 1,
			}),

			Instructions = React.createElement("TextLabel", {
				Size = UDim2.new(1, 0, 0, 20),
				BackgroundTransparency = 1,
				Text = "Select structures to destroy:",
				Font = Enum.Font.Garamond,
				TextSize = 14,
				TextColor3 = Color3.fromRGB(200, 180, 150),
				TextXAlignment = Enum.TextXAlignment.Center,
				LayoutOrder = 2,
			}),

			BuildingListContainer = React.createElement("ScrollingFrame", {
				Size = UDim2.new(1, 0, 0, listHeight),
				BackgroundColor3 = Color3.fromRGB(30, 24, 18),
				BackgroundTransparency = 0.3,
				BorderSizePixel = 1,
				BorderColor3 = Color3.fromRGB(80, 60, 40),
				ScrollBarThickness = 6,
				CanvasSize = UDim2.fromOffset(0, buildingCount * 28),
				LayoutOrder = 3,
			}, {
				UICorner = React.createElement("UICorner", {
					CornerRadius = UDim.new(0, 4),
				}),

				ListLayout = React.createElement("UIListLayout", {
					FillDirection = Enum.FillDirection.Vertical,
					Padding = UDim.new(0, 2),
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),

				Buildings = React.createElement(React.Fragment, nil, buildingListElements),
			}),

			Summary = React.createElement("TextLabel", {
				Size = UDim2.new(1, 0, 0, 35),
				BackgroundTransparency = 1,
				Text = string.format("Selected: %s", summaryText),
				Font = Enum.Font.GothamBold,
				TextSize = 14,
				TextColor3 = Color3.fromRGB(255, 220, 180),
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Center,
				LayoutOrder = 4,
			}),

			RefundInfo = props.totalRefund and React.createElement("TextLabel", {
				Size = UDim2.new(1, 0, 0, 24),
				BackgroundTransparency = 1,
				Text = "Reclaimed Resources: " .. props.totalRefund,
				Font = Enum.Font.GothamBold,
				TextSize = 13,
				TextColor3 = Color3.fromRGB(255, 215, 0), -- Gold
				TextXAlignment = Enum.TextXAlignment.Center,
				LayoutOrder = 5,
			}) or nil,

			Warning = React.createElement("TextLabel", {
				Size = UDim2.new(1, 0, 0, 22),
				BackgroundTransparency = 1,
				Text = "This action cannot be undone!",
				Font = Enum.Font.GothamBold,
				TextSize = 12,
				TextColor3 = Color3.fromRGB(200, 50, 50),
				TextXAlignment = Enum.TextXAlignment.Center,
				LayoutOrder = 6,
			}),

			ButtonContainer = React.createElement("Frame", {
				Size = UDim2.new(1, 0, 0, 45),
				BackgroundTransparency = 1,
				LayoutOrder = 7,
			}, {
				Layout = React.createElement("UIListLayout", {
					FillDirection = Enum.FillDirection.Horizontal,
					Padding = UDim.new(0, 12),
					HorizontalAlignment = Enum.HorizontalAlignment.Center,
				}),

				CancelButton = React.createElement("TextButton", {
					Size = UDim2.fromOffset(160, 40),
					BackgroundColor3 = Color3.fromRGB(60, 50, 40),
					BorderSizePixel = 2,
					BorderColor3 = Color3.fromRGB(100, 80, 60),
					Text = "Cancel",
					Font = Enum.Font.GothamBold,
					TextSize = 16,
					TextColor3 = Color3.fromRGB(200, 180, 150),
					[React.Event.MouseButton1Click] = props.onCancel,
				}, {
					UICorner = React.createElement("UICorner", {
						CornerRadius = UDim.new(0, 5),
					}),
				}),

				ConfirmButton = React.createElement("TextButton", {
					Size = UDim2.fromOffset(160, 40),
					BackgroundColor3 = if selectedCount > 0
						then Color3.fromRGB(140, 30, 30)
						else Color3.fromRGB(80, 80, 80), -- Disabled gray
					BorderSizePixel = 2,
					BorderColor3 = if selectedCount > 0 then Color3.fromRGB(100, 20, 20) else Color3.fromRGB(60, 60, 60),
					Text = string.format("Destroy (%d)", selectedCount),
					Font = Enum.Font.GothamBold,
					TextSize = 16,
					TextColor3 = Color3.new(1, 1, 1),
					AutoButtonColor = selectedCount > 0,
					[React.Event.MouseButton1Click] = function()
						print("[MultiDeleteModal] Destroy button clicked. selectedCount:", selectedCount)
						if selectedCount == 0 then
							print("[MultiDeleteModal] No buildings selected, returning")
							return
						end

						-- Build list of selected buildings
						local selectedBuildings = {}
						for i, building in props.buildings do
							if selectedStates[i] then
								table.insert(selectedBuildings, building)
							end
						end

						print("[MultiDeleteModal] Calling onConfirm with", #selectedBuildings, "buildings")
						props.onConfirm(selectedBuildings)
					end,
				}, {
					UICorner = React.createElement("UICorner", {
						CornerRadius = UDim.new(0, 5),
					}),
				}),
			}),
		}),
	})
end

-- Wrapper function to maintain .new() API
function MultiDeleteModal.new(props: Props)
	return React.createElement(MultiDeleteModalComponent, props)
end

return MultiDeleteModal
