-- COMMAND BAR SCRIPT: Fix Building Pivots to CENTER
-- Copy and paste this entire script into Roblox Studio's Command Bar (View > Command Bar)
-- Then press Enter to execute

local ReplicatedStorage = game:GetService("ReplicatedStorage")

print("=== FIXING BUILDING PIVOTS ===")
print("Automatically moving all building pivots to CENTER position...")
print("")

local Assets = ReplicatedStorage:FindFirstChild("Assets")
if not Assets then
	warn("No Assets folder found in ReplicatedStorage")
	return
end

local Buildings = Assets:FindFirstChild("Buildings")
if not Buildings then
	warn("No Buildings folder found in Assets")
	return
end

local fixedCount = 0
local skippedCount = 0
local results = {}

for _, model in Buildings:GetChildren() do
	if model:IsA("Model") then
		local oldPivot = model:GetPivot()
		local oldPivotPos = oldPivot.Position

		-- Calculate model bounds
		local cframe, size = model:GetBoundingBox()
		local boundingCenter = cframe.Position

		-- Calculate where pivot currently is relative to bounding box
		local boundingMin = boundingCenter - (size / 2)
		local relativeY = (oldPivotPos.Y - boundingMin.Y) / size.Y

		-- Check if already centered (between 40% and 60% from bottom)
		if relativeY >= 0.4 and relativeY <= 0.6 then
			skippedCount = skippedCount + 1
			table.insert(results, {
				name = model.Name,
				status = "SKIPPED (already centered)",
				oldY = oldPivotPos.Y,
				newY = oldPivotPos.Y,
				relativeY = relativeY,
			})
		else
			-- Calculate the offset from current pivot to bounding center (in Y only)
			local offsetY = boundingCenter.Y - oldPivotPos.Y

			-- Move the pivot by the offset amount
			-- This shifts the pivot point without moving the model in world space
			local newPivot = oldPivot * CFrame.new(0, offsetY, 0)

			model:PivotTo(newPivot)
			fixedCount = fixedCount + 1

			local statusText = "FIXED (was OFFSET)"
			if relativeY < 0.1 then
				statusText = "FIXED (was BOTTOM)"
			elseif relativeY > 0.9 then
				statusText = "FIXED (was TOP)"
			end

			table.insert(results, {
				name = model.Name,
				status = statusText,
				oldY = oldPivotPos.Y,
				newY = oldPivotPos.Y + offsetY,
				relativeY = relativeY,
			})
		end
	end
end

-- Sort by name
table.sort(results, function(a, b)
	return a.name < b.name
end)

-- Print results
print(string.format("%-40s | %-25s | %-15s | %s", "Building Name", "Status", "Old Pivot Y", "New Pivot Y"))
print(string.rep("-", 110))

for _, result in results do
	print(
		string.format(
			"%-40s | %-25s | %-15.1f | %.1f (was %.1f%% from bottom)",
			result.name,
			result.status,
			result.oldY,
			result.newY,
			result.relativeY * 100
		)
	)
end

print("")
print("=== SUMMARY ===")
print(string.format("Fixed: %d models", fixedCount))
print(string.format("Skipped (already centered): %d models", skippedCount))
print(string.format("Total: %d models", fixedCount + skippedCount))
print("")
print("✅ DONE! Now save the place (Ctrl+S or File > Save)")
