# Wall Model Preparation Checklist

## Quick Setup for Each Wall Model

Use this checklist for each of your 7 wall models.

---

## Models to Prepare

- [ ] Straight_Stone_Wall (16x16)
- [ ] Short_Straight_Stone_Wall (10x16)
- [ ] Ladder_Stone_Wall (16x16)
- [ ] Small_Tower_Stone_Wall
- [ ] Large_Tower_Stone_Wall
- [ ] Large_Keep_Stone
- [ ] Gatehouse_Stone_Wall

---

## For Each Model:

### 1. Location ✅
- [ ] Model is in `ReplicatedStorage/Assets/Buildings/`
- [ ] Model name matches exactly (case-sensitive)

### 2. Basic Setup ✅
- [ ] Set PrimaryPart (right-click model → Set PrimaryPart)
- [ ] Verify all parts are anchored
- [ ] Check that the model isn't too complex (< 100 parts recommended)

### 3. Pivot Point ✅
- [ ] Open Properties panel
- [ ] Select the model
- [ ] Check PivotOffset
- [ ] Pivot Y should be at ground level (Y ≈ 0)
- [ ] If not, use "Edit Pivot" tool to adjust

### 4. Measurements ✅

Measure the model's bounding box:

```lua
-- Run this in Command Bar with model selected:
local model = game.Selection:Get()[1]
local cf, size = model:GetBoundingBox()
print("Size:", size)
print("Width (X):", size.X)
print("Height (Y):", size.Y)
print("Depth (Z):", size.Z)
```

Record the values:
- Width: _____ studs
- Height: _____ studs
- Depth: _____ studs

Update these in `WallPieceDatabase.luau`

### 5. Connection Points (OPTIONAL) ✅

If you want connection points for future features:

- [ ] Create a Folder named "ConnectionPoints" in the model
- [ ] Add BasePart(s) named "ConnectionPoint"
  - For straight walls: 2 points (at each end)
  - For towers: 4 points (one per side)
  - For gates: 2 points (one per side)

For each ConnectionPoint:
- [ ] Set `Transparency = 1`
- [ ] Set `CanCollide = false`
- [ ] Set `Anchored = false`
- [ ] Position at ground level (Y ≈ 0 relative to model)
- [ ] Size: 1x1x1 or smaller

### 6. Visual Optimization ✅

For better mobile performance:

- [ ] Combine similar parts where possible
- [ ] Use MeshParts instead of Unions when possible
- [ ] Texture size: 512x512 or 1024x1024 maximum
- [ ] Remove unnecessary decorative details
- [ ] Check that SurfaceAppearances aren't too heavy

### 7. Collision Setup ✅

- [ ] Main structural parts: `CanCollide = true`
- [ ] Decorative parts: `CanCollide = false`
- [ ] ConnectionPoints: `CanCollide = false`
- [ ] Use simple collision geometry (avoid complex meshes)

### 8. Testing ✅

Test the model individually:

```lua
-- Test script (run in Command Bar):
local model = game.ReplicatedStorage.Assets.Buildings.Straight_Stone_Wall
local clone = model:Clone()
clone.Parent = workspace
clone:PivotTo(CFrame.new(0, 0, 0))
```

- [ ] Model appears correctly
- [ ] Pivot is at ground level
- [ ] Model doesn't sink into ground or float
- [ ] No errors in Output

---

## After All Models are Prepared:

### Update WallPieceDatabase.luau ✅

For each model, update the entry:

```lua
["Straight_Stone_Wall"] = {
	assetName = "Straight_Stone_Wall",
	width = 16,  -- ← Your measured width
	height = 16, -- ← Your measured height
	depth = 16,  -- ← Your measured depth
	connectionPoints = 2, -- ← Number of connection points (or 0 if none)
	category = "straight",
},
```

### Verify Grid Size ✅

- [ ] `WallPieceDatabase.GRID_SIZE` matches your most common wall width
- [ ] Default is 16 (matches Straight_Stone_Wall and Ladder_Stone_Wall)

---

## Common Issues

### Model appears rotated incorrectly
**Fix**: Adjust rotation in `BITMASK_LOOKUP` table for that piece type

### Model floats or sinks into ground
**Fix**: Adjust pivot point using Edit Pivot tool. Y should be at ground level.

### Model doesn't appear at all
**Fix**:
1. Check model name matches exactly
2. Check Output for error messages
3. Verify model is in correct folder

### Model clips through other parts
**Fix**:
1. Check collision groups
2. Simplify collision geometry
3. Verify CanCollide settings

---

## Quick Copy-Paste Script

### Get All Model Info at Once

Run this script in Command Bar with a model selected:

```lua
local model = game.Selection:Get()[1]
if not model then
	print("Select a model first!")
	return
end

print("\n=== MODEL INFO ===")
print("Name:", model.Name)

-- Bounding box
local cf, size = model:GetBoundingBox()
print("Size:", size)
print("  Width (X):", math.floor(size.X + 0.5), "studs")
print("  Height (Y):", math.floor(size.Y + 0.5), "studs")
print("  Depth (Z):", math.floor(size.Z + 0.5), "studs")

-- Pivot
local pivot = model:GetPivot()
print("Pivot Position:", pivot.Position)
print("  Y level:", pivot.Position.Y)

-- PrimaryPart
if model.PrimaryPart then
	print("PrimaryPart:", model.PrimaryPart.Name)
else
	print("⚠️ NO PRIMARY PART SET")
end

-- ConnectionPoints
local cpFolder = model:FindFirstChild("ConnectionPoints")
if cpFolder then
	local count = #cpFolder:GetChildren()
	print("ConnectionPoints:", count)
else
	print("ConnectionPoints: None")
end

-- Part count
local partCount = 0
for _, v in model:GetDescendants() do
	if v:IsA("BasePart") then
		partCount = partCount + 1
	end
end
print("Total parts:", partCount)

print("\n=== COPY THIS TO WallPieceDatabase.luau ===")
print(string.format([[
["%s"] = {
	assetName = "%s",
	width = %d,
	height = %d,
	depth = %d,
	connectionPoints = %d,
	category = "straight", -- Change as needed
},
]],
	model.Name,
	model.Name,
	math.floor(size.X + 0.5),
	math.floor(size.Y + 0.5),
	math.floor(size.Z + 0.5),
	cpFolder and #cpFolder:GetChildren() or 0
))
```

Copy and paste the output directly into your WallPieceDatabase!

---

## Final Checks ✅

Before going live:

- [ ] All 7 models prepared
- [ ] WallPieceDatabase.luau updated with correct sizes
- [ ] Tested placement of each wall type
- [ ] Verified auto-tiling works (corners, junctions)
- [ ] Checked performance (FPS, draw calls)
- [ ] Tested on mobile device (if possible)

Done! Your wall system is ready! 🎉
