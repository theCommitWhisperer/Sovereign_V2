--[[
	Wall Model Information Printer

	HOW TO USE:
	1. Copy this script to ServerScriptService in Roblox Studio
	2. Run the game
	3. Check the Output window for detailed model information

	This script prints EVERYTHING about your wall models so we can see what's wrong.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local function printSeparator()
	print(string.rep("=", 80))
end

local function printModelInfo(model: Model)
	printSeparator()
	print("MODEL: " .. model.Name)
	printSeparator()

	-- Get pivot information
	local pivotCFrame = model:GetPivot()
	local pivotPos = pivotCFrame.Position
	print(string.format("Pivot Position: (%.2f, %.2f, %.2f)", pivotPos.X, pivotPos.Y, pivotPos.Z))

	-- Get model bounds
	local cf, size = model:GetBoundingBox()
	print(string.format("Bounding Box Size: (%.2f, %.2f, %.2f)", size.X, size.Y, size.Z))
	print(string.format("Bounding Box Center: (%.2f, %.2f, %.2f)", cf.Position.X, cf.Position.Y, cf.Position.Z))

	-- Check for PrimaryPart
	if model.PrimaryPart then
		print("PrimaryPart: " .. model.PrimaryPart.Name)
		print(string.format("  Position: (%.2f, %.2f, %.2f)",
			model.PrimaryPart.Position.X,
			model.PrimaryPart.Position.Y,
			model.PrimaryPart.Position.Z))
		print(string.format("  Size: (%.2f, %.2f, %.2f)",
			model.PrimaryPart.Size.X,
			model.PrimaryPart.Size.Y,
			model.PrimaryPart.Size.Z))
	else
		print("PrimaryPart: NONE")
	end

	-- Check for ConnectionPoints folder
	local connectionPointsFolder = model:FindFirstChild("ConnectionPoints")
	if connectionPointsFolder then
		print("\nConnectionPoints Folder: FOUND")

		local connectionPoints = {}
		for _, child in connectionPointsFolder:GetChildren() do
			if child:IsA("BasePart") and child.Name == "ConnectionPoint" then
				table.insert(connectionPoints, child)
			end
		end

		if #connectionPoints > 0 then
			print(string.format("Number of ConnectionPoints: %d\n", #connectionPoints))

			for i, cp in connectionPoints do
				print(string.format("  ConnectionPoint #%d:", i))
				print(string.format("    World Position: (%.2f, %.2f, %.2f)",
					cp.Position.X, cp.Position.Y, cp.Position.Z))

				-- Calculate position relative to pivot
				local relativeToPivot = pivotCFrame:PointToObjectSpace(cp.Position)
				print(string.format("    Relative to Pivot: (%.2f, %.2f, %.2f)",
					relativeToPivot.X, relativeToPivot.Y, relativeToPivot.Z))

				-- Calculate position relative to bounding box center
				local relativeToBBox = cf:PointToObjectSpace(cp.Position)
				print(string.format("    Relative to BBox Center: (%.2f, %.2f, %.2f)",
					relativeToBBox.X, relativeToBBox.Y, relativeToBBox.Z))

				print(string.format("    Size: (%.2f, %.2f, %.2f)", cp.Size.X, cp.Size.Y, cp.Size.Z))
				print(string.format("    Transparency: %.2f", cp.Transparency))
				print(string.format("    CanCollide: %s", tostring(cp.CanCollide)))
				print(string.format("    Anchored: %s", tostring(cp.Anchored)))
				print("")
			end

			-- Calculate average ConnectionPoint position
			local avgPos = Vector3.new(0, 0, 0)
			for _, cp in connectionPoints do
				avgPos = avgPos + cp.Position
			end
			avgPos = avgPos / #connectionPoints

			print(string.format("  Average CP World Position: (%.2f, %.2f, %.2f)",
				avgPos.X, avgPos.Y, avgPos.Z))

			local avgRelativeToPivot = pivotCFrame:PointToObjectSpace(avgPos)
			print(string.format("  Average CP Relative to Pivot: (%.2f, %.2f, %.2f)",
				avgRelativeToPivot.X, avgRelativeToPivot.Y, avgRelativeToPivot.Z))

		else
			print("  WARNING: ConnectionPoints folder exists but contains NO ConnectionPoint parts!")
		end
	else
		print("\nConnectionPoints Folder: NOT FOUND")
		print("  ERROR: This model needs a ConnectionPoints folder!")
	end

	-- List all parts in the model
	print("\nAll Parts in Model:")
	local partCount = 0
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.Name ~= "ConnectionPoint" then
			partCount = partCount + 1
			print(string.format("  %d. %s - Size: (%.2f, %.2f, %.2f), Pos: (%.2f, %.2f, %.2f)",
				partCount,
				descendant.Name,
				descendant.Size.X, descendant.Size.Y, descendant.Size.Z,
				descendant.Position.X, descendant.Position.Y, descendant.Position.Z))
		end
	end

	print("")
end

-- Main execution
printSeparator()
print("WALL MODEL INFORMATION REPORT")
printSeparator()

local Assets = ReplicatedStorage:FindFirstChild("Assets")
if not Assets then
	error("❌ CRITICAL: Could not find ReplicatedStorage.Assets!")
end

local Buildings = Assets:FindFirstChild("Buildings")
if not Buildings then
	error("❌ CRITICAL: Could not find ReplicatedStorage.Assets.Buildings!")
end

print(string.format("\nFound Buildings folder at: %s", Buildings:GetFullName()))
print(string.format("Number of children: %d\n", #Buildings:GetChildren()))

-- Wall models to check
local wallModels = {
	"Wall Segment",
	"Wall Corner",
	"Wall Corner Reverse",
	"Tower",
	"Gatehouse",
	"Ladder Wall Segment",
}

local foundModels = 0

for _, modelName in wallModels do
	local model = Buildings:FindFirstChild(modelName)
	if model and model:IsA("Model") then
		foundModels = foundModels + 1
		printModelInfo(model)
	else
		printSeparator()
		print("MODEL: " .. modelName)
		printSeparator()
		print("❌ NOT FOUND or not a Model!")
		print("")
	end
end

-- Summary
printSeparator()
print("SUMMARY")
printSeparator()
print(string.format("Models found: %d out of %d", foundModels, #wallModels))
print("")
print("Look for these potential issues:")
print("  1. Different 'Relative to Pivot' Y values across different wall types")
print("  2. ConnectionPoints folder missing")
print("  3. ConnectionPoints with CanCollide = true or Anchored = true")
print("  4. Transparency not set to 1")
print("")
printSeparator()
