--[[ 
	Building Model Information Printer

	HOW TO USE:
	1. Copy this script into a regular Script in ServerScriptService in Roblox Studio.
	2. Run the game by pressing Play or Run.
	3. Open the Output window (View > Output) to see the detailed information for each building model.

	This script inspects and prints detailed properties for all models found in
	ReplicatedStorage.Assets.Buildings.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local function printSeparator()
	print(string.rep("=", 80))
end

local function printModelInfo(model: Model)
	printSeparator()
	print("MODEL: " .. model.Name .. " (" .. model:GetFullName() .. ")")
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
		print(
			string.format(
				"  Position: (%.2f, %.2f, %.2f)",
				model.PrimaryPart.Position.X,
				model.PrimaryPart.Position.Y,
				model.PrimaryPart.Position.Z
			)
		)
		print(
			string.format(
				"  Size: (%.2f, %.2f, %.2f)",
				model.PrimaryPart.Size.X,
				model.PrimaryPart.Size.Y,
				model.PrimaryPart.Size.Z
			)
		)
	else
		print("PrimaryPart: NONE")
	end

	-- List all children in the model
	print("\nChildren in Model:")
	local children = model:GetChildren()
	if #children > 0 then
		for i, child in ipairs(children) do
			print(string.format("  %d. %s (ClassName: %s)", i, child.Name, child.ClassName))
		end
	else
		print("  No children found.")
	end

	-- List all parts in the model
	print("\nAll Parts in Model:")
	local parts = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end

	if #parts > 0 then
		for i, part in ipairs(parts) do
			print(
				string.format(
					"  %d. %s - Size: (%.2f, %.2f, %.2f), Pos: (%.2f, %.2f, %.2f)",
					i,
					part.Name,
					part.Size.X,
					part.Size.Y,
					part.Size.Z,
					part.Position.X,
					part.Position.Y,
					part.Position.Z
				)
			)
		end
	else
		print("  No BaseParts found in model.")
	end

	print("")
end

-- Main execution
local function runReport()
	printSeparator()
	print("BUILDING MODEL INFORMATION REPORT")
	printSeparator()

	local Assets = ReplicatedStorage:FindFirstChild("Assets")
	if not Assets then
		warn("❌ WARNING: Could not find ReplicatedStorage.Assets!")
		return
	end

	local Buildings = Assets:FindFirstChild("Buildings")
	if not Buildings then
		warn("❌ WARNING: Could not find ReplicatedStorage.Assets.Buildings!")
		return
	end

	print(string.format("\nFound Buildings folder at: %s", Buildings:GetFullName()))
	local models = Buildings:GetChildren()
	print(string.format("Number of children in folder: %d\n", #models))

	local foundModels = 0
	for _, model in ipairs(models) do
		if model:IsA("Model") then
			foundModels = foundModels + 1
			printModelInfo(model)
		end
	end

	-- Summary
	printSeparator()
	print("SUMMARY")
	printSeparator()
	print(string.format("Models found and inspected: %d", foundModels))
	print("Report finished.")
	printSeparator()
end

runReport()
