--!strict
-- UpgradePanel: Shows available upgrades for selected building

local React = require(game.ReplicatedStorage.Packages.react)
local UIConfig = require(script.Parent.Parent.Parent.UIConfig)
local Panel = require(script.Parent.Parent.Parent.components.Panel)
local Button = require(script.Parent.Parent.Parent.components.Button)

local UpgradePanel = React.Component:extend("UpgradePanel")

function UpgradePanel:init()
	self:setState({
		currentLevel = 1,
		nextUpgrade = nil,
		canAfford = false,
	})
end

function UpgradePanel:render()
	local building = self.props.building
	if not building then
		return nil
	end

	local buildingType = building:GetAttribute("BuildingType")
	local currentLevel = building:GetAttribute("UpgradeLevel") or 1
	local nextUpgrade = self.props.upgradeInfo
	local playerResources = self.props.playerResources or {}

	-- Check if player can afford upgrade
	local canAfford = true
	if nextUpgrade and nextUpgrade.cost then
		for resource, cost in pairs(nextUpgrade.cost) do
			if (playerResources[resource] or 0) < cost then
				canAfford = false
				break
			end
		end
	end

	-- Resource icon mapping
	local resourceIcons = {
		Wood = "🌲",
		Stone = "🪨",
		Gold = "💰",
		Iron_Bars = "⚒️",
	}

	-- Build cost display elements
	local costElements = {}
	if nextUpgrade and nextUpgrade.cost then
		local index = 0
		for resource, cost in pairs(nextUpgrade.cost) do
			index = index + 1
			local hasEnough = (playerResources[resource] or 0) >= cost
			costElements["Cost_" .. resource] = React.createElement("TextLabel", {
				Size = UDim2.new(0.5, -5, 0, 20),
				Position = UDim2.new((index - 1) % 2 * 0.5, 5, math.floor((index - 1) / 2) * 25, 0),
				BackgroundTransparency = 1,
				Text = string.format(
					"%s %s: %d",
					resourceIcons[resource] or "•",
					resource:gsub("_", " "),
					cost
				),
				TextColor3 = hasEnough and UIConfig.HUD.BuildingButtonAffordable
					or UIConfig.HUD.BuildingButtonUnaffordable,
				TextSize = 14,
				Font = UIConfig.Font.Default,
				TextXAlignment = Enum.TextXAlignment.Left,
			})
		end
	end

	-- Build bonus display elements
	local bonusElements = {}
	if nextUpgrade then
		local index = 0
		if nextUpgrade.productionBonus then
			index = index + 1
			bonusElements["Bonus_Production"] = React.createElement("TextLabel", {
				Size = UDim2.new(1, -10, 0, 18),
				Position = UDim2.fromOffset(5, (index - 1) * 20),
				BackgroundTransparency = 1,
				Text = string.format("📈 Production: +%d%%", (nextUpgrade.productionBonus - 1) * 100),
				TextColor3 = UIConfig.HUD.AccentGold,
				TextSize = 14,
				Font = UIConfig.Font.Default,
				TextXAlignment = Enum.TextXAlignment.Left,
			})
		end
		if nextUpgrade.storageBonus then
			index = index + 1
			bonusElements["Bonus_Storage"] = React.createElement("TextLabel", {
				Size = UDim2.new(1, -10, 0, 18),
				Position = UDim2.fromOffset(5, (index - 1) * 20),
				BackgroundTransparency = 1,
				Text = string.format("📦 Storage: +%d%%", (nextUpgrade.storageBonus - 1) * 100),
				TextColor3 = UIConfig.HUD.AccentGold,
				TextSize = 14,
				Font = UIConfig.Font.Default,
				TextXAlignment = Enum.TextXAlignment.Left,
			})
		end
		if nextUpgrade.healthBonus then
			index = index + 1
			bonusElements["Bonus_Health"] = React.createElement("TextLabel", {
				Size = UDim2.new(1, -10, 0, 18),
				Position = UDim2.fromOffset(5, (index - 1) * 20),
				BackgroundTransparency = 1,
				Text = string.format("🛡️ Health: +%d%%", (nextUpgrade.healthBonus - 1) * 100),
				TextColor3 = UIConfig.HUD.AccentGold,
				TextSize = 14,
				Font = UIConfig.Font.Default,
				TextXAlignment = Enum.TextXAlignment.Left,
			})
		end
	end

	return React.createElement(Panel, {
		medieval = true,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = UIConfig.HUD.PanelBackground,
	}, {
		Header = React.createElement("TextLabel", {
			Size = UDim2.new(1, -20, 0, 30),
			Position = UDim2.fromOffset(10, 10),
			BackgroundTransparency = 1,
			Text = "🏰 Building Upgrades",
			TextColor3 = UIConfig.HUD.PanelHeaderColor,
			TextSize = 20,
			Font = UIConfig.Font.Title,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),

		CurrentLevel = React.createElement("TextLabel", {
			Size = UDim2.new(1, -20, 0, 25),
			Position = UDim2.fromOffset(10, 45),
			BackgroundTransparency = 1,
			Text = string.format("Current Level: %d", currentLevel),
			TextColor3 = UIConfig.HUD.PanelTextColor,
			TextSize = 16,
			Font = UIConfig.Font.Default,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),

		-- Show upgrade available or max level
		UpgradeContent = nextUpgrade and React.createElement("Frame", {
			Size = UDim2.new(1, -20, 1, -150),
			Position = UDim2.fromOffset(10, 75),
			BackgroundTransparency = 1,
		}, {
			UpgradeName = React.createElement("TextLabel", {
				Size = UDim2.new(1, 0, 0, 25),
				BackgroundTransparency = 1,
				Text = string.format("⬆️ Upgrade to Level %d", nextUpgrade.level),
				TextColor3 = UIConfig.HUD.PanelHeaderColor,
				TextSize = 18,
				Font = UIConfig.Font.Title,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),

			Description = React.createElement("TextLabel", {
				Size = UDim2.new(1, 0, 0, 40),
				Position = UDim2.fromOffset(0, 30),
				BackgroundTransparency = 1,
				Text = nextUpgrade.description,
				TextColor3 = UIConfig.HUD.PanelTextColor,
				TextSize = 14,
				Font = UIConfig.Font.Default,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextWrapped = true,
			}),

			BonusesLabel = React.createElement("TextLabel", {
				Size = UDim2.new(1, 0, 0, 20),
				Position = UDim2.fromOffset(0, 75),
				BackgroundTransparency = 1,
				Text = "Bonuses:",
				TextColor3 = UIConfig.HUD.PanelHeaderColor,
				TextSize = 16,
				Font = UIConfig.Font.Title,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),

			Bonuses = React.createElement("Frame", {
				Size = UDim2.new(1, 0, 0, 60),
				Position = UDim2.fromOffset(0, 100),
				BackgroundTransparency = 1,
			}, bonusElements),

			CostLabel = React.createElement("TextLabel", {
				Size = UDim2.new(1, 0, 0, 20),
				Position = UDim2.fromOffset(0, 165),
				BackgroundTransparency = 1,
				Text = "Cost:",
				TextColor3 = UIConfig.HUD.PanelHeaderColor,
				TextSize = 16,
				Font = UIConfig.Font.Title,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),

			CostDisplay = React.createElement("Frame", {
				Size = UDim2.new(1, 0, 0, 50),
				Position = UDim2.fromOffset(0, 190),
				BackgroundTransparency = 1,
			}, costElements),
		})
			or React.createElement("TextLabel", {
				Size = UDim2.new(1, -20, 0, 40),
				Position = UDim2.fromOffset(10, 75),
				BackgroundTransparency = 1,
				Text = "✅ Max Level Reached!\n\nThis building is fully upgraded.",
				TextColor3 = UIConfig.HUD.AccentGold,
				TextSize = 16,
				Font = UIConfig.Font.Title,
				TextXAlignment = Enum.TextXAlignment.Center,
				TextYAlignment = Enum.TextYAlignment.Top,
			}),

		UpgradeButton = nextUpgrade and React.createElement(Button, {
			Text = canAfford and "Upgrade Building" or "Insufficient Resources",
			Size = UDim2.new(1, -20, 0, 40),
			Position = UDim2.new(0, 10, 1, -50),
			TextSize = 18,
			OnClick = function()
				if canAfford then
					local ReplicatedStorage = game:GetService("ReplicatedStorage")
					local RemoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")
					if RemoteEvents then
						local GameEvent = RemoteEvents:FindFirstChild("GameEvent")
						if GameEvent then
							GameEvent:FireServer("UpgradeBuilding", {
								buildingId = building.Name,
							})
						end
					end
				end
			end,
		}) or nil,
	})
end

return UpgradePanel
