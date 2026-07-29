local React = require(game.ReplicatedStorage.Packages.react)
local UIConfig = require(script.Parent.Parent.Parent.UIConfig)
local Platform = require(script.Parent.Parent.Parent.Platform)

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

	local tokens = Platform.tokens
	-- Offsets (not tokens.padding directly) so Desktop reproduces the original
	-- 10px/12px hardcoded here exactly: tokens.padding is 8 on Desktop, so
	-- `padding + 2` / `padding + 4` land back on 10/12. Mobile's bigger padding
	-- token still grows these, just from the same baseline.
	local paddingTopBottom = tokens.padding + 2
	local paddingLeftRight = tokens.padding + 4

	return React.createElement("Frame", {
		Name = "SelectionPanel",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, {
		Padding = React.createElement("UIPadding", {
			PaddingTop = UDim.new(0, paddingTopBottom),
			PaddingBottom = UDim.new(0, paddingTopBottom),
			PaddingLeft = UDim.new(0, paddingLeftRight),
			PaddingRight = UDim.new(0, paddingLeftRight),
		}),

		Header = React.createElement("TextLabel", {
			Size = UDim2.new(1, 0, 0, 24 * tokens.fontScale),
			BackgroundTransparency = 1,
			Text = "Selected Units",
			Font = Enum.Font.GothamBold,
			TextSize = 16 * tokens.fontScale,
			TextColor3 = UIConfig.HUD.PanelHeaderColor,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),

		Content = React.createElement("TextLabel", {
			Size = UDim2.new(1, 0, 1, -30),
			Position = UDim2.new(0, 0, 0, 30),
			BackgroundTransparency = 1,
			Text = displayText,
			Font = Enum.Font.Gotham,
			TextSize = 18 * tokens.fontScale,
			TextColor3 = UIConfig.HUD.PanelTextColor,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
		}),
	})
end

return SelectionPanel
