--[[
	Corner Wall Analysis Script
	Paste this into Roblox Studio Command Bar to analyze the Corner_Stone_Wall model

	Instructions:
	1. Open Roblox Studio
	2. Make sure Corner_Stone_Wall exists in ReplicatedStorage.Assets.Buildings
	3. Open the Command Bar (View > Command Bar)
	4. Copy and paste this entire script
	5. Press Enter to run
	6. Copy all the output from the Output window and send it to Claude
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

print("========================================")
print("CORNER WALL ANALYSIS")
print("========================================")

-- Find the Corner_Stone_Wall model
local assets = ReplicatedStorage:FindFirstChild("Assets")
if not assets then
	warn("Assets folder not found in ReplicatedStorage")
	return
end

local buildings = assets:FindFirstChild("Buildings")
if not buildings then
	warn("Buildings folder not found in Assets")
	return
end

local cornerWall = buildings:FindFirstChild("Corner_Stone_Wall")
if not cornerWall or not cornerWall:IsA("Model") then
	warn("Corner_Stone_Wall model not found in Assets.Buildings")
	return
end

print("\n1. MODEL INFORMATION:")
print("   Name: " .. cornerWall.Name)
print("   ClassName: " .. cornerWall.ClassName)

-- Get pivot information
local pivot = cornerWall:GetPivot()
print("\n2. PIVOT INFORMATION:")
print("   Pivot Position: " .. tostring(pivot.Position))
print("   Pivot X: " .. pivot.Position.X)
print("   Pivot Y: " .. pivot.Position.Y)
print("   Pivot Z: " .. pivot.Position.Z)

-- Get bounding box
local boundingCF, boundingSize = cornerWall:GetBoundingBox()
print("\n3. BOUNDING BOX:")
print("   Center Position: " .. tostring(boundingCF.Position))
print("   Center X: " .. boundingCF.Position.X)
print("   Center Y: " .. boundingCF.Position.Y)
print("   Center Z: " .. boundingCF.Position.Z)
print("   Size: " .. tostring(boundingSize))
print("   Width (X): " .. boundingSize.X)
print("   Height (Y): " .. boundingSize.Y)
print("   Depth (Z): " .. boundingSize.Z)

-- Calculate extents
local minX = boundingCF.Position.X - (boundingSize.X / 2)
local maxX = boundingCF.Position.X + (boundingSize.X / 2)
local minY = boundingCF.Position.Y - (boundingSize.Y / 2)
local maxY = boundingCF.Position.Y + (boundingSize.Y / 2)
local minZ = boundingCF.Position.Z - (boundingSize.Z / 2)
local maxZ = boundingCF.Position.Z + (boundingSize.Z / 2)

print("\n4. BOUNDING BOX EXTENTS:")
print("   Min X: " .. minX)
print("   Max X: " .. maxX)
print("   Min Y: " .. minY)
print("   Max Y: " .. maxY)
print("   Min Z: " .. minZ)
print("   Max Z: " .. maxZ)

-- Calculate offsets from pivot
print("\n5. PIVOT OFFSETS FROM BOUNDING BOX:")
print("   Pivot to Center X: " .. (pivot.Position.X - boundingCF.Position.X))
print("   Pivot to Center Y: " .. (pivot.Position.Y - boundingCF.Position.Y))
print("   Pivot to Center Z: " .. (pivot.Position.Z - boundingCF.Position.Z))
print("   Pivot to Bottom: " .. (pivot.Position.Y - minY))
print("   Pivot to Top: " .. (maxY - pivot.Position.Y))
print("   Pivot to Front (-Z): " .. (pivot.Position.Z - minZ))
print("   Pivot to Back (+Z): " .. (maxZ - pivot.Position.Z))
print("   Pivot to Left (-X): " .. (pivot.Position.X - minX))
print("   Pivot to Right (+X): " .. (maxX - pivot.Position.X))

-- Check PrimaryPart
print("\n6. PRIMARY PART:")
if cornerWall.PrimaryPart then
	print("   Primary Part: " .. cornerWall.PrimaryPart.Name)
	print("   Primary Part Position: " .. tostring(cornerWall.PrimaryPart.Position))
	print("   Primary Part Size: " .. tostring(cornerWall.PrimaryPart.Size))
else
	print("   Primary Part: NONE")
end

-- List all parts
print("\n7. ALL PARTS IN MODEL:")
local partCount = 0
local lowestY = math.huge
local lowestPart = nil

for _, descendant in cornerWall:GetDescendants() do
	if descendant:IsA("BasePart") then
		partCount = partCount + 1
		local partBottom = descendant.Position.Y - (descendant.Size.Y / 2)
		print(string.format("   Part %d: %s", partCount, descendant.Name))
		print(string.format("      Position: %.2f, %.2f, %.2f", descendant.Position.X, descendant.Position.Y, descendant.Position.Z))
		print(string.format("      Size: %.2f, %.2f, %.2f", descendant.Size.X, descendant.Size.Y, descendant.Size.Z))
		print(string.format("      Bottom Y: %.2f", partBottom))

		if partBottom < lowestY then
			lowestY = partBottom
			lowestPart = descendant
		end
	end
end

print("\n8. LOWEST POINT:")
print("   Lowest Part: " .. (lowestPart and lowestPart.Name or "NONE"))
print("   Lowest Y Position: " .. lowestY)
print("   Pivot to Lowest: " .. (pivot.Position.Y - lowestY))

-- Calculate recommended database values
print("\n9. RECOMMENDED DATABASE VALUES:")
print("   width: " .. math.ceil(boundingSize.X))
print("   height: " .. math.ceil(boundingSize.Y))
print("   depth: " .. math.ceil(boundingSize.Z))

-- Test rotation at different angles
print("\n10. ROTATION TEST (visual check needed):")
print("   Testing 0°, 90°, 180°, 270° rotations...")
print("   After running this script, manually rotate the Corner_Stone_Wall")
print("   in Studio and check if corners align properly at grid intersections.")

-- For corner walls, check if it's designed for inner or outer corners
print("\n11. CORNER DESIGN NOTES:")
print("   Corner walls should connect at grid intersections.")
print("   At 0° rotation: Should connect West (-X) and North (-Z) walls")
print("   At 90° rotation: Should connect North (-Z) and East (+X) walls")
print("   At 180° rotation: Should connect East (+X) and South (+Z) walls")
print("   At 270° rotation: Should connect South (+Z) and West (-X) walls")
print("\n   Check if the corner geometry faces INWARD or OUTWARD.")

print("\n========================================")
print("ANALYSIS COMPLETE")
print("Copy all output above and send to Claude")
print("========================================")
