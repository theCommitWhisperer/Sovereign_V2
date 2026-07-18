--[[
	Worker Point Generator Plugin

	HOW TO USE:
	1. Select a building model in workspace or ReplicatedStorage
	2. Run this script in Command Bar or as a Plugin
	3. Choose which point type to add (or add all)

	This will create invisible parts at the model's center that you can then reposition
]]

local Selection = game:GetService("Selection")

-- Configuration
local POINT_CONFIGURATIONS = {
	-- Production building points (simplified - only 3 points needed!)
	Production = {
		{ Name = "BuildingEntrance", Color = Color3.fromRGB(0, 255, 0) }, -- Green
		{ Name = "ProductionStation", Color = Color3.fromRGB(0, 100, 255) }, -- Blue
		{ Name = "ResourceDropoff", Color = Color3.fromRGB(255, 200, 0) }, -- Yellow (workers deposit AND haulers pick up)
	},

	-- Storage building points
	Storage = {
		{ Name = "BuildingEntrance", Color = Color3.fromRGB(0, 255, 0) }, -- Green
		{ Name = "StorageAreaWood", Color = Color3.fromRGB(139, 69, 19) }, -- Brown
		{ Name = "StorageAreaStone", Color = Color3.fromRGB(128, 128, 128) }, -- Gray
		{ Name = "StorageAreaFood", Color = Color3.fromRGB(255, 200, 100) }, -- Wheat
		{ Name = "StorageAreaIron", Color = Color3.fromRGB(70, 70, 80) }, -- Dark gray
		{ Name = "StorageAreaGold", Color = Color3.fromRGB(255, 215, 0) }, -- Gold
		{ Name = "StorageAreaWeapons", Color = Color3.fromRGB(150, 0, 0) }, -- Dark red
		{ Name = "StorageAreaGeneral", Color = Color3.fromRGB(200, 200, 200) }, -- Light gray
	},
}

-- Point part properties
local POINT_PROPERTIES = {
	Size = Vector3.new(2, 2, 2),
	Transparency = 0.5, -- Semi-transparent in Studio for easy visibility
	CanCollide = false,
	Anchored = true,
	Material = Enum.Material.Neon, -- Makes them glow in Studio
	TopSurface = Enum.SurfaceType.Smooth,
	BottomSurface = Enum.SurfaceType.Smooth,
}

-- Create a single worker point part
local function createWorkerPoint(parent: Model, pointName: string, color: Color3, offsetMultiplier: number)
	-- Check if point already exists
	local existing = parent:FindFirstChild(pointName)
	if existing then
		warn(`Point "{pointName}" already exists in {parent.Name}. Skipping.`)
		return existing
	end

	local point = Instance.new("Part")
	point.Name = pointName

	-- Apply properties
	for property, value in pairs(POINT_PROPERTIES) do
		point[property] = value
	end

	point.Color = color

	-- Position relative to parent's center (spread them out for easy selection)
	local centerPos = parent:GetPivot().Position
	local offset = Vector3.new(
		(offsetMultiplier % 3) * 4 - 4, -- X: -4, 0, 4
		2, -- Y: slightly above ground
		math.floor(offsetMultiplier / 3) * 4 - 4 -- Z: -4, 0, 4
	)
	point.Position = centerPos + offset

	-- Add a BillboardGui for easy identification in Studio
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "PointLabel"
	billboard.Adornee = point
	billboard.Size = UDim2.new(0, 100, 0, 20)
	billboard.StudsOffset = Vector3.new(0, 2, 0)
	billboard.AlwaysOnTop = true

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 0.3
	label.BackgroundColor3 = Color3.new(0, 0, 0)
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Text = pointName
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Parent = billboard

	billboard.Parent = point
	point.Parent = parent

	print(`✓ Created "{pointName}" in {parent.Name}`)
	return point
end

-- Main function: Add production points to a building
local function addProductionPoints(building: Model)
	print(`\n=== Adding Production Points to {building.Name} ===`)

	local points = POINT_CONFIGURATIONS.Production
	for i, pointConfig in ipairs(points) do
		createWorkerPoint(building, pointConfig.Name, pointConfig.Color, i - 1)
	end

	print(`\n✓ Added {#points} production points to {building.Name}`)
	print(`Next step: Reposition the points to their correct locations in your building!`)
end

-- Main function: Add storage points to a building
local function addStoragePoints(building: Model)
	print(`\n=== Adding Storage Points to {building.Name} ===`)

	local points = POINT_CONFIGURATIONS.Storage
	for i, pointConfig in ipairs(points) do
		createWorkerPoint(building, pointConfig.Name, pointConfig.Color, i - 1)
	end

	print(`\n✓ Added {#points} storage points to {building.Name}`)
	print(`Next step: Reposition the points to their correct locations in your building!`)
end

-- Function to finalize points (make them invisible for production)
local function finalizePoints(building: Model)
	print(`\n=== Finalizing Points in {building.Name} ===`)

	local count = 0
	for _, child in ipairs(building:GetChildren()) do
		if child:IsA("Part") and (
			child.Name:match("BuildingEntrance") or
			child.Name:match("Worker") or
			child.Name:match("Production") or
			child.Name:match("Resource") or
			child.Name:match("StorageArea")
		) then
			-- Make invisible
			child.Transparency = 1
			child.Material = Enum.Material.SmoothPlastic

			-- Remove billboard
			local billboard = child:FindFirstChild("PointLabel")
			if billboard then
				billboard:Destroy()
			end

			count = count + 1
		end
	end

	print(`✓ Finalized {count} worker points (made invisible and production-ready)`)
	print(`These points are now ready for your game!`)
end

-- Interactive menu
local function showMenu(building: Model)
	print(`\n╔═══════════════════════════════════════════════════╗`)
	print(`║     Worker Point Generator - {building.Name}`)
	print(`╚═══════════════════════════════════════════════════╝`)
	print(`\nWhat would you like to do?`)
	print(`  1. Add Production Points (for Lumberjack, Farms, Mines, etc.)`)
	print(`  2. Add Storage Points (for Keep, Storehouse, Granary, etc.)`)
	print(`  3. Add Both Production AND Storage Points`)
	print(`  4. Finalize Points (make invisible for production)`)
	print(`  5. Remove All Worker Points`)
	print(`\nEnter your choice (1-5):`)
end

-- Remove all worker points from a building
local function removeWorkerPoints(building: Model)
	print(`\n=== Removing Worker Points from {building.Name} ===`)

	local count = 0
	for _, child in ipairs(building:GetChildren()) do
		if child:IsA("Part") and (
			child.Name:match("BuildingEntrance") or
			child.Name:match("Worker") or
			child.Name:match("Production") or
			child.Name:match("Resource") or
			child.Name:match("StorageArea")
		) then
			child:Destroy()
			count = count + 1
		end
	end

	print(`✓ Removed {count} worker points from {building.Name}`)
end

-- ============================================
-- MAIN EXECUTION
-- ============================================

local function main()
	-- Get selected objects
	local selected = Selection:Get()

	if #selected == 0 then
		warn("⚠️  No objects selected!")
		warn("Please select a building model in workspace and run this script again.")
		return
	end

	-- Process each selected model
	for _, object in ipairs(selected) do
		if not object:IsA("Model") then
			warn(`⚠️  "{object.Name}" is not a Model. Skipping.`)
			continue
		end

		local building = object :: Model
		showMenu(building)

		-- For plugin use, you'd use PluginGui for input
		-- For now, we'll provide functions you can call directly
		print(`\n📝 To use this script, call one of these functions:`)
		print(`   • addProductionPoints(building)`)
		print(`   • addStoragePoints(building)`)
		print(`   • finalizePoints(building)`)
		print(`   • removeWorkerPoints(building)`)
		print(`\nExample for selected building:`)
		print(`   local building = game.Selection:Get()[1]`)
		print(`   addProductionPoints(building)`)
	end
end

-- Run main
main()

-- ============================================
-- QUICK ACCESS FUNCTIONS (paste in command bar)
-- ============================================

--[[

--- ADD PRODUCTION POINTS (ONLY 3 NEEDED!) ---
local building = game.Selection:Get()[1]
if building then
	-- Create points (simplified - only 3 points!)
	local points = {
		{Name = "BuildingEntrance", Color = Color3.fromRGB(0, 255, 0)},
		{Name = "ProductionStation", Color = Color3.fromRGB(0, 100, 255)},
		{Name = "ResourceDropoff", Color = Color3.fromRGB(255, 200, 0)},
	}

	for i, cfg in ipairs(points) do
		local p = Instance.new("Part")
		p.Name = cfg.Name
		p.Size = Vector3.new(2, 2, 2)
		p.Transparency = 0.5
		p.CanCollide = false
		p.Anchored = true
		p.Material = Enum.Material.Neon
		p.Color = cfg.Color
		p.Position = building:GetPivot().Position + Vector3.new((i-1)*4-8, 2, 0)

		local bb = Instance.new("BillboardGui")
		bb.Adornee = p
		bb.Size = UDim2.new(0, 100, 0, 20)
		bb.StudsOffset = Vector3.new(0, 2, 0)
		bb.AlwaysOnTop = true
		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.new(1, 0, 1, 0)
		lbl.BackgroundTransparency = 0.3
		lbl.BackgroundColor3 = Color3.new(0, 0, 0)
		lbl.TextColor3 = Color3.new(1, 1, 1)
		lbl.Text = cfg.Name
		lbl.TextScaled = true
		lbl.Font = Enum.Font.GothamBold
		lbl.Parent = bb
		bb.Parent = p
		p.Parent = building
		print("Created:", cfg.Name)
	end
	print("✓ Production points added!")
end


--- ADD STORAGE POINTS ---
local building = game.Selection:Get()[1]
if building then
	local points = {
		{Name = "BuildingEntrance", Color = Color3.fromRGB(0, 255, 0)},
		{Name = "StorageAreaWood", Color = Color3.fromRGB(139, 69, 19)},
		{Name = "StorageAreaStone", Color = Color3.fromRGB(128, 128, 128)},
		{Name = "StorageAreaFood", Color = Color3.fromRGB(255, 200, 100)},
		{Name = "StorageAreaIron", Color = Color3.fromRGB(70, 70, 80)},
		{Name = "StorageAreaGold", Color = Color3.fromRGB(255, 215, 0)},
		{Name = "StorageAreaWeapons", Color = Color3.fromRGB(150, 0, 0)},
		{Name = "StorageAreaGeneral", Color = Color3.fromRGB(200, 200, 200)},
	}

	for i, cfg in ipairs(points) do
		local p = Instance.new("Part")
		p.Name = cfg.Name
		p.Size = Vector3.new(2, 2, 2)
		p.Transparency = 0.5
		p.CanCollide = false
		p.Anchored = true
		p.Material = Enum.Material.Neon
		p.Color = cfg.Color
		local x = (i-1) % 4
		local z = math.floor((i-1) / 4)
		p.Position = building:GetPivot().Position + Vector3.new(x*4-6, 2, z*4-4)

		local bb = Instance.new("BillboardGui")
		bb.Adornee = p
		bb.Size = UDim2.new(0, 100, 0, 20)
		bb.StudsOffset = Vector3.new(0, 2, 0)
		bb.AlwaysOnTop = true
		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.new(1, 0, 1, 0)
		lbl.BackgroundTransparency = 0.3
		lbl.BackgroundColor3 = Color3.new(0, 0, 0)
		lbl.TextColor3 = Color3.new(1, 1, 1)
		lbl.Text = cfg.Name
		lbl.TextScaled = true
		lbl.Font = Enum.Font.GothamBold
		lbl.Parent = bb
		bb.Parent = p
		p.Parent = building
		print("Created:", cfg.Name)
	end
	print("✓ Storage points added!")
end


--- FINALIZE POINTS (MAKE INVISIBLE) ---
local building = game.Selection:Get()[1]
if building then
	for _, child in ipairs(building:GetChildren()) do
		if child:IsA("Part") and (child.Name:match("Building") or child.Name:match("Worker") or child.Name:match("Storage") or child.Name:match("Resource") or child.Name:match("Production")) then
			child.Transparency = 1
			child.Material = Enum.Material.SmoothPlastic
			local bb = child:FindFirstChild("PointLabel")
			if bb then bb:Destroy() end
		end
	end
	print("✓ Points finalized!")
end


--- REMOVE ALL POINTS ---
local building = game.Selection:Get()[1]
if building then
	for _, child in ipairs(building:GetChildren()) do
		if child:IsA("Part") and (child.Name:match("Building") or child.Name:match("Worker") or child.Name:match("Storage") or child.Name:match("Resource") or child.Name:match("Production")) then
			child:Destroy()
		end
	end
	print("✓ Points removed!")
end

--]]

print("\n✓ Worker Point Generator loaded!")
print("Select a building model and run the script to get started!")

return {
	addProductionPoints = addProductionPoints,
	addStoragePoints = addStoragePoints,
	finalizePoints = finalizePoints,
	removeWorkerPoints = removeWorkerPoints,
}
