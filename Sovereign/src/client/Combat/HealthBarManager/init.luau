--!strict
-- HealthBarManager: Creates and updates health bars above units

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer

local HealthBarManager = {}

local healthBars: { [Model]: BillboardGui } = {}

-- Create a health bar for a unit
local function createHealthBar(unit: Model): BillboardGui?
	if not unit.PrimaryPart then
		return nil
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "HealthBar"
	billboard.Size = UDim2.new(4, 0, 0.5, 0)
	billboard.StudsOffset = Vector3.new(0, 3, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = unit.PrimaryPart

	-- Background
	local background = Instance.new("Frame")
	background.Name = "Background"
	background.Size = UDim2.new(1, 0, 1, 0)
	background.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	background.BorderSizePixel = 1
	background.BorderColor3 = Color3.fromRGB(0, 0, 0)
	background.Parent = billboard

	-- Health bar fill
	local healthFill = Instance.new("Frame")
	healthFill.Name = "HealthFill"
	healthFill.Size = UDim2.new(1, 0, 1, 0)
	healthFill.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
	healthFill.BorderSizePixel = 0
	healthFill.Parent = background

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

	local currentHealth = unit:GetAttribute("CurrentHealth") or 100
	local maxHealth = unit:GetAttribute("MaxHealth") or 100
	local healthPercent = currentHealth / maxHealth

	local healthFill = billboard:FindFirstChild("Background") and billboard.Background:FindFirstChild("HealthFill")
	if healthFill then
		healthFill.Size = UDim2.new(healthPercent, 0, 1, 0)

		-- Color based on health
		if healthPercent > 0.6 then
			healthFill.BackgroundColor3 = Color3.fromRGB(0, 255, 0) -- Green
		elseif healthPercent > 0.3 then
			healthFill.BackgroundColor3 = Color3.fromRGB(255, 255, 0) -- Yellow
		else
			healthFill.BackgroundColor3 = Color3.fromRGB(255, 0, 0) -- Red
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

print("[HealthBarManager] Initialized")

return HealthBarManager
