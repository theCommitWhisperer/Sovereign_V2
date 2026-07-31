--!strict
-- HeroFightHUD: Center-bottom fighting HUD for Fight / Hero POV mode.
-- Features a clean Lord Health Bar and camera toggle hint (Press B for 1st/3rd person).
-- Isolates UIListLayout inside ContentContainer to prevent MedievalCorners bracket stacking.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.react)

local Theme = require(script.Parent.Parent.Theme)
local HUDStore = require(script.Parent.Parent.state.HUDStore)
local MedievalCorners = require(script.Parent.Parent.components.MedievalCorners)

-- Keybindings manager lookup for dynamic hotkey names
local KeybindingsManager: any = nil
pcall(function()
	local player = Players.LocalPlayer
	if player then
		local cameraFolder = player.PlayerScripts:FindFirstChild("Camera")
		if cameraFolder and cameraFolder:FindFirstChild("KeybindingsManager") then
			KeybindingsManager = require(cameraFolder:FindFirstChild("KeybindingsManager") :: any)
		end
	end
end)

local function getKeyName(action: string, fallback: string): string
	if KeybindingsManager and KeybindingsManager.GetKeybinding then
		local kc = KeybindingsManager.GetKeybinding(action)
		if kc then
			return KeybindingsManager.GetKeyCodeName(kc)
		end
	end
	return fallback
end

local function HeroFightHUD()
	local kingHealth = HUDStore.useHUDState(function(s)
		return s.kingHealth
	end)
	local kingMaxHealth = HUDStore.useHUDState(function(s)
		return s.kingMaxHealth
	end)

	local cycleKey = getKeyName("ToggleCameraMode", "V")
	local heroCamKey = getKeyName("HeroFirstPerson", "B")

	local health = kingHealth or 0
	local maxHealth = math.max(kingMaxHealth or 1, 1)
	local healthFraction = math.clamp(health / maxHealth, 0, 1)
	local healthColor = if healthFraction > 0.5
		then Theme.Color.Success
		elseif healthFraction > 0.25 then Theme.Color.Warning
		else Theme.Color.Danger

	return React.createElement("Frame", {
		Name = "HeroFightHUD",
		Size = UDim2.fromOffset(460, 42),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -20),
		BackgroundColor3 = Theme.Color.Surface,
		BackgroundTransparency = 0.05,
		ZIndex = 40,
	}, {
		Corner = React.createElement("UICorner", { CornerRadius = Theme.corner() }),
		Stroke = React.createElement("UIStroke", Theme.celticStrokeProps()),

		-- MedievalCorners anchored to 4 true corners of the outer frame
		Corners = React.createElement(MedievalCorners, { size = 14, color = Theme.Color.Accent, thickness = 2 }),

		-- ContentContainer isolates UIListLayout from MedievalCorners
		ContentContainer = React.createElement("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = 41,
		}, {
			Padding = React.createElement("UIPadding", {
				PaddingTop = UDim.new(0, 7),
				PaddingBottom = UDim.new(0, 7),
				PaddingLeft = UDim.new(0, 12),
				PaddingRight = UDim.new(0, 12),
			}),
			Layout = React.createElement("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 8),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),

			-- Crown Icon
			CrownIcon = React.createElement("TextLabel", {
				Size = UDim2.fromOffset(24, 28),
				BackgroundTransparency = 1,
				Text = "👑",
				TextSize = 16,
				FontFace = Theme.FontFace.Body,
				LayoutOrder = 1,
			}),

			-- Lord Health Bar Fill Container
			HealthBarContainer = React.createElement("Frame", {
				Size = UDim2.new(0, 180, 0, 14),
				BackgroundColor3 = Theme.Color.SurfaceRaised,
				BorderSizePixel = 0,
				LayoutOrder = 2,
			}, {
				Corner = React.createElement("UICorner", { CornerRadius = Theme.corner(Theme.Metrics.RadiusSmall) }),
				Fill = React.createElement("Frame", {
					Size = UDim2.fromScale(healthFraction, 1),
					BackgroundColor3 = healthColor,
					BorderSizePixel = 0,
				}, {
					Corner = React.createElement("UICorner", { CornerRadius = Theme.corner(Theme.Metrics.RadiusSmall) }),
				}),
			}),

			-- Health Text Numbers
			HealthText = React.createElement("TextLabel", {
				Size = UDim2.fromOffset(56, 28),
				BackgroundTransparency = 1,
				Text = string.format("%d/%d", math.floor(health), math.floor(maxHealth)),
				TextSize = 12,
				FontFace = Theme.FontFace.Number,
				TextColor3 = Theme.Color.TextPrimary,
				TextXAlignment = Enum.TextXAlignment.Left,
				LayoutOrder = 3,
			}),

			-- Divider Line
			Divider = React.createElement("Frame", {
				Size = UDim2.new(0, 1, 0, 18),
				BackgroundColor3 = Theme.Color.Border,
				BorderSizePixel = 0,
				LayoutOrder = 4,
			}),

			-- Camera & Mode Hint Text
			CameraHintText = React.createElement("TextLabel", {
				Size = UDim2.new(1, -290, 1, 0),
				BackgroundTransparency = 1,
				Text = string.format("[%s] 1st/3rd POV · [%s] Modes", heroCamKey, cycleKey),
				FontFace = Theme.FontFace.Display,
				TextSize = 11,
				TextColor3 = Theme.Color.Accent,
				TextXAlignment = Enum.TextXAlignment.Center,
				TextTruncate = Enum.TextTruncate.AtEnd,
				LayoutOrder = 5,
			}),
		}),
	})
end

return HeroFightHUD
