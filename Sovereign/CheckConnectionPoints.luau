--[[
	ConnectionPoints Diagnostic Script

	HOW TO USE:
	1. Copy this script to ServerScriptService in Roblox Studio
	2. Run the game
	3. Check the Output window for diagnostic information

	This script checks all wall models in ReplicatedStorage.Assets.Buildings
	and reports any issues with their ConnectionPoints setup.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local function findConnectionPoints(model: Model): { BasePart }
	if not model then
		return {}
	end

	local connectionPoints = {}
	local folder = model:FindFirstChild("ConnectionPoints")

	if folder then
		for _, child in folder:GetChildren() do
			if child:IsA("BasePart") and child.Name == "ConnectionPoint" then
				table.insert(connectionPoints, child)
			end
		end
	else
		warn(string.format("❌ Model '%s' has NO ConnectionPoints folder!", model.Name))
	end

	return connectionPoints
end

local function checkModel(model: Model)
	print(string.format("\n=== Checking Model: %s ===", model.Name))

	local connectionPoints = findConnectionPoints(model)

	if #connectionPoints == 0 then
		warn(string.format("❌ FAIL: Model '%s' has NO ConnectionPoints!", model.Name))
		return false
	end

	print(string.format("✓ Found %d ConnectionPoints", #connectionPoints))

	-- Get model pivot
	local pivotPos = model:GetPivot().Position
	print(string.format("  Model Pivot: (%.2f, %.2f, %.2f)", pivotPos.X, pivotPos.Y, pivotPos.Z))

	-- Check each ConnectionPoint
	local allValid = true
	for i, cp in connectionPoints do
		print(string.format("\n  ConnectionPoint %d:", i))
		print(string.format("    World Position: (%.2f, %.2f, %.2f)", cp.Position.X, cp.Position.Y, cp.Position.Z))

		-- Calculate offset from pivot (in model space)
		local pivotCFrame = model:GetPivot()
		local cpLocalPos = pivotCFrame:PointToObjectSpace(cp.Position)
		print(string.format("    Offset from Pivot: (%.2f, %.2f, %.2f)", cpLocalPos.X, cpLocalPos.Y, cpLocalPos.Z))

		-- Check properties
		if cp.Transparency ~= 1 then
			warn(string.format("    ⚠️  Transparency is %.2f (should be 1)", cp.Transparency))
			allValid = false
		end

		if cp.CanCollide then
			warn("    ⚠️  CanCollide is true (should be false)")
			allValid = false
		end

		if cp.Anchored then
			warn("    ⚠️  Anchored is true (should be false)")
			allValid = false
		end

		-- Check Y offset (should be negative for floor level if pivot is at center)
		if cpLocalPos.Y > 0 then
			warn(string.format("    ⚠️  Y offset is POSITIVE (%.2f) - ConnectionPoint may be above pivot!", cpLocalPos.Y))
			print("       For floor-level placement, Y should typically be NEGATIVE (below the pivot)")
			allValid = false
		end

		if math.abs(cpLocalPos.Y) < 1 then
			warn(string.format("    ⚠️  Y offset is very small (%.2f) - Are you sure this is at floor level?", cpLocalPos.Y))
			allValid = false
		end
	end

	-- Check if all ConnectionPoints have the same Y offset
	if #connectionPoints > 1 then
		local pivotCFrame = model:GetPivot()
		local firstY = pivotCFrame:PointToObjectSpace(connectionPoints[1].Position).Y
		local allSameY = true

		for i = 2, #connectionPoints do
			local cpY = pivotCFrame:PointToObjectSpace(connectionPoints[i].Position).Y
			if math.abs(cpY - firstY) > 0.1 then
				allSameY = false
				warn(string.format("    ⚠️  ConnectionPoints have different Y offsets! CP1: %.2f, CP%d: %.2f", firstY, i, cpY))
				break
			end
		end

		if allSameY then
			print(string.format("  ✓ All ConnectionPoints at same Y offset: %.2f", firstY))
		else
			allValid = false
		end
	end

	if allValid then
		print(string.format("\n✅ PASS: Model '%s' ConnectionPoints look correct!", model.Name))
	else
		warn(string.format("\n❌ ISSUES FOUND in model '%s'", model.Name))
	end

	return allValid
end

-- Main execution
print("\n" .. string.rep("=", 60))
print("CONNECTION POINTS DIAGNOSTIC CHECK")
print(string.rep("=", 60))

local Assets = ReplicatedStorage:FindFirstChild("Assets")
if not Assets then
	error("❌ CRITICAL: Could not find ReplicatedStorage.Assets!")
end

local Buildings = Assets:FindFirstChild("Buildings")
if not Buildings then
	error("❌ CRITICAL: Could not find ReplicatedStorage.Assets.Buildings!")
end

print(string.format("\nFound Buildings folder with %d children", #Buildings:GetChildren()))

-- Check specific wall models
local wallModels = {
	"Wall Segment",
	"Wall Corner",
	"Wall Corner Reverse",
	"Tower",
	"Gatehouse",
	"Ladder Wall Segment",
}

local allPassed = true
local modelsChecked = 0

for _, modelName in wallModels do
	local model = Buildings:FindFirstChild(modelName)
	if model and model:IsA("Model") then
		modelsChecked = modelsChecked + 1
		local passed = checkModel(model)
		if not passed then
			allPassed = false
		end
	else
		warn(string.format("\n⚠️  Model '%s' not found in Buildings folder", modelName))
	end
end

-- Summary
print("\n" .. string.rep("=", 60))
print("SUMMARY")
print(string.rep("=", 60))
print(string.format("Models checked: %d", modelsChecked))

if allPassed then
	print("\n✅ ALL MODELS PASSED! Your ConnectionPoints setup looks good!")
	print("   Next steps:")
	print("   1. Test wall placement in-game")
	print("   2. Check if walls snap together properly")
	print("   3. Verify walls sit at ground level")
else
	warn("\n❌ SOME MODELS HAVE ISSUES!")
	print("   Please fix the issues above, then run this script again.")
	print("   Common fixes:")
	print("   - Set ConnectionPoint Y position to negative value (e.g., -10)")
	print("   - Set Transparency = 1")
	print("   - Set CanCollide = false")
	print("   - Set Anchored = false")
end

print(string.rep("=", 60) .. "\n")
