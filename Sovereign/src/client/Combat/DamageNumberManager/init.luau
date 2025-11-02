--!strict
-- DamageNumberManager: Shows floating damage numbers when units take damage

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DebugManager = require(ReplicatedStorage.Shared.DebugManager)
local DamageNumDebug = DebugManager.createChannel("DamageNumbers", false)

local DamageNumberManager = {}

-- Track last health values to detect damage
local lastHealthValues: { [Model]: number } = {}

-- Create a floating damage number
local function createDamageNumber(unit: Model, damage: number)
	if not unit.PrimaryPart then
		return
	end

	local roundedDamage = math.floor(damage + 0.5)
	local isCritical = damage > 50

	-- Create billboard GUI
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "DamageNumber"
	billboard.Size = UDim2.new(3, 0, 1.5, 0)
	billboard.StudsOffset = Vector3.new(math.random(-10, 10) / 10, 4.5, 0)  -- Slight random offset
	billboard.AlwaysOnTop = false  -- Don't show through walls
	billboard.Parent = unit.PrimaryPart

	-- Container for scaling effect
	local container = Instance.new("Frame")
	container.Name = "Container"
	container.Size = UDim2.new(1, 0, 1, 0)
	container.BackgroundTransparency = 1
	container.Parent = billboard

	-- Create text label for damage
	local damageLabel = Instance.new("TextLabel")
	damageLabel.Name = "DamageText"
	damageLabel.Size = UDim2.new(1, 0, 1, 0)
	damageLabel.BackgroundTransparency = 1
	damageLabel.Text = `-{roundedDamage}`
	damageLabel.Font = Enum.Font.GothamBold
	damageLabel.TextSize = isCritical and 28 or 20
	damageLabel.TextColor3 = isCritical and Color3.fromRGB(255, 50, 50) or Color3.fromRGB(255, 100, 100)
	damageLabel.TextStrokeTransparency = 0
	damageLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	damageLabel.TextScaled = false
	damageLabel.Parent = container

	-- Animate with bounce-out effect
	local tweenInfo = TweenInfo.new(
		0.8,  -- Faster duration
		Enum.EasingStyle.Back,  -- Bounce effect
		Enum.EasingDirection.Out
	)

	-- Pop-up scale animation
	container.Size = UDim2.new(0.5, 0, 0.5, 0)
	container.Position = UDim2.new(0.25, 0, 0.25, 0)

	local scaleTween = TweenService:Create(container, tweenInfo, {
		Size = UDim2.new(1, 0, 1, 0),
		Position = UDim2.new(0, 0, 0, 0)
	})

	-- Float upward
	local floatTween = TweenService:Create(billboard, TweenInfo.new(
		1.0,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	), {
		StudsOffset = Vector3.new(billboard.StudsOffset.X, 6, 0)
	})

	-- Fade out
	local fadeTween = TweenService:Create(damageLabel, TweenInfo.new(
		0.5,  -- Start fading halfway
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.In
	), {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	})

	scaleTween:Play()
	floatTween:Play()

	-- Delay fade to let it be visible
	task.delay(0.5, function()
		fadeTween:Play()
	end)

	-- Destroy after animation
	task.delay(1.0, function()
		billboard:Destroy()
	end)

	DamageNumDebug:info(`Showed damage number: {damage} on {unit.Name}`)
end

-- Monitor health changes and create damage numbers
RunService.RenderStepped:Connect(function()
	local unitsFolder = workspace:FindFirstChild("Units")
	if not unitsFolder then
		return
	end

	for _, unit in unitsFolder:GetChildren() do
		if unit:IsA("Model") and unit:GetAttribute("UnitType") then
			local currentHealth = unit:GetAttribute("CurrentHealth")
			local lastHealth = lastHealthValues[unit]

			if currentHealth and lastHealth then
				-- Check if health decreased (damage taken)
				if currentHealth < lastHealth then
					local damage = lastHealth - currentHealth
					createDamageNumber(unit, damage)
				end
			end

			-- Update last health value
			lastHealthValues[unit] = currentHealth or unit:GetAttribute("MaxHealth") or 100
		end
	end

	-- Clean up destroyed units
	for unit, _ in lastHealthValues do
		if not unit or not unit.Parent then
			lastHealthValues[unit] = nil
		end
	end
end)

DamageNumDebug:info("Initialized")

return DamageNumberManager
