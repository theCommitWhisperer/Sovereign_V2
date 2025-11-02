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
	billboard.Size = UDim2.new(3, 0, 0.6, 0)  -- Smaller, more compact
	billboard.StudsOffset = Vector3.new(0, 3.5, 0)  -- Closer to worker
	billboard.AlwaysOnTop = false  -- Don't show through walls
	billboard.Parent = worker.PrimaryPart

	-- Background with better styling
	local background = Instance.new("Frame")
	background.Name = "Background"
	background.Size = UDim2.new(0, 60, 0, 24)  -- Fixed pixel size for consistency
	background.AnchorPoint = Vector2.new(0.5, 0.5)
	background.Position = UDim2.new(0.5, 0, 0.5, 0)
	background.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
	background.BackgroundTransparency = 0.15
	background.BorderSizePixel = 0
	background.Parent = billboard

	-- Rounded corners
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = background

	-- Subtle border/glow
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(80, 80, 90)
	stroke.Transparency = 0.4
	stroke.Thickness = 1
	stroke.Parent = background

	-- Icon label (centered, bigger)
	local iconLabel = Instance.new("TextLabel")
	iconLabel.Name = "Icon"
	iconLabel.Size = UDim2.new(0, 20, 0, 20)
	iconLabel.Position = UDim2.new(0, 4, 0, 2)
	iconLabel.BackgroundTransparency = 1
	iconLabel.Font = Enum.Font.GothamBold
	iconLabel.TextSize = 16
	iconLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	iconLabel.Text = ""
	iconLabel.Parent = background

	-- Text label (amount) - cleaner font
	local textLabel = Instance.new("TextLabel")
	textLabel.Name = "Amount"
	textLabel.Size = UDim2.new(0, 32, 0, 20)
	textLabel.Position = UDim2.new(0, 26, 0, 2)
	textLabel.BackgroundTransparency = 1
	textLabel.Font = Enum.Font.GothamBold
	textLabel.TextSize = 13
	textLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	textLabel.Text = ""
	textLabel.TextXAlignment = Enum.TextXAlignment.Left
	textLabel.Parent = background

	-- Text shadow for readability
	local shadow = Instance.new("TextLabel")
	shadow.Name = "Shadow"
	shadow.Size = textLabel.Size
	shadow.Position = UDim2.new(0, 27, 0, 3)
	shadow.BackgroundTransparency = 1
	shadow.Font = textLabel.Font
	shadow.TextSize = textLabel.TextSize
	shadow.TextColor3 = Color3.fromRGB(0, 0, 0)
	shadow.TextTransparency = 0.5
	shadow.Text = ""
	shadow.TextXAlignment = Enum.TextXAlignment.Left
	shadow.ZIndex = 0
	shadow.Parent = background

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

	if resourcesCarrying <= 0.5 or not resourceType then
		-- Hide indicator if not carrying (with small threshold to avoid flicker)
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

	-- Round to whole number for cleaner display
	local roundedAmount = math.floor(resourcesCarrying + 0.5)

	-- Update icon and text
	local background = billboard:FindFirstChild("Background")
	if not background then return end

	local iconLabel = background:FindFirstChild("Icon")
	local amountLabel = background:FindFirstChild("Amount")
	local shadowLabel = background:FindFirstChild("Shadow")

	if iconLabel then
		iconLabel.Text = resourceInfo.icon
		iconLabel.TextColor3 = resourceInfo.color
	end

	if amountLabel then
		amountLabel.Text = tostring(roundedAmount)
		amountLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	end

	if shadowLabel then
		shadowLabel.Text = tostring(roundedAmount)
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
