--[[
	Update WallPieceDatabase From Models Script

	HOW TO USE:
	1. Copy this script to ServerScriptService in Roblox Studio
	2. Run the game
	3. Check the Output window for results
	4. Copy the generated code into WallPieceDatabase.luau

	This script will:
	- Find all wall models in ReplicatedStorage/Assets/Buildings/
	- Measure their bounding boxes
	- Generate the PIECES table code
	- Generate the BITMASK_LOOKUP table code (using available models)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

print("\n" .. string.rep("=", 80))
print("WALL MODEL SCANNER - AUTO-GENERATE DATABASE")
print(string.rep("=", 80) .. "\n")

-- Get Buildings folder
local assets = ReplicatedStorage:FindFirstChild("Assets")
if not assets then
	error("❌ Assets folder not found in ReplicatedStorage!")
end

local buildings = assets:FindFirstChild("Buildings")
if not buildings then
	error("❌ Buildings folder not found in ReplicatedStorage/Assets!")
end

print(string.format("✓ Found Buildings folder: %s\n", buildings:GetFullName()))

-- List of wall model names to look for
local wallModelNames = {
	"Straight_Stone_Wall",
	"Short_Straight_Stone_Wall",
	"Ladder_Stone_Wall",
	"Small_Tower_Stone_Wall",
	"Large_Tower_Stone_Wall",
	"Large_Keep_Stone",
	"Gatehouse_Stone_Wall",
}

-- Scan for models and collect data
local foundModels = {}
local modelData = {}

print("Scanning for wall models...\n")

for _, modelName in wallModelNames do
	local model = buildings:FindFirstChild(modelName)

	if model and model:IsA("Model") then
		print(string.format("✓ FOUND: %s", modelName))

		-- Get bounding box
		local cf, size = model:GetBoundingBox()

		-- Determine category based on name
		local category = "straight"
		local connectionPoints = 2

		if string.find(modelName:lower(), "tower") or string.find(modelName:lower(), "keep") then
			category = "tower"
			connectionPoints = 4
		elseif string.find(modelName:lower(), "gate") then
			category = "gate"
			connectionPoints = 2
		elseif string.find(modelName:lower(), "ladder") then
			category = "ladder"
			connectionPoints = 2
		end

		-- Store data
		table.insert(foundModels, modelName)
		modelData[modelName] = {
			name = modelName,
			size = size,
			width = math.floor(size.X + 0.5),
			height = math.floor(size.Y + 0.5),
			depth = math.floor(size.Z + 0.5),
			category = category,
			connectionPoints = connectionPoints,
			pivotPos = model:GetPivot().Position,
		}

		print(string.format("  Size: %.1f x %.1f x %.1f (W x H x D)", size.X, size.Y, size.Z))
		print(string.format("  Rounded: %d x %d x %d studs", modelData[modelName].width, modelData[modelName].height, modelData[modelName].depth))
		print(string.format("  Category: %s (%d connection points)", category, connectionPoints))
		print()
	else
		print(string.format("❌ MISSING: %s", modelName))
	end
end

print(string.rep("-", 80))
print(string.format("Found %d out of %d wall models\n", #foundModels, #wallModelNames))
print(string.rep("=", 80))

-- Generate PIECES table code
print("\nGENERATED CODE FOR WallPieceDatabase.luau:")
print(string.rep("=", 80))
print("\n-- STEP 1: Copy this into WallPieceDatabase.PIECES = { ... }\n")

for i, modelName in foundModels do
	local data = modelData[modelName]

	print(string.format('\t["%s"] = {', modelName))
	print(string.format('\t\tassetName = "%s",', modelName))
	print(string.format('\t\twidth = %d,', data.width))
	print(string.format('\t\theight = %d,', data.height))
	print(string.format('\t\tdepth = %d,', data.depth))
	print(string.format('\t\tconnectionPoints = %d,', data.connectionPoints))
	print(string.format('\t\tcategory = "%s",', data.category))
	print('\t},')
	print()
end

-- Determine which models to use for auto-tiling
local straightWall = nil
local towerWall = nil
local largeTowerWall = nil

-- Find best straight wall (prefer Straight_Stone_Wall)
for _, name in {"Straight_Stone_Wall", "Ladder_Stone_Wall", "Short_Straight_Stone_Wall"} do
	if modelData[name] then
		straightWall = name
		break
	end
end

-- Find best small tower (prefer Small_Tower_Stone_Wall)
for _, name in {"Small_Tower_Stone_Wall", "Large_Tower_Stone_Wall"} do
	if modelData[name] then
		towerWall = name
		break
	end
end

-- Find large tower
for _, name in {"Large_Tower_Stone_Wall", "Large_Keep_Stone"} do
	if modelData[name] then
		largeTowerWall = name
		break
	end
end

-- Fallback to straight wall if no tower found
if not towerWall then
	towerWall = straightWall
end
if not largeTowerWall then
	largeTowerWall = towerWall
end

print(string.rep("-", 80))
print("\n-- STEP 2: Copy this into WallPieceDatabase.BITMASK_LOOKUP = { ... }\n")

print(string.format("-- Auto-tiling configuration (using available models)"))
print(string.format("-- Straight walls: %s", straightWall or "NONE"))
print(string.format("-- Corners/T-junctions: %s", towerWall or "NONE"))
print(string.format("-- Cross junctions: %s", largeTowerWall or "NONE"))
print()

if straightWall then
	print('\t-- No neighbors = isolated straight wall')
	print(string.format('\t[0] = { pieceType = "%s", rotation = 0 },', straightWall))
	print()

	print('\t-- One neighbor')
	print(string.format('\t[1] = { pieceType = "%s", rotation = 0 }, -- North', straightWall))
	print(string.format('\t[2] = { pieceType = "%s", rotation = 90 }, -- East', straightWall))
	print(string.format('\t[4] = { pieceType = "%s", rotation = 0 }, -- South', straightWall))
	print(string.format('\t[8] = { pieceType = "%s", rotation = 90 }, -- West', straightWall))
	print()

	print('\t-- Two neighbors - straight line or corner')
	print(string.format('\t[5] = { pieceType = "%s", rotation = 0 }, -- North + South (vertical line)', straightWall))
	print(string.format('\t[10] = { pieceType = "%s", rotation = 90 }, -- East + West (horizontal line)', straightWall))

	if towerWall then
		print(string.format('\t[3] = { pieceType = "%s", rotation = 0 }, -- North + East (corner)', towerWall))
		print(string.format('\t[6] = { pieceType = "%s", rotation = 90 }, -- East + South (corner)', towerWall))
		print(string.format('\t[12] = { pieceType = "%s", rotation = 180 }, -- South + West (corner)', towerWall))
		print(string.format('\t[9] = { pieceType = "%s", rotation = 270 }, -- West + North (corner)', towerWall))
		print()

		print('\t-- Three neighbors - T-junction (use tower)')
		print(string.format('\t[7] = { pieceType = "%s", rotation = 0 }, -- N + E + S', towerWall))
		print(string.format('\t[14] = { pieceType = "%s", rotation = 90 }, -- E + S + W', towerWall))
		print(string.format('\t[13] = { pieceType = "%s", rotation = 180 }, -- S + W + N', towerWall))
		print(string.format('\t[11] = { pieceType = "%s", rotation = 270 }, -- W + N + E', towerWall))
		print()
	end

	if largeTowerWall then
		print('\t-- Four neighbors - cross junction (use large tower)')
		print(string.format('\t[15] = { pieceType = "%s", rotation = 0 },', largeTowerWall))
	end
else
	print("❌ ERROR: No straight wall found! Cannot generate bitmask lookup.")
end

print()
print(string.rep("=", 80))
print("\nINSTRUCTIONS:")
print("1. Open src/shared/WallPieceDatabase.luau")
print("2. Replace the PIECES table with STEP 1 code above")
print("3. Replace the BITMASK_LOOKUP table with STEP 2 code above")
print("4. Save the file")
print("5. Restart your game")
print()
print("✓ Done! Your database will now match your actual models.")
print(string.rep("=", 80) .. "\n")

-- Also print a summary table
print("\nSUMMARY TABLE:")
print(string.rep("-", 80))
print(string.format("%-30s %-15s %-15s %s", "Model Name", "Size (WxHxD)", "Category", "Status"))
print(string.rep("-", 80))

for _, modelName in wallModelNames do
	local data = modelData[modelName]
	if data then
		print(string.format("%-30s %-15s %-15s %s",
			modelName,
			string.format("%dx%dx%d", data.width, data.height, data.depth),
			data.category,
			"✓ FOUND"
		))
	else
		print(string.format("%-30s %-15s %-15s %s",
			modelName,
			"N/A",
			"N/A",
			"❌ MISSING"
		))
	end
end

print(string.rep("-", 80) .. "\n")
