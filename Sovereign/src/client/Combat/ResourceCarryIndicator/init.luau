--!strict
-- ResourceCarryIndicator: Shows visual indicators above workers when they're carrying resources

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DebugManager = require(ReplicatedStorage.Shared.DebugManager)
local ResourceIndicatorDebug = DebugManager.createChannel("ResourceIndicator", false)

local ResourceCarryIndicator = {}

local carryIndicators: { [Model]: BillboardGui } = {}

-- Resource icons/colors
local RESOURCE_INFO = {
	Wood = {
		icon = "🪵",
		color = Color3.fromRGB(139, 69, 19),
		displayName = "Wood"
	},
	Stone = {
		icon = "🪨",
		color = Color3.fromRGB(128, 128, 128),
		displayName = "Stone"
	},
	Food = {
		icon = "🌾",
		color = Color3.fromRGB(255, 215, 0),
		displayName = "Food"
	},
	Iron = {
		icon = "⛏️",
		color = Color3.fromRGB(192, 192, 192),
		displayName = "Iron"
	},
	Gold = {
		icon = "💰",
		color = Color3.fromRGB(255, 215, 0),
		displayName = "Gold"
	},
}

-- Create a carry indicator for a worker
local function createCarryIndicator(worker: Model): BillboardGui?
	if not worker.PrimaryPart then
		return nil
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "ResourceCarryIndicator"
	billboard.Size = UDim2.new(5, 0, 1, 0)
	billboard.StudsOffset = Vector3.new(0, 4.5, 0)  -- Above the worker
	billboard.AlwaysOnTop = true
	billboard.Parent = worker.PrimaryPart

	-- Background
	local background = Instance.new("Frame")
	background.Name = "Background"
	background.Size = UDim2.new(1, 0, 1, 0)
	background.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	background.BackgroundTransparency = 0.3
	background.BorderSizePixel = 0
	background.Parent = billboard

	-- Corner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = background

	-- Icon label
	local iconLabel = Instance.new("TextLabel")
	iconLabel.Name = "Icon"
	iconLabel.Size = UDim2.new(0.4, 0, 1, 0)
	iconLabel.Position = UDim2.new(0, 0, 0, 0)
	iconLabel.BackgroundTransparency = 1
	iconLabel.Font = Enum.Font.GothamBold
	iconLabel.TextSize = 18
	iconLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	iconLabel.Text = ""
	iconLabel.Parent = background

	-- Text label (amount)
	local textLabel = Instance.new("TextLabel")
	textLabel.Name = "Amount"
	textLabel.Size = UDim2.new(0.6, 0, 1, 0)
	textLabel.Position = UDim2.new(0.4, 0, 0, 0)
	textLabel.BackgroundTransparency = 1
	textLabel.Font = Enum.Font.GothamBold
	textLabel.TextSize = 14
	textLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	textLabel.Text = ""
	textLabel.TextXAlignment = Enum.TextXAlignment.Left
	textLabel.Parent = background

	return billboard
end

-- Update a carry indicator
local function updateCarryIndicator(worker: Model, billboard: BillboardGui)
	if not worker or not worker.Parent then
		if billboard then
			billboard:Destroy()
		end
		return
	end

	-- Check if worker is carrying resources
	local resourcesCarrying = worker:GetAttribute("ResourcesCarrying") or 0
	local resourceType = worker:GetAttribute("ResourceType")

	if resourcesCarrying <= 0 or not resourceType then
		-- Hide indicator if not carrying
		billboard.Enabled = false
		return
	end

	-- Show indicator
	billboard.Enabled = true

	-- Get resource info
	local resourceInfo = RESOURCE_INFO[resourceType] or {
		icon = "📦",
		color = Color3.fromRGB(200, 200, 200),
		displayName = resourceType
	}

	-- Update icon and text
	local iconLabel = billboard:FindFirstChild("Background") and billboard.Background:FindFirstChild("Icon")
	local amountLabel = billboard:FindFirstChild("Background") and billboard.Background:FindFirstChild("Amount")

	if iconLabel then
		iconLabel.Text = resourceInfo.icon
		iconLabel.TextColor3 = resourceInfo.color
	end

	if amountLabel then
		amountLabel.Text = `{resourcesCarrying}`
		amountLabel.TextColor3 = resourceInfo.color
	end
end

-- Update all carry indicators
RunService.RenderStepped:Connect(function()
	local unitsFolder = workspace:FindFirstChild("Units")
	if not unitsFolder then
		return
	end

	-- Create indicators for new workers
	for _, unit in unitsFolder:GetChildren() do
		if unit:IsA("Model") and unit.PrimaryPart then
			-- Check if it's a worker (has ResourcesCarrying attribute)
			local resourcesCarrying = unit:GetAttribute("ResourcesCarrying")
			if resourcesCarrying ~= nil then
				-- It's a worker
				if not carryIndicators[unit] then
					local billboard = createCarryIndicator(unit)
					if billboard then
						carryIndicators[unit] = billboard
						ResourceIndicatorDebug:info(`Created carry indicator for {unit.Name}`)
					end
				end
			end
		end
	end

	-- Update existing indicators
	for worker, billboard in carryIndicators do
		if worker and worker.Parent then
			updateCarryIndicator(worker, billboard)
		else
			-- Worker was destroyed
			if billboard then
				billboard:Destroy()
			end
			carryIndicators[worker] = nil
		end
	end
end)

ResourceIndicatorDebug:info("ResourceCarryIndicator initialized")

return ResourceCarryIndicator
