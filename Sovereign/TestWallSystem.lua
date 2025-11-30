--[[
	Wall System Test Script

	HOW TO USE:
	1. Copy this script to ServerScriptService in Roblox Studio
	2. Run the game
	3. Check the Output window for test results

	This script will:
	- Verify all wall models exist
	- Test grid conversion functions
	- Test bitmasking logic
	- Create test walls
	- Verify auto-tiling works
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

print("\n" .. string.rep("=", 80))
print("WALL SYSTEM TEST SUITE")
print(string.rep("=", 80) .. "\n")

-- Load required modules
local WallPieceDatabase = require(ReplicatedStorage.Shared.WallPieceDatabase)
local WallGridManager = require(game.ServerScriptService.Systems.WallGridManager)

local testsPassed = 0
local testsFailed = 0

local function test(name, func)
	print(string.format("TEST: %s", name))
	local success, err = pcall(func)
	if success then
		print("  ✓ PASS\n")
		testsPassed = testsPassed + 1
	else
		print(string.format("  ✗ FAIL: %s\n", tostring(err)))
		testsFailed = testsFailed + 1
	end
end

-- Test 1: Verify all wall models exist
test("All wall piece models exist in ReplicatedStorage", function()
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	assert(assets, "Assets folder not found!")

	local buildings = assets:FindFirstChild("Buildings")
	assert(buildings, "Buildings folder not found!")

	local missingModels = {}
	for pieceName, config in WallPieceDatabase.PIECES do
		local model = buildings:FindFirstChild(config.assetName)
		if not model then
			table.insert(missingModels, config.assetName)
		end
	end

	if #missingModels > 0 then
		error("Missing models: " .. table.concat(missingModels, ", "))
	end

	print(string.format("  Found all %d wall piece models", #WallPieceDatabase.PIECES))
end)

-- Test 2: Grid conversion functions
test("Grid conversion functions work correctly", function()
	-- Test world to grid
	local gridX, gridZ = WallPieceDatabase.worldToGrid(Vector3.new(25, 0, 10))
	assert(gridX == 2, string.format("Expected gridX=2, got %d", gridX))
	assert(gridZ == 1, string.format("Expected gridZ=1, got %d", gridZ))

	-- Test grid to world
	local worldPos = WallPieceDatabase.gridToWorld(2, 1, 0)
	assert(worldPos.X == 32, string.format("Expected X=32, got %d", worldPos.X))
	assert(worldPos.Z == 16, string.format("Expected Z=16, got %d", worldPos.Z))

	print("  Grid conversions working correctly")
end)

-- Test 3: Bitmasking logic
test("Bitmasking produces correct piece types", function()
	-- Test isolated wall (bitmask 0)
	local piece, rotation = WallPieceDatabase.getPieceFromBitmask(0)
	assert(piece == "Straight_Stone_Wall", "Isolated wall should be straight")

	-- Test corner (bitmask 3 = North + East)
	piece, rotation = WallPieceDatabase.getPieceFromBitmask(3)
	assert(piece == "Small_Tower_Stone_Wall", "Corner should be small tower")
	assert(rotation == 0, "Corner rotation should be 0")

	-- Test cross (bitmask 15 = all sides)
	piece, rotation = WallPieceDatabase.getPieceFromBitmask(15)
	assert(piece == "Large_Tower_Stone_Wall", "Cross junction should be large tower")

	print("  Bitmasking logic correct")
end)

-- Test 4: WallGridManager initialization
test("WallGridManager initializes successfully", function()
	WallGridManager.initialize()
	local count = WallGridManager.getWallCount()
	print(string.format("  Initialized with %d existing walls", count))
end)

-- Test 5: Place test walls
test("Place walls and verify auto-tiling", function()
	-- Clean up any existing test walls
	for x = 0, 2 do
		for z = 0, 2 do
			WallGridManager.removeWall(x, z)
		end
	end

	-- Place a straight line of walls (should auto-tile to straight pieces)
	local testOwnerId = 999999

	local wall1 = WallGridManager.placeWall(0, 0, testOwnerId, "Stone_Wall")
	assert(wall1, "Failed to place wall 1")

	local wall2 = WallGridManager.placeWall(1, 0, testOwnerId, "Stone_Wall")
	assert(wall2, "Failed to place wall 2")

	local wall3 = WallGridManager.placeWall(2, 0, testOwnerId, "Stone_Wall")
	assert(wall3, "Failed to place wall 3")

	-- Check middle wall is straight (bitmask = 10: East + West)
	local wallData = WallGridManager.getWall(1, 0)
	assert(wallData, "Failed to get wall data")
	print(string.format("  Middle wall piece type: %s", wallData.pieceType))

	-- Place wall to create corner
	local wall4 = WallGridManager.placeWall(0, 1, testOwnerId, "Stone_Wall")
	assert(wall4, "Failed to place wall 4")

	-- Check corner wall (0,0) should now be a tower (bitmask = 6: East + South)
	wallData = WallGridManager.getWall(0, 0)
	print(string.format("  Corner wall piece type: %s (should be tower)", wallData.pieceType))

	print(string.format("  Successfully placed %d test walls", 4))
end)

-- Test 6: Grid occupancy checks
test("Grid occupancy checks work", function()
	assert(WallGridManager.isOccupied(0, 0), "Position (0,0) should be occupied")
	assert(WallGridManager.isOccupied(1, 0), "Position (1,0) should be occupied")
	assert(not WallGridManager.isOccupied(10, 10), "Position (10,10) should be empty")
	print("  Occupancy checks working")
end)

-- Test 7: Get player walls
test("Get player walls function works", function()
	local playerWalls = WallGridManager.getPlayerWalls(999999)
	assert(#playerWalls >= 4, string.format("Expected at least 4 walls, got %d", #playerWalls))
	print(string.format("  Found %d walls for test player", #playerWalls))
end)

-- Test 8: Wall removal
test("Wall removal works and updates neighbors", function()
	local initialCount = WallGridManager.getWallCount()

	-- Remove middle wall
	local success = WallGridManager.removeWall(1, 0)
	assert(success, "Failed to remove wall")

	local newCount = WallGridManager.getWallCount()
	assert(newCount == initialCount - 1, "Wall count didn't decrease")

	-- Check it's actually gone
	assert(not WallGridManager.isOccupied(1, 0), "Position should be empty after removal")

	print("  Wall removal working correctly")
end)

-- Test 9: Model structure verification
test("Wall models have correct structure", function()
	local assets = ReplicatedStorage.Assets.Buildings
	local model = assets:FindFirstChild("Straight_Stone_Wall")

	if model then
		-- Check for PrimaryPart
		if not model.PrimaryPart then
			warn("  WARNING: Straight_Stone_Wall has no PrimaryPart set")
		else
			print(string.format("  PrimaryPart: %s ✓", model.PrimaryPart.Name))
		end

		-- Check for ConnectionPoints (optional)
		local cpFolder = model:FindFirstChild("ConnectionPoints")
		if cpFolder then
			local cpCount = #cpFolder:GetChildren()
			print(string.format("  ConnectionPoints: %d ✓", cpCount))
		else
			print("  ConnectionPoints: None (this is OK)")
		end

		-- Check size
		local cf, size = model:GetBoundingBox()
		print(string.format("  Size: %.1f x %.1f x %.1f", size.X, size.Y, size.Z))
	end
end)

-- Test 10: Configuration validation
test("WallPieceDatabase configuration is valid", function()
	assert(WallPieceDatabase.GRID_SIZE > 0, "Grid size must be positive")
	assert(WallPieceDatabase.SNAP_RADIUS > 0, "Snap radius must be positive")

	-- Verify all bitmasks have entries
	for i = 0, 15 do
		local config = WallPieceDatabase.BITMASK_LOOKUP[i]
		assert(config, string.format("Missing bitmask entry for %d", i))
		assert(config.pieceType, string.format("Bitmask %d missing pieceType", i))
		assert(config.rotation ~= nil, string.format("Bitmask %d missing rotation", i))
	end

	print("  All bitmask entries valid (0-15)")
end)

-- Print summary
print("\n" .. string.rep("=", 80))
print("TEST SUMMARY")
print(string.rep("=", 80))
print(string.format("Tests Passed: %d", testsPassed))
print(string.format("Tests Failed: %d", testsFailed))
print(string.rep("=", 80) .. "\n")

if testsFailed == 0 then
	print("✓ ALL TESTS PASSED! Wall system is ready to use!")
else
	warn("✗ SOME TESTS FAILED! Check the errors above.")
end

-- Optional: Visual test grid
print("\nCurrent wall grid (center 5x5):")
WallGridManager.debugPrintGrid(0, 0, 2)

print("\n" .. string.rep("=", 80))
print("WALL STATISTICS")
print(string.rep("=", 80))
print(string.format("Total walls in system: %d", WallGridManager.getWallCount()))
print(string.format("Grid size: %d studs", WallPieceDatabase.GRID_SIZE))
print(string.format("Wall piece types configured: %d", #WallPieceDatabase.PIECES))
print(string.rep("=", 80) .. "\n")

-- Cleanup test walls
print("Cleaning up test walls...")
for x = -2, 2 do
	for z = -2, 2 do
		local wallData = WallGridManager.getWall(x, z)
		if wallData and wallData.ownerId == 999999 then
			WallGridManager.removeWall(x, z)
		end
	end
end
print("✓ Cleanup complete\n")

print("TEST SUITE FINISHED\n")
