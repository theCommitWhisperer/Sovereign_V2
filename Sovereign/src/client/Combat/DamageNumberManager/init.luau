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

	-- Create billboard GUI
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "DamageNumber"
	billboard.Size = UDim2.new(4, 0, 2, 0)
	billboard.StudsOffset = Vector3.new(0, 4, 0)  -- Float above health bar
	billboard.AlwaysOnTop = true
	billboard.Parent = unit.PrimaryPart

	-- Create text label for damage
	local damageLabel = Instance.new("TextLabel")
	damageLabel.Name = "DamageText"
	damageLabel.Size = UDim2.new(1, 0, 1, 0)
	damageLabel.BackgroundTransparency = 1
	damageLabel.Text = `-${math.floor(damage)}`
	damageLabel.Font = Enum.Font.GothamBold
	damageLabel.TextSize = 24
	damageLabel.TextColor3 = Color3.fromRGB(255, 80, 80)  -- Red
	damageLabel.TextStrokeTransparency = 0.5
	damageLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	damageLabel.TextScaled = false
	damageLabel.Parent = billboard

	-- Bigger text for critical damage (>50)
	if damage > 50 then
		damageLabel.TextSize = 32
		damageLabel.TextColor3 = Color3.fromRGB(255, 0, 0)  -- Brighter red
	end

	-- Animate upward and fade out
	local tweenInfo = TweenInfo.new(
		1.2,  -- Duration
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	)

	local offsetTween = TweenService:Create(billboard, tweenInfo, {
		StudsOffset = Vector3.new(math.random(-1, 1), 7, 0)  -- Float upward with slight randomness
	})

	local fadeTween = TweenService:Create(damageLabel, tweenInfo, {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	})

	offsetTween:Play()
	fadeTween:Play()

	-- Destroy after animation
	task.delay(1.2, function()
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
