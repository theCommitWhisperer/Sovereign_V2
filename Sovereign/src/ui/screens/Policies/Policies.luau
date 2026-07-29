--!strict
-- Policies modal for managing kingdom policies.
-- Taxation and Food Rations are live: clicking a policy fires the "SetPolicy"
-- GameEvent action; the server (TaxManager/ConsumptionManager via
-- EconomyConfig) applies it and echoes "PolicyUpdated" back.
local React = require(game.ReplicatedStorage.Packages.react)
local Modal = require(script.Parent.Parent.Parent.components.Modal)
local UIConfig = require(script.Parent.Parent.Parent.UIConfig)
local EconomyConfig = require(game.ReplicatedStorage.Shared.GameData.EconomyConfig)

local Policies = React.Component:extend("Policies")

export type Props = {
	visible: boolean,
	onClose: () -> (),
	happiness: number?, -- current kingdom happiness (drives the tax popularity tier readout)
	size: UDim2?, -- forwarded to Modal; MobileShell passes a near-fullscreen size, desktop leaves it nil
}

-- Per-policy numeric effect line, pulled straight from EconomyConfig so the
-- UI can never drift from what the server actually applies.
local function getPolicyEffectText(categoryName: string, policyName: string): string?
	if categoryName == "Taxation" then
		local policy = EconomyConfig.TaxPolicies[policyName]
		if policy then
			return string.format("💰 Tax rate: %d%%", math.floor(policy.rate * 100 + 0.5))
		end
	elseif categoryName == "Food Rations" then
		local policy = EconomyConfig.RationsPolicies[policyName]
		if policy then
			local sign = if policy.happinessModifier > 0 then "+" else ""
			return string.format(
				"🍴 Food use ×%.1f   ❤️ Happiness %s%d",
				policy.consumptionMultiplier,
				sign,
				policy.happinessModifier
			)
		end
	end
	return nil
end

local POLICY_CATEGORIES = {
	{
		name = "Taxation",
		interactive = true,
		policies = {
			{ name = "No Tax", description = "No taxation on peasants. Maximum popularity." },
			{ name = "Low Tax", description = "Small tax increase. Slight popularity decrease." },
			{ name = "Normal Tax", description = "Moderate taxation. Balanced approach." },
			{ name = "High Tax", description = "Heavy taxation. Significant popularity decrease." },
		},
	},
	{
		name = "Food Rations",
		interactive = true,
		policies = {
			{ name = "Double Rations", description = "Extra food for everyone. High popularity boost." },
			{ name = "Extra Rations", description = "Increased food rations. Popularity boost." },
			{ name = "Normal Rations", description = "Standard food distribution." },
			{ name = "Half Rations", description = "Reduced food rations. Popularity decrease." },
		},
	},
	{
		name = "Military",
		interactive = false, -- placeholder category (not wired server-side yet)
		policies = {
			{ name = "Aggressive", description = "Focus on offense and expansion." },
			{ name = "Defensive", description = "Focus on fortifications and defense." },
			{ name = "Balanced", description = "Equal focus on offense and defense." },
		},
	},
}

function Policies:init()
	self:setState({
		selected = {
			["Taxation"] = "Normal Tax",
			["Food Rations"] = "Normal Rations",
			["Military"] = "Balanced",
		},
	})
end

function Policies:didMount()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents", 10)
	self.gameEvent = RemoteEvents and RemoteEvents:WaitForChild("GameEvent", 10)

	-- Keep selection in sync with the server's confirmation
	if self.gameEvent then
		self.policyConnection = self.gameEvent.OnClientEvent:Connect(function(action, data)
			if action == "PolicyUpdated" and typeof(data) == "table" then
				local selected = table.clone(self.state.selected)
				selected[data.category] = data.policy
				self:setState({ selected = selected })
			end
		end)
	end
end

function Policies:willUnmount()
	if self.policyConnection then
		self.policyConnection:Disconnect()
	end
end

function Policies:selectPolicy(categoryName: string, policyName: string, interactive: boolean)
	-- Optimistic local highlight; server confirms via PolicyUpdated
	local selected = table.clone(self.state.selected)
	selected[categoryName] = policyName
	self:setState({ selected = selected })

	if interactive and self.gameEvent then
		self.gameEvent:FireServer("SetPolicy", {
			category = categoryName,
			policy = policyName,
		})
	end
end

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
			local isSelected = self.state.selected[category.name] == policy.name
			local categoryName = category.name
			local policyName = policy.name
			local interactive = category.interactive == true
			local effectText = getPolicyEffectText(categoryName, policyName)

			policyButtons[policy.name] = React.createElement("TextButton", {
				Size = UDim2.new(1, 0, 0, effectText and 88 or 70),
				BackgroundColor3 = UIConfig.HUD.UtilityButtonBackground,
				BackgroundTransparency = interactive and 0 or 0.4, -- placeholder categories look disabled
				BorderSizePixel = isSelected and 3 or 2,
				BorderColor3 = isSelected and Color3.fromRGB(255, 215, 0) or UIConfig.HUD.UtilityButtonBorder,
				Text = "",
				AutoButtonColor = interactive,
				LayoutOrder = j,
				[React.Event.Activated] = function()
					self:selectPolicy(categoryName, policyName, interactive)
				end,
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
					TextColor3 = interactive and UIConfig.HUD.PanelHeaderColor or Color3.fromRGB(140, 130, 120),
					TextXAlignment = Enum.TextXAlignment.Left,
					LayoutOrder = 1,
				}),

				Description = React.createElement("TextLabel", {
					Size = UDim2.new(1, 0, 0, 30),
					BackgroundTransparency = 1,
					Text = policy.description,
					Font = Enum.Font.Gotham,
					TextSize = 14,
					TextColor3 = interactive and UIConfig.HUD.PanelTextColor or Color3.fromRGB(120, 112, 104),
					TextXAlignment = Enum.TextXAlignment.Left,
					TextWrapped = true,
					LayoutOrder = 2,
				}),

				-- Numeric effect readout (from EconomyConfig — matches the server)
				Effect = effectText and React.createElement("TextLabel", {
					Size = UDim2.new(1, 0, 0, 16),
					BackgroundTransparency = 1,
					Text = effectText,
					Font = Enum.Font.GothamBold,
					TextSize = 14,
					TextColor3 = isSelected and Color3.fromRGB(255, 215, 0) or Color3.fromRGB(160, 190, 160),
					TextXAlignment = Enum.TextXAlignment.Left,
					LayoutOrder = 3,
				}) or nil,
			})
		end

		-- Live "what's in effect right now" summary under each category header
		local happiness = self.props.happiness or 50
		local currentSummary: string? = nil
		if category.name == "Taxation" then
			local selectedPolicy = EconomyConfig.TaxPolicies[self.state.selected["Taxation"]]
			if selectedPolicy then
				local tierMult = EconomyConfig.getTaxPopularityMultiplier(happiness)
				currentSummary = string.format(
					"Now: %d%% tax × %.2f popularity multiplier (happiness %d) = %.1f%% effective income",
					math.floor(selectedPolicy.rate * 100 + 0.5),
					tierMult,
					math.floor(happiness),
					selectedPolicy.rate * tierMult * 100
				)
			end
		elseif category.name == "Food Rations" then
			local selectedPolicy = EconomyConfig.RationsPolicies[self.state.selected["Food Rations"]]
			if selectedPolicy then
				local sign = if selectedPolicy.happinessModifier > 0 then "+" else ""
				currentSummary = string.format(
					"Now: peasants eat ×%.1f food, %s%d happiness",
					selectedPolicy.consumptionMultiplier,
					sign,
					selectedPolicy.happinessModifier
				)
			end
		elseif category.name == "Military" then
			currentSummary = "Coming soon — military doctrine is not yet in effect."
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
				Text = category.interactive and category.name or (category.name .. "  🔒"),
				Font = Enum.Font.GothamBold,
				TextSize = 24,
				TextColor3 = category.interactive and UIConfig.HUD.PanelHeaderColor
					or Color3.fromRGB(140, 130, 120),
				TextXAlignment = Enum.TextXAlignment.Left,
				LayoutOrder = 1,
			}),

			CurrentEffect = currentSummary and React.createElement("TextLabel", {
				Size = UDim2.new(1, 0, 0, 18),
				BackgroundTransparency = 1,
				Text = currentSummary,
				Font = Enum.Font.Gotham,
				TextSize = 14,
				TextColor3 = category.interactive and Color3.fromRGB(255, 215, 0)
					or Color3.fromRGB(120, 112, 104),
				TextXAlignment = Enum.TextXAlignment.Left,
				LayoutOrder = 2, -- header (1) → current-effect summary (2) → policy list (3)
			}) or nil,

			Policies = React.createElement("Frame", {
				Size = UDim2.new(1, 0, 0, 0),
				BackgroundTransparency = 1,
				AutomaticSize = Enum.AutomaticSize.Y,
				LayoutOrder = 3,
			}, policyButtons),
		})
	end

	return React.createElement(Modal, {
		title = "Kingdom Policies",
		visible = self.props.visible,
		onClose = self.props.onClose,
		size = self.props.size,
	}, policyContent)
end

return Policies
