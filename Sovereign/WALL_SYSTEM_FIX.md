# Wall Building System Fix - Summary

## Problem Identified

The wall building ghost preview showed walls aligned correctly for straight pieces, but when placing corner pieces or other wall types, they were misaligned.

**Root Cause:**
- Different wall piece models have ConnectionPoints at different vertical offsets from their walkways
- From ModelInfo.md:
  - Wall Segment: -30.01 studs
  - Wall Corner: -29.50 studs
  - Tower: -34.51 studs
  - Gatehouse: -28.38 studs
- The placement system was using ConnectionPoint centers for positioning, but when swapping between piece types, the varying offsets caused misalignment

## Solution Implemented

Created a **grid-based wall system** with normalized configuration data for each wall piece type.

### New Files Created

1. **[WallGridConfig.luau](src/shared/WallGridConfig.luau)** - Central configuration module
   - Stores offset data for each wall piece type
   - Provides grid conversion utilities
   - Calculates proper model CFrames based on connection point alignment
   - Ensures all wall pieces align to the same 16x16 stud grid

2. **[DiagnosticScript.lua](DiagnosticScript.lua)** - Studio diagnostic tool
   - Run this in Roblox Studio to analyze your wall models
   - Reports ConnectionPoint positions, walkway positions, and offsets
   - Useful for debugging and verifying model structure

### Modified Files

3. **[PlacementController.client.luau](src/client/PlacementController.client.luau)**
   - Updated to use WallGridConfig for grid size (16 studs instead of 8)
   - Grid placement now uses `WallGridConfig.getModelCFrame()` to properly position models
   - Neighbor detection updated to use proper grid spacing
   - Falls back to old method if piece not in WallGridConfig

4. **[WallSystem.luau](src/server/Systems/WallSystem.luau)**
   - Updated to use WallGridConfig utilities
   - Grid functions now delegate to WallGridConfig module

## How It Works

### Grid-Based Positioning

1. **All walls align to a 16x16 stud grid**
   - Grid coordinates are in multiples of 16 studs
   - ConnectionPoints of all wall pieces should align to the same grid positions

2. **WallGridConfig stores offsets** for each piece type
   - `connectionPointOffset`: How far the CP center is from the model pivot
   - These offsets are used to calculate where the model pivot should be placed

3. **Placement logic**:
   ```lua
   -- Convert mouse position to grid coordinates
   local gridX, gridZ = WallGridConfig.toGrid(position)

   -- Get the precise CFrame where the model should be placed
   local modelCFrame = WallGridConfig.getModelCFrame(assetName, gridX, gridZ, rotation)

   -- Adjust for ground level and place
   ghostBuilding:PivotTo(adjustedCFrame)
   ```

4. **Connection point snapping still works**
   - When placing near existing walls, the system finds nearest ConnectionPoints
   - Snaps ghost to align perfectly with neighbor
   - This works regardless of wall piece type because all CPs are at Y=10

## Testing Instructions

1. **Run the diagnostic script first** (optional but recommended):
   - Open Roblox Studio
   - Paste DiagnosticScript.lua into Command Bar
   - Run it and verify the output matches expected offsets
   - Share output if you see discrepancies

2. **Test wall placement**:
   - Start placing a Wall Segment
   - Place several in a line - they should align perfectly
   - Switch to Wall Corner (using cycle key)
   - Place corner - it should align with the straight pieces
   - Try Tower, Gatehouse, etc.
   - All pieces should now align on the same grid

3. **Test connection snapping**:
   - Place a wall piece
   - Move mouse near an existing wall's ConnectionPoint
   - Ghost should snap to align perfectly
   - Place it - should connect seamlessly

## Expected Behavior

### Before Fix
- ❌ Straight pieces aligned to grid
- ❌ Corner pieces appeared offset when placed
- ❌ Different piece types didn't align properly
- ❌ Walkways at different heights caused visual misalignment

### After Fix
- ✅ All wall pieces align to the same 16-stud grid
- ✅ Corner pieces align perfectly with straight pieces
- ✅ All piece types connect seamlessly
- ✅ ConnectionPoints of all placed walls are at the same world positions

## Configuration Details

### Grid Settings (WallGridConfig.luau)
- **GRID_SIZE**: 16 studs (each grid cell is 16x16)
- **SNAP_RADIUS**: 20 studs (how close CPs must be to snap)
- **CONNECTION_TOLERANCE**: 4.0 studs (max distance for valid connection)

### Wall Piece Offsets
All offsets are from the model's pivot (walkway center) to CP center:

| Piece Type | Y Offset | Notes |
|------------|----------|-------|
| Wall Segment | -30.0 | Standard wall |
| Ladder Wall Segment | -30.0 | Wall with ladder |
| Wall Corner | -29.5 | 90° corner |
| Wall Corner Reverse | -29.5 | Reverse corner |
| Tower | -34.5 | Larger structure |
| Gatehouse | -28.4 | Entry structure |

## Troubleshooting

### If walls still don't align:

1. **Check your model structure**:
   - Run DiagnosticScript.lua to verify ConnectionPoint positions
   - Ensure all ConnectionPoints are named "ConnectionPoint" (or "ConnectionPoint_1", etc.)
   - Verify ConnectionPoints are at Y=10 in world space

2. **Verify grid settings**:
   - ConnectionPoints should be ~16 studs apart on straight pieces
   - Check if your models use different spacing

3. **Update WallGridConfig offsets**:
   - If diagnostic shows different offsets, update WallGridConfig.PIECES
   - Use the vertical distance from walkway to CP center

### If ghost doesn't snap properly:

1. **Check SNAP_RADIUS**: Increase in WallGridConfig if snapping range is too short
2. **Check CONNECTION_TOLERANCE**: Increase if valid connections are being rejected
3. **Verify ConnectionPoint LookVectors**: Should point outward from the model

## Alternative Solution (Not Implemented)

If the grid-based approach doesn't work for your use case, you could instead:

**Normalize all wall models** by editing them in Studio:
1. Open each wall model
2. Move all ConnectionPoints to Y=10 (local)
3. Adjust walkways so they're all at the same relative Y position (e.g., Y=40 local)
4. This would make all models have identical structure

The grid-based solution is preferred because:
- No need to edit existing models
- Handles any model structure
- Centralized configuration
- Easier to add new wall types

## Next Steps

1. **Test in Studio** - Place various wall combinations
2. **Adjust offsets if needed** - Update WallGridConfig.PIECES based on diagnostic output
3. **Add new wall types** - Simply add entries to WallGridConfig.PIECES
4. **Fine-tune snapping** - Adjust SNAP_RADIUS and CONNECTION_TOLERANCE as needed

## Files Changed Summary

| File | Status | Purpose |
|------|--------|---------|
| `src/shared/WallGridConfig.luau` | ✨ New | Grid configuration and utilities |
| `DiagnosticScript.lua` | ✨ New | Studio diagnostic tool |
| `src/client/PlacementController.client.luau` | 📝 Modified | Uses grid config for placement |
| `src/server/Systems/WallSystem.luau` | 📝 Modified | Uses grid config utilities |

---

**Questions or Issues?** Run the diagnostic script and share the output for further troubleshooting.
