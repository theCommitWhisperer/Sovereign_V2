local React = require(game.ReplicatedStorage.Packages.react)
local UIConfig = require(script.Parent.Parent.Parent.UIConfig)

local SelectionPanel = React.Component:extend("SelectionPanel")

function SelectionPanel:render()
	local selectedUnits = self.props.selectedUnits or {}
	local unitCount = #selectedUnits

	if unitCount == 0 then
		return nil -- Don't show panel if nothing selected
	end

	-- Group units by type
	local unitGroups = {}
	for _, unit in selectedUnits do
		local unitType = unit:GetAttribute("UnitType") or "Unknown"
		if not unitGroups[unitType] then
			unitGroups[unitType] = 0
		end
		unitGroups[unitType] = unitGroups[unitType] + 1
	end

	-- Create display text
	local displayText = ""
	local displayLines = {}
	for unitType, count in unitGroups do
		if count > 1 then
			table.insert(displayLines, `{count}x {unitType}`)
		else
			table.insert(displayLines, unitType)
		end
	end
	displayText = table.concat(displayLines, "\n")

	return React.createElement("Frame", {
		Name = "SelectionPanel",
		Size = UDim2.new(0, 250, 0, 100),
		Position = UDim2.new(0, 10, 1, -260),
		AnchorPoint = Vector2.new(0, 0),
		BackgroundColor3 = Color3.fromRGB(40, 40, 45),
		BorderSizePixel = 2,
		BorderColor3 = Color3.fromRGB(100, 100, 100),
	}, {
		Padding = React.createElement("UIPadding", {
			PaddingTop = UDim.new(0, 8),
			PaddingBottom = UDim.new(0, 8),
			PaddingLeft = UDim.new(0, 8),
			PaddingRight = UDim.new(0, 8),
		}),

		Header = React.createElement("TextLabel", {
			Size = UDim2.new(1, 0, 0, 20),
			BackgroundTransparency = 1,
			Text = "Selected Units",
			Font = Enum.Font.GothamBold,
			TextSize = 14,
			TextColor3 = Color3.fromRGB(255, 255, 255),
			TextXAlignment = Enum.TextXAlignment.Left,
		}),

		Content = React.createElement("TextLabel", {
			Size = UDim2.new(1, 0, 1, -25),
			Position = UDim2.new(0, 0, 0, 25),
			BackgroundTransparency = 1,
			Text = displayText,
			Font = Enum.Font.Gotham,
			TextSize = 16,
			TextColor3 = Color3.fromRGB(200, 200, 200),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
		}),
	})
end

return SelectionPanel
