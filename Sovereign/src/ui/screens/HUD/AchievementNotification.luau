--!strict
-- AchievementNotification: Toast notification for unlocked achievements

local React = require(game.ReplicatedStorage.Packages.react)
local UIConfig = require(script.Parent.Parent.Parent.UIConfig)

local AchievementNotification = React.Component:extend("AchievementNotification")

function AchievementNotification:init()
	self:setState({
		visible = false,
		slideIn = false,
	})
end

function AchievementNotification:didUpdate(prevProps)
	-- Trigger animation when achievement changes
	if self.props.achievement ~= prevProps.achievement and self.props.achievement then
		-- Start slide-in animation
		self:setState({ visible = true, slideIn = true })

		-- Auto-hide after 5 seconds
		task.delay(5, function()
			self:setState({ slideIn = false })
			task.wait(0.5) -- Wait for slide-out animation
			self:setState({ visible = false })
		end)
	end
end

function AchievementNotification:render()
	if not self.state.visible or not self.props.achievement then
		return nil
	end

	local achievement = self.props.achievement
	local slideIn = self.state.slideIn

	-- Calculate position for slide animation
	local targetPosition = UDim2.new(0.5, -200, 0, 100)
	local hiddenPosition = UDim2.new(0.5, -200, 0, -150)

	-- Resource icon mapping for rewards
	local resourceIcons = {
		Wood = "🌲",
		Stone = "🪨",
		Gold = "💰",
		Iron_Bars = "⚒️",
		Weapons = "⚔️",
		Food = "🍞",
	}

	-- Build reward text
	local rewardText = ""
	if achievement.reward then
		local rewards = {}
		for resource, amount in pairs(achievement.reward) do
			table.insert(rewards, string.format("%s +%d", resourceIcons[resource] or "•", amount))
		end
		rewardText = "Rewards: " .. table.concat(rewards, ", ")
	end

	return React.createElement("Frame", {
		Size = UDim2.fromOffset(400, 120),
		Position = slideIn and targetPosition or hiddenPosition,
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = UIConfig.HUD.PanelBackground,
		BorderSizePixel = 3,
		BorderColor3 = UIConfig.HUD.AccentGold,
		ZIndex = 100,
	}, {
		Gradient = React.createElement("UIGradient", {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(218, 165, 32)),
				ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 215, 0)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(218, 165, 32)),
			}),
			Rotation = 90,
		}),

		GlowEffect = React.createElement("ImageLabel", {
			Size = UDim2.fromScale(1.1, 1.1),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			Image = "rbxasset://textures/ui/GuiImagePlaceholder.png",
			ImageColor3 = UIConfig.HUD.AccentGold,
			ImageTransparency = 0.7,
			ZIndex = 99,
		}),

		Icon = React.createElement("TextLabel", {
			Size = UDim2.fromOffset(60, 60),
			Position = UDim2.fromOffset(10, 10),
			BackgroundColor3 = UIConfig.HUD.DarkWood,
			BorderSizePixel = 2,
			BorderColor3 = UIConfig.HUD.AccentGold,
			Text = "🏆",
			TextSize = 40,
			Font = UIConfig.Font.Default,
		}),

		Content = React.createElement("Frame", {
			Size = UDim2.new(1, -80, 1, -20),
			Position = UDim2.fromOffset(75, 10),
			BackgroundTransparency = 1,
		}, {
			Title = React.createElement("TextLabel", {
				Size = UDim2.new(1, 0, 0, 25),
				BackgroundTransparency = 1,
				Text = "🎉 ACHIEVEMENT UNLOCKED! 🎉",
				TextColor3 = UIConfig.HUD.AccentGold,
				TextSize = 16,
				Font = UIConfig.Font.Title,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),

			AchievementName = React.createElement("TextLabel", {
				Size = UDim2.new(1, 0, 0, 22),
				Position = UDim2.fromOffset(0, 28),
				BackgroundTransparency = 1,
				Text = achievement.achievementName or achievement.name or "Achievement",
				TextColor3 = Color3.fromRGB(255, 255, 255),
				TextSize = 18,
				Font = UIConfig.Font.Title,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextStrokeTransparency = 0.5,
			}),

			Description = React.createElement("TextLabel", {
				Size = UDim2.new(1, 0, 0, 18),
				Position = UDim2.fromOffset(0, 52),
				BackgroundTransparency = 1,
				Text = achievement.description or "",
				TextColor3 = UIConfig.HUD.PanelTextColor,
				TextSize = 12,
				Font = UIConfig.Font.Default,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextWrapped = true,
			}),

			Rewards = rewardText ~= "" and React.createElement("TextLabel", {
				Size = UDim2.new(1, 0, 0, 18),
				Position = UDim2.fromOffset(0, 72),
				BackgroundTransparency = 1,
				Text = rewardText,
				TextColor3 = UIConfig.HUD.AccentGold,
				TextSize = 13,
				Font = UIConfig.Font.Default,
				TextXAlignment = Enum.TextXAlignment.Left,
			}) or nil,
		}),

		CloseButton = React.createElement("TextButton", {
			Size = UDim2.fromOffset(25, 25),
			Position = UDim2.new(1, -30, 0, 5),
			BackgroundColor3 = UIConfig.HUD.DarkWood,
			BorderSizePixel = 1,
			BorderColor3 = UIConfig.HUD.StrokeColor,
			Text = "✕",
			TextColor3 = UIConfig.HUD.PanelTextColor,
			TextSize = 16,
			Font = UIConfig.Font.Default,
			[React.Event.Activated] = function()
				self:setState({ slideIn = false })
				task.wait(0.5)
				self:setState({ visible = false })
			end,
		}),

		UIStroke = React.createElement("UIStroke", {
			Color = UIConfig.HUD.AccentGold,
			Thickness = 2,
		}),

		UICorner = React.createElement("UICorner", {
			CornerRadius = UDim.new(0, 8),
		}),
	})
end

return AchievementNotification
