--[[
	Undo Button Component
	Allows players to undo the last 5 building deletions
]]

local React = require(game.ReplicatedStorage.Packages.react)
local UIConfig = require(script.Parent.Parent.Parent.UIConfig)
local IconButton = require(script.Parent.Parent.Parent.components.IconButton)

local UndoButton = function(props)
	local hasHistory = props.deletionHistory and #props.deletionHistory > 0
	local lastDeletion = hasHistory and props.deletionHistory[#props.deletionHistory] or nil

	-- Show tooltip with last deleted building name
	local tooltipText = if lastDeletion
		then string.format("Undo: %s (Ctrl+Z)", lastDeletion.buildingType)
		else "Nothing to undo"

	return React.createElement("Frame", {
		Size = UDim2.new(0, 100, 0, 40),
		Position = props.Position or UDim2.new(1, -120, 1, -UIConfig.HUD.BottomBarHeight - 60),
		BackgroundTransparency = 1,
		ZIndex = 15,
	}, {
		Button = React.createElement(IconButton, {
			Name = "UndoButton",
			Size = UDim2.new(1, 0, 1, 0),
			Icon = "↶",
			IconSize = 24,
			IconColor = hasHistory and UIConfig.HUD.PanelTextColor or Color3.fromRGB(100, 100, 100),
			ImageColor3 = hasHistory and UIConfig.HUD.CategoryButtonSelected or Color3.fromRGB(60, 60, 60),
			OnClick = hasHistory and props.onUndo or function() end,
			ShowGlow = hasHistory,
		}),

		Label = React.createElement("TextLabel", {
			Size = UDim2.new(1, 0, 0, 14),
			Position = UDim2.new(0, 0, 1, 2),
			BackgroundTransparency = 1,
			Text = hasHistory and "UNDO (Ctrl+Z)" or "No history",
			TextColor3 = hasHistory and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(120, 120, 120),
			TextSize = 10,
			Font = Enum.Font.GothamBold,
			TextYAlignment = Enum.TextYAlignment.Top,
		}),

		-- History count badge
		Badge = hasHistory and React.createElement("Frame", {
			Size = UDim2.fromOffset(20, 20),
			Position = UDim2.new(1, -5, 0, -5),
			AnchorPoint = Vector2.new(1, 0),
			BackgroundColor3 = UIConfig.HUD.AccentGold,
			BorderSizePixel = 0,
			ZIndex = 16,
		}, {
			Corner = React.createElement("UICorner", {
				CornerRadius = UDim.new(0.5, 0),
			}),
			Count = React.createElement("TextLabel", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Text = tostring(#props.deletionHistory),
				TextColor3 = Color3.fromRGB(0, 0, 0),
				TextSize = 12,
				Font = Enum.Font.GothamBold,
			}),
		}) or nil,
	})
end

return UndoButton
