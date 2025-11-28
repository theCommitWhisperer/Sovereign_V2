--!strict
-- Policies modal for managing kingdom policies
local React = require(game.ReplicatedStorage.Packages.react)
local Modal = require(script.Parent.Parent.Parent.components.Modal)
local UIConfig = require(script.Parent.Parent.Parent.UIConfig)

local Policies = React.Component:extend("Policies")

export type Props = {
	visible: boolean,
	onClose: () -> (),
}

-- Placeholder policies data (will be expanded later)
local POLICY_CATEGORIES = {
	{
		name = "Taxation",
		policies = {
			{ name = "No Tax", description = "No taxation on peasants. Maximum popularity." },
			{ name = "Low Tax", description = "Small tax increase. Slight popularity decrease." },
			{ name = "Normal Tax", description = "Moderate taxation. Balanced approach." },
			{ name = "High Tax", description = "Heavy taxation. Significant popularity decrease." },
		},
	},
	{
		name = "Food Rations",
		policies = {
			{ name = "Double Rations", description = "Extra food for everyone. High popularity boost." },
			{ name = "Extra Rations", description = "Increased food rations. Popularity boost." },
			{ name = "Normal Rations", description = "Standard food distribution." },
			{ name = "Half Rations", description = "Reduced food rations. Popularity decrease." },
		},
	},
	{
		name = "Military",
		policies = {
			{ name = "Aggressive", description = "Focus on offense and expansion." },
			{ name = "Defensive", description = "Focus on fortifications and defense." },
			{ name = "Balanced", description = "Equal focus on offense and defense." },
		},
	},
}

function Policies:render()
	local policyContent = {}

	-- Create sections for each policy category
	for i, category in ipairs(POLICY_CATEGORIES) do
		local policyButtons = {}

		policyButtons.Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		})

		-- Create button for each policy in category
		for j, policy in ipairs(category.policies) do
			policyButtons[policy.name] = React.createElement("Frame", {
				Size = UDim2.new(1, 0, 0, 70),
				BackgroundColor3 = UIConfig.HUD.UtilityButtonBackground,
				BorderSizePixel = 2,
				BorderColor3 = UIConfig.HUD.UtilityButtonBorder,
				LayoutOrder = j,
			}, {
				Padding = React.createElement("UIPadding", {
					PaddingTop = UDim.new(0, 10),
					PaddingBottom = UDim.new(0, 10),
					PaddingLeft = UDim.new(0, 15),
					PaddingRight = UDim.new(0, 15),
				}),

				Layout = React.createElement("UIListLayout", {
					FillDirection = Enum.FillDirection.Vertical,
					Padding = UDim.new(0, 5),
				}),

				Name = React.createElement("TextLabel", {
					Size = UDim2.new(1, 0, 0, 20),
					BackgroundTransparency = 1,
					Text = policy.name,
					Font = Enum.Font.GothamBold,
					TextSize = 18,
					TextColor3 = UIConfig.HUD.PanelHeaderColor,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),

				Description = React.createElement("TextLabel", {
					Size = UDim2.new(1, 0, 0, 30),
					BackgroundTransparency = 1,
					Text = policy.description,
					Font = Enum.Font.Gotham,
					TextSize = 14,
					TextColor3 = UIConfig.HUD.PanelTextColor,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextWrapped = true,
				}),
			})
		end

		-- Create category section
		policyContent[category.name] = React.createElement("Frame", {
			Size = UDim2.new(1, 0, 0, 0),
			BackgroundTransparency = 1,
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = i,
		}, {
			Layout = React.createElement("UIListLayout", {
				FillDirection = Enum.FillDirection.Vertical,
				Padding = UDim.new(0, 10),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),

			Header = React.createElement("TextLabel", {
				Size = UDim2.new(1, 0, 0, 30),
				BackgroundTransparency = 1,
				Text = category.name,
				Font = Enum.Font.GothamBold,
				TextSize = 24,
				TextColor3 = UIConfig.HUD.PanelHeaderColor,
				TextXAlignment = Enum.TextXAlignment.Left,
				LayoutOrder = 1,
			}),

			Policies = React.createElement("Frame", {
				Size = UDim2.new(1, 0, 0, 0),
				BackgroundTransparency = 1,
				AutomaticSize = Enum.AutomaticSize.Y,
				LayoutOrder = 2,
			}, policyButtons),
		})
	end

	return React.createElement(Modal, {
		title = "Kingdom Policies",
		visible = self.props.visible,
		onClose = self.props.onClose,
	}, policyContent)
end

return Policies
