--!strict
-- HealthBarManager: Creates and updates health bars above units

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer

-- Remote function for checking visibility
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local CheckVisibility = RemoteEvents:WaitForChild("CheckVisibility")

local DebugManager = require(ReplicatedStorage.Shared.DebugManager)
local HealthBarDebug = DebugManager.createChannel("HealthBar", false) -- Corrected to be off by default

local HealthBarManager = {}

local healthBars: { [Model]: BillboardGui } = {}

-- Create a health bar for a unit
local function createHealthBar(unit: Model): BillboardGui?
	if not unit.PrimaryPart then
		return nil
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "HealthBar"
	billboard.Size = UDim2.new(3, 0, 0.4, 0)  -- Smaller, more compact
	billboard.StudsOffset = Vector3.new(0, 4, 0)  -- Higher to avoid clutter
	billboard.AlwaysOnTop = false  -- Don't show through walls
	billboard.Parent = unit.PrimaryPart

	-- Container frame for proper sizing
	local container = Instance.new("Frame")
	container.Name = "Container"
	container.Size = UDim2.new(0, 80, 0, 10)  -- Slightly bigger: 80x10
	container.AnchorPoint = Vector2.new(0.5, 0.5)
	container.Position = UDim2.new(0.5, 0, 0.5, 0)
	container.BackgroundTransparency = 1
	container.Parent = billboard

	-- Background (dark with softer styling)
	local background = Instance.new("Frame")
	background.Name = "Background"
	background.Size = UDim2.new(1, 0, 1, 0)
	background.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
	background.BackgroundTransparency = 0.1
	background.BorderSizePixel = 0
	background.Parent = container

	-- More rounded corners for softer look
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)  -- Fully rounded (pill shape)
	corner.Parent = background

	-- Outer glow effect
	local outerGlow = Instance.new("UIStroke")
	outerGlow.Color = Color3.fromRGB(0, 0, 0)
	outerGlow.Transparency = 0.6
	outerGlow.Thickness = 2
	outerGlow.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	outerGlow.Parent = background

	-- Inner shadow/inset effect
	local innerFrame = Instance.new("Frame")
	innerFrame.Name = "InnerFrame"
	innerFrame.Size = UDim2.new(1, -2, 1, -2)
	innerFrame.Position = UDim2.new(0, 1, 0, 1)
	innerFrame.BackgroundColor3 = Color3.fromRGB(10, 10, 15)
	innerFrame.BackgroundTransparency = 0.3
	innerFrame.BorderSizePixel = 0
	innerFrame.ZIndex = 1
	innerFrame.Parent = background

	local innerCorner = Instance.new("UICorner")
	innerCorner.CornerRadius = UDim.new(1, 0)
	innerCorner.Parent = innerFrame

	-- Health bar fill
	local healthFill = Instance.new("Frame")
	healthFill.Name = "HealthFill"
	healthFill.Size = UDim2.new(1, 0, 1, 0)
	healthFill.BackgroundColor3 = Color3.fromRGB(76, 175, 80)  -- Material green
	healthFill.BorderSizePixel = 0
	healthFill.ZIndex = 3
	healthFill.Parent = innerFrame

	-- Fully rounded corners for fill
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)  -- Pill shape
	fillCorner.Parent = healthFill

	-- Glossy gradient for depth
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(150, 150, 150))
	})
	gradient.Rotation = 90
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.7),   -- Top highlight
		NumberSequenceKeypoint.new(0.5, 1),   -- Middle transparent
		NumberSequenceKeypoint.new(1, 0.8)    -- Bottom shadow
	})
	gradient.Parent = healthFill

	-- Inner glow for health bar
	local healthGlow = Instance.new("UIStroke")
	healthGlow.Name = "HealthGlow"
	healthGlow.Color = Color3.fromRGB(255, 255, 255)
	healthGlow.Transparency = 0.7
	healthGlow.Thickness = 1
	healthGlow.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	healthGlow.Parent = healthFill

	return billboard
end

-- Update a health bar
local function updateHealthBar(unit: Model, billboard: BillboardGui)
	if not unit or not unit.Parent then
		if billboard then
			billboard:Destroy()
		end
		return
	end

	-- Check if unit is visible (fog of war)
	local isVisible = CheckVisibility:InvokeServer("Unit", unit)
	local owner = unit:GetAttribute("Owner")

	-- Always show health bars for own units, only show enemy bars if visible
	local shouldShow = (owner == player.UserId) or isVisible

	if not shouldShow then
		billboard.Enabled = false
		return
	end

	local currentHealth = unit:GetAttribute("CurrentHealth") or 100
	local maxHealth = unit:GetAttribute("MaxHealth") or 100
	local healthPercent = math.clamp(currentHealth / maxHealth, 0, 1)

	-- Find the container and health fill (now nested in InnerFrame)
	local container = billboard:FindFirstChild("Container")
	if not container then return end

	local background = container:FindFirstChild("Background")
	if not background then return end

	local innerFrame = background:FindFirstChild("InnerFrame")
	if not innerFrame then return end

	local healthFill = innerFrame:FindFirstChild("HealthFill")
	if healthFill then
		healthFill.Size = UDim2.new(healthPercent, 0, 1, 0)

		-- Smooth color transition based on health
		local healthColor
		local glowColor

		if healthPercent > 0.7 then
			-- Healthy: Material Green
			healthColor = Color3.fromRGB(76, 175, 80)
			glowColor = Color3.fromRGB(139, 255, 144)
		elseif healthPercent > 0.4 then
			-- Moderate: Orange/Yellow blend
			local t = (healthPercent - 0.4) / 0.3  -- 0 to 1 from 40% to 70%
			healthColor = Color3.fromRGB(
				math.floor(255 - (179 * t)),  -- 255 to 76
				math.floor(152 + (23 * t)),   -- 152 to 175
				math.floor(0 + (80 * t))      -- 0 to 80
			)
			glowColor = Color3.fromRGB(255, 200, 100)
		else
			-- Critical: Red
			healthColor = Color3.fromRGB(244, 67, 54)
			glowColor = Color3.fromRGB(255, 120, 120)
		end

		healthFill.BackgroundColor3 = healthColor

		-- Update glow color to match health state
		local healthGlow = healthFill:FindFirstChild("HealthGlow")
		if healthGlow then
			healthGlow.Color = glowColor
		end
	end

	-- Hide if at full health
	billboard.Enabled = healthPercent < 1.0
end

-- Update all health bars
RunService.RenderStepped:Connect(function()
	local unitsFolder = workspace:FindFirstChild("Units")
	if not unitsFolder then
		return
	end

	-- Create health bars for new units
	for _, unit in unitsFolder:GetChildren() do
		if unit:IsA("Model") and unit:GetAttribute("UnitType") then
			if not healthBars[unit] then
				local billboard = createHealthBar(unit)
				if billboard then
					healthBars[unit] = billboard
				end
			end
		end
	end

	-- Update existing health bars
	for unit, billboard in healthBars do
		if unit and unit.Parent then
			updateHealthBar(unit, billboard)
		else
			-- Unit was destroyed
			if billboard then
				billboard:Destroy()
			end
			healthBars[unit] = nil
		end
	end
end)

HealthBarDebug:info("Initialized")

return HealthBarManager
