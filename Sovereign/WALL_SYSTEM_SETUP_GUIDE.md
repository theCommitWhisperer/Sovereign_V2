# Wall System Setup Guide

## Overview

This guide will help you set up the new optimized wall system for your Roblox game. The system features:
- **Automatic wall piece selection** using bitmasking (no more manual selection!)
- **Grid-based placement** for consistent alignment
- **Mobile-optimized rendering** with Level of Detail (LOD)
- **Smart neighbor detection** and auto-tiling

## Architecture

The new wall system consists of:

1. **WallPieceDatabase** (`src/shared/WallPieceDatabase.luau`) - Configuration for all wall pieces
2. **WallGridManager** (`src/server/Systems/WallGridManager.luau`) - Server-side grid management and auto-tiling
3. **WallRenderer** (`src/client/WallRenderer.client.luau`) - Client-side LOD rendering
4. **WallPlacementController** (`src/client/WallPlacementController.client.luau`) - Client-side placement UI
5. **GameManager integration** - Server event handlers for wall placement

## Step 1: Prepare Your Wall Models

Your wall models are located in `ReplicatedStorage/Assets/Buildings/`. Each model needs proper setup:

### Required Model Structure

Each wall model MUST have:

```
WallModel (Model)
├── PrimaryPart (BasePart) - Set this to the main structural part
├── ConnectionPoints (Folder) - OPTIONAL but recommended
│   ├── ConnectionPoint (BasePart)
│   ├── ConnectionPoint (BasePart)
│   └── ... (more connection points)
└── [Other visual parts]
```

### Connection Points Setup

**IMPORTANT**: Connection points are NOT required for the new system to work! The system uses grid-based placement.

However, if you want to add them for future features (like visual indicators), follow these rules:

1. Create a Folder named "ConnectionPoints" in your model
2. Add BaseParts named "ConnectionPoint" to this folder
3. Position them at ground level (Y ≈ 0 relative to the model's pivot)
4. Set properties:
   - `Transparency = 1` (invisible)
   - `CanCollide = false`
   - `Anchored = false`

**For straight walls**: Add 2 connection points (one at each end)
**For towers**: Add 4 connection points (one on each side)
**For gates**: Add 2 connection points (one on each side)

### Model Naming

Ensure your models are named EXACTLY as configured in `WallPieceDatabase.luau`:

- `Straight_Stone_Wall` ✅
- `Short_Straight_Stone_Wall` ✅
- `Ladder_Stone_Wall` ✅
- `Small_Tower_Stone_Wall` ✅
- `Large_Tower_Stone_Wall` ✅
- `Large_Keep_Stone` ✅
- `Gatehouse_Stone_Wall` ✅

### Model Positioning

1. **Set the PrimaryPart**: Right-click your model → "Set PrimaryPart"
2. **Position the pivot**: The pivot should be at ground level (Y = 0) in the center of the model
3. **Verify size**: Check that sizes match the values in `WallPieceDatabase.luau`

## Step 2: Configure WallPieceDatabase

Open `src/shared/WallPieceDatabase.luau` and verify/update the configuration:

```lua
WallPieceDatabase.PIECES = {
	["Straight_Stone_Wall"] = {
		assetName = "Straight_Stone_Wall",
		width = 16,  -- ← Update this to match your model's actual width
		height = 16, -- ← Update this
		depth = 16,  -- ← Update this
		connectionPoints = 2,
		category = "straight",
	},
	-- ... more pieces
}
```

### How to Get Accurate Sizes

1. In Roblox Studio, select your wall model
2. Open the Properties panel
3. Look at the bounding box size (or use GetBoundingBox in a script)
4. Update the width/height/depth values accordingly

### Grid Size Configuration

The grid size is currently set to 16 studs:

```lua
WallPieceDatabase.GRID_SIZE = 16
```

This should match your most common wall piece width. If most of your walls are 10 studs wide, change this to 10.

## Step 3: Update Bitmasking Rules (Optional)

The `BITMASK_LOOKUP` table in `WallPieceDatabase.luau` defines which wall piece to use based on neighbors.

Current configuration:
- **Isolated wall or 1 neighbor**: Straight wall
- **2 opposite neighbors**: Straight wall (line)
- **2 adjacent neighbors**: Small tower (corner)
- **3 neighbors**: Small tower (T-junction)
- **4 neighbors**: Large tower (cross junction)

To customize:

```lua
WallPieceDatabase.BITMASK_LOOKUP = {
	[0] = { pieceType = "Straight_Stone_Wall", rotation = 0 }, -- No neighbors
	[3] = { pieceType = "Small_Tower_Stone_Wall", rotation = 0 }, -- North + East corner
	[15] = { pieceType = "Large_Tower_Stone_Wall", rotation = 0 }, -- All 4 neighbors
	-- ... etc
}
```

## Step 4: Test the System

### In Roblox Studio:

1. **Start the game** in Studio
2. **Open the Output window** (View → Output)
3. **Check for initialization messages**:
   ```
   [WallGridManager] Initializing...
   [WallGridManager] Initialized with X existing walls
   [WallRenderer] Running on DESKTOP device
   ```

4. **Test placement**:
   - Select a wall building from your UI
   - The ghost preview should appear and snap to grid
   - Click to place
   - Check Output for placement confirmations

### Debug Commands

Add these to your test script:

```lua
-- Print wall statistics
local WallGridManager = require(game.ServerScriptService.Systems.WallGridManager)
print("Total walls:", WallGridManager.getWallCount())

-- Print grid around a position
WallGridManager.debugPrintGrid(0, 0, 5) -- Center (0,0), radius 5

-- Print LOD stats (client-side)
local WallRenderer = require(game.StarterPlayer.StarterPlayerScripts.WallRenderer)
WallRenderer.printStats()
```

## Step 5: Optimize for Mobile

### LOD Configuration

The LOD system is in `src/client/WallRenderer.client.luau`:

```lua
local LOD_CONFIG = {
	mobile = {
		highDetailDistance = 50,    -- Full detail within 50 studs
		mediumDetailDistance = 120, -- Medium detail 50-120 studs
		lowDetailDistance = 250,    -- Low detail 120-250 studs
		updateInterval = 0.5,       -- Update twice per second
	},
	desktop = {
		highDetailDistance = 80,
		mediumDetailDistance = 200,
		lowDetailDistance = 400,
		updateInterval = 0.3,
	},
}
```

**Adjust these values** based on your game's needs:
- Smaller values = better performance, less visual quality
- Larger values = better visuals, worse performance

### Enable Streaming (Recommended)

In Roblox Studio:
1. Select **Workspace** in Explorer
2. In Properties, find **StreamingEnabled**
3. Set it to `true`
4. Set **StreamingTargetRadius** to `128` (for mobile) or `256` (for desktop)

This will dramatically improve performance on mobile devices with large maps.

## Step 6: Replace Old System

Once you've verified the new system works:

### Files to Delete/Archive:

1. **Old WallSystem**: `src/server/Systems/WallSystem.luau`
2. **Old WallGridConfig**: `src/shared/WallGridConfig.luau`
3. **Old PlacementController** (only wall-related code): `src/client/PlacementController.client.luau`

### Keep These (Non-Wall Placement):

- Building placement logic in PlacementController (for non-wall buildings)
- Building construction/management in BuildingManager

## Troubleshooting

### Walls Not Appearing

**Check**:
1. Models are in `ReplicatedStorage/Assets/Buildings/`
2. Model names match exactly (case-sensitive!)
3. Output window for error messages
4. WallGridManager initialized successfully

### Wrong Wall Piece Selected

**Check**:
1. Bitmask lookup table in `WallPieceDatabase.luau`
2. Grid size matches your wall widths
3. Output shows correct neighbor detection

### Walls Floating or Underground

**Check**:
1. Model pivot is at ground level (Y = 0)
2. PrimaryPart is set correctly
3. Connection points (if used) are at ground level

### Performance Issues

**Solutions**:
1. Reduce LOD distances in `WallRenderer.client.luau`
2. Enable Workspace Streaming
3. Combine wall meshes in Blender (advanced)
4. Reduce texture sizes to 512x512

### Walls Not Snapping to Grid

**Check**:
1. Grid size in `WallPieceDatabase.luau`
2. Placement is using grid coordinates, not world coordinates
3. Client is sending correct `gridX` and `gridZ` values

## Advanced Customization

### Adding New Wall Types

1. Add model to `ReplicatedStorage/Assets/Buildings/`
2. Add entry to `WallPieceDatabase.PIECES`
3. Update `BITMASK_LOOKUP` if needed
4. Test placement

### Custom Rotation Logic

Modify the rotation calculation in `WallGridManager._updateWallVisuals()`:

```lua
local newPieceType, autoRotation = WallPieceDatabase.getPieceFromBitmask(bitmask, wallData.manualOverride)

-- Custom rotation logic here
if someCondition then
	autoRotation = (autoRotation + 90) % 360
end
```

### Wall Networks and Connectivity

The WallGridManager tracks all walls in a grid. Future features you could add:

- **Wall health system**: Track damage per wall segment
- **Wall gates**: Toggle CanCollide for pathfinding
- **Wall upgrades**: Swap wall piece types (stone → iron)
- **Siege weapons**: Target specific wall segments

Example:
```lua
-- Get all walls owned by a player
local playerWalls = WallGridManager.getPlayerWalls(player.UserId)

for _, wallData in playerWalls do
	print("Wall at", wallData.gridX, wallData.gridZ)
	print("Type:", wallData.pieceType)
end
```

## Performance Metrics

Target performance on mobile devices:
- **Draw calls**: < 30 for entire wall system
- **Memory**: < 100MB for walls
- **FPS impact**: < 5ms per frame
- **Concurrent instances**: < 500 visible at once

Monitor with:
```lua
-- F9 → Developer Console → Stats
-- Look for:
-- - Draw Calls
-- - Memory
-- - Heartbeat (frame time)
```

## Next Steps

1. ✅ Set up wall models with proper structure
2. ✅ Configure WallPieceDatabase
3. ✅ Test placement in Studio
4. ✅ Optimize LOD settings
5. ✅ Enable streaming for large maps
6. ✅ Remove old wall system files
7. ✅ Test on actual mobile device (using Roblox app)
8. ✅ Iterate and optimize based on performance

## Support

If you encounter issues:
1. Check the Output window for error messages
2. Verify all model names and paths
3. Test with a single wall piece first
4. Review the debug print statements in the code

Good luck building your castle walls! 🏰
