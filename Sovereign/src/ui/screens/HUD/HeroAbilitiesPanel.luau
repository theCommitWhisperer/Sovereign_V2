--!strict
-- HeroAbilitiesPanel: Displays King's hero abilities with cooldown indicators

local React = require(game.ReplicatedStorage.Packages.react)
local UIConfig = require(script.Parent.Parent.Parent.UIConfig)
local Panel = require(script.Parent.Parent.Parent.components.Panel)

local HeroAbilitiesPanel = React.Component:extend("HeroAbilitiesPanel")

function HeroAbilitiesPanel:init()
	self:setState({
		abilities = {},
		cooldowns = {},
		currentTime = tick(),
	})

	-- Update cooldowns every frame
	self.updateConnection = game:GetService("RunService").Heartbeat:Connect(function()
		self:setState({
			currentTime = tick(),
		})
	end)
end

function HeroAbilitiesPanel:willUnmount()
	if self.updateConnection then
		self.updateConnection:Disconnect()
	end
end

function HeroAbilitiesPanel:didMount()
	-- Request abilities data from server
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
	local GameEvent = RemoteEvents:WaitForChild("GameEvent")

	GameEvent:FireServer("GetAbilities")

	-- Listen for abilities data
	self.abilitiesConnection = GameEvent.OnClientEvent:Connect(function(action, data)
		if action == "AbilitiesData" then
			self:setState({
				abilities = data.abilities,
				cooldowns = data.cooldowns,
			})
		elseif action == "AbilityUsed" then
			-- Ability was used successfully, refresh cooldowns
			GameEvent:FireServer("GetAbilities")
		elseif action == "AbilityCooldown" then
			-- Ability on cooldown, just refresh
			GameEvent:FireServer("GetAbilities")
		end
	end)
end

function HeroAbilitiesPanel:render()
	local abilities = self.state.abilities or {}
	local cooldowns = self.state.cooldowns or {}
	local currentTime = self.state.currentTime

	-- Convert abilities table to array for rendering
	local abilityArray = {}
	for id, ability in pairs(abilities) do
		table.insert(abilityArray, {
			id = id,
			data = ability,
		})
	end

	-- Sort abilities by ID for consistent order
	table.sort(abilityArray, function(a, b)
		return a.id < b.id
	end)

	local abilityButtons = {}

	for index, abilityEntry in ipairs(abilityArray) do
		local ability = abilityEntry.data
		local abilityId = abilityEntry.id
		local cooldown = cooldowns[abilityId] or 0
		local isOnCooldown = cooldown > 0

		-- Calculate cooldown progress
		local cooldownProgress = 0
		if isOnCooldown then
			cooldownProgress = cooldown / ability.cooldown
		end

		abilityButtons["Ability_" .. abilityId] = React.createElement("TextButton", {
			Size = UDim2.new(0, 80, 0, 80),
			BackgroundColor3 = isOnCooldown and UIConfig.HUD.BuildingButtonUnaffordable
				or UIConfig.HUD.BuildingButtonAffordable,
			BorderSizePixel = 2,
			BorderColor3 = UIConfig.HUD.StrokeColor,
			LayoutOrder = index,
			Text = "",
			AutoButtonColor = not isOnCooldown,
			[React.Event.Activated] = function()
				if not isOnCooldown then
					-- Fire ability use to server
					local ReplicatedStorage = game:GetService("ReplicatedStorage")
					local RemoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")
					if RemoteEvents then
						local GameEvent = RemoteEvents:FindFirstChild("GameEvent")
						if GameEvent then
							GameEvent:FireServer("UseAbility", {
								abilityId = abilityId,
							})
						end
					end
				end
			end,
			[React.Event.MouseEnter] = function(rbx)
				if self.props.tooltip then
					local tooltipText = string.format(
						"<b>%s</b>\n%s\n\nCooldown: %ds\n%s",
						ability.name,
						ability.description,
						ability.cooldown,
						ability.radius and string.format("Radius: %d studs", ability.radius) or ""
					)
					self.props.tooltip.show(tooltipText, rbx)
				end
			end,
			[React.Event.MouseLeave] = function()
				if self.props.tooltip then
					self.props.tooltip.hide()
				end
			end,
		}, {
			-- Ability icon/name
			AbilityName = React.createElement("TextLabel", {
				Size = UDim2.fromScale(1, 0.5),
				Position = UDim2.fromScale(0, 0),
				BackgroundTransparency = 1,
				Text = ability.name,
				TextColor3 = UIConfig.HUD.PanelTextColor,
				TextSize = 14,
				Font = UIConfig.Font.Medieval,
				TextWrapped = true,
				TextYAlignment = Enum.TextYAlignment.Top,
			}),

			-- Cooldown overlay
			CooldownOverlay = isOnCooldown and React.createElement("Frame", {
				Size = UDim2.new(1, 0, cooldownProgress, 0),
				Position = UDim2.fromScale(0, 1 - cooldownProgress),
				BackgroundColor3 = Color3.fromRGB(0, 0, 0),
				BackgroundTransparency = 0.6,
				BorderSizePixel = 0,
				ZIndex = 2,
			}, {
				CooldownText = React.createElement("TextLabel", {
					Size = UDim2.fromScale(1, 1),
					BackgroundTransparency = 1,
					Text = string.format("%.1fs", cooldown),
					TextColor3 = Color3.fromRGB(255, 255, 255),
					TextSize = 20,
					Font = UIConfig.Font.Default,
					TextStrokeTransparency = 0.5,
					ZIndex = 3,
				}),
			}) or nil,

			-- Hotkey hint
			Hotkey = React.createElement("TextLabel", {
				Size = UDim2.new(0, 20, 0, 20),
				Position = UDim2.new(1, -22, 0, 2),
				BackgroundColor3 = Color3.fromRGB(0, 0, 0),
				BackgroundTransparency = 0.5,
				BorderSizePixel = 0,
				Text = tostring(index),
				TextColor3 = Color3.fromRGB(255, 255, 255),
				TextSize = 14,
				Font = UIConfig.Font.Default,
			}),

			UIStroke = React.createElement("UIStroke", {
				Color = UIConfig.HUD.StrokeColor,
				Thickness = 1.5,
			}),
		})
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
			Text = "⚔️ Hero Abilities",
			TextColor3 = UIConfig.HUD.PanelHeaderColor,
			TextSize = 20,
			Font = UIConfig.Font.Title,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),

		AbilityGrid = React.createElement("Frame", {
			Size = UDim2.new(1, -20, 1, -50),
			Position = UDim2.fromOffset(10, 45),
			BackgroundTransparency = 1,
		}, React.assign({
			Layout = React.createElement("UIGridLayout", {
				CellSize = UDim2.fromOffset(80, 80),
				CellPadding = UDim2.fromOffset(10, 10),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		}, abilityButtons)),

		HelpText = React.createElement("TextLabel", {
			Size = UDim2.new(1, -20, 0, 20),
			Position = UDim2.new(0, 10, 1, -25),
			BackgroundTransparency = 1,
			Text = "Click abilities to activate • Numbers 1-5 for hotkeys",
			TextColor3 = UIConfig.HUD.PanelTextColor,
			TextSize = 12,
			Font = UIConfig.Font.Default,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
	})
end

return HeroAbilitiesPanel
