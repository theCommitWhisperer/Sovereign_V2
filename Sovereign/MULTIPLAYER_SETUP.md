# Multiplayer Quadrant System

## Overview

The game now supports up to 4 players, with each player assigned to their own estate quadrant. The map is divided into 4 sections with neutral space between them to prevent building conflicts.

## Map Layout

```
Total Map Size: 1000x1000 studs

┌──────────────────────────────────────────────────────────┐
│                                                          │
│   Quadrant 1 (NW)     NEUTRAL    Quadrant 2 (NE)       │
│    Kingdom (Blue)      ZONE       Empire (Gold)         │
│    400x400 studs     100 studs    400x400 studs        │
│    Spawn: (-250,10,250)          Spawn: (250,10,250)   │
│                                                          │
├──────────────────────────────────────────────────────────┤
│                                                          │
│      NEUTRAL         NEUTRAL         NEUTRAL            │
│       ZONE            ZONE            ZONE               │
│     100 studs       100 studs       100 studs           │
│                                                          │
├──────────────────────────────────────────────────────────┤
│                                                          │
│   Quadrant 3 (SW)     NEUTRAL    Quadrant 4 (SE)       │
│   Tribes (Green)       ZONE     IronLegion (Gray)       │
│    400x400 studs     100 studs    400x400 studs        │
│    Spawn: (-250,10,-250)        Spawn: (250,10,-250)   │
│                                                          │
└──────────────────────────────────────────────────────────┘
```

## How It Works

### 1. Player Assignment (SpawnManager)

When a player starts the game, the [SpawnManager](src/server/Managers/SpawnManager.luau) automatically assigns them to a quadrant:

- **Round-robin assignment**: Players are distributed evenly across quadrants
- **First player**: Assigned to Quadrant 1 (Kingdom, Northwest)
- **Second player**: Assigned to Quadrant 2 (Empire, Northeast)
- **Third player**: Assigned to Quadrant 3 (Tribes, Southwest)
- **Fourth player**: Assigned to Quadrant 4 (IronLegion, Southeast)
- **Fifth+ players**: Assigned to whichever quadrant has the fewest players

### 2. Quadrant to Faction Mapping

Each quadrant is mapped to a specific faction in [GameManager.server.luau](src/server/GameManager.server.luau:227-232):

| Quadrant | Faction | Color | Position | Starting Resources |
|----------|---------|-------|----------|-------------------|
| 1 (NW) | Kingdom | Blue | (-250, 10, 250) | 600 Wood, 200 Stone, 900 Gold |
| 2 (NE) | Empire | Gold | (250, 10, 250) | 500 Wood, 250 Stone, 1000 Gold |
| 3 (SW) | Tribes | Green | (-250, 10, -250) | 700 Wood, 150 Stone, 800 Gold |
| 4 (SE) | IronLegion | Gray | (250, 10, -250) | 400 Wood, 400 Stone, 1000 Gold |

### 3. Estate Boundaries

Each estate has specific boundaries defined in [SpawnManager.getEstateBounds()](src/server/Managers/SpawnManager.luau:58-88):

- **Estate Size**: 400x400 studs per quadrant
- **Build Radius**: 200 studs from center
- **Neutral Zone**: 100 studs wide between each estate (no building allowed)

### 4. Territory Enforcement

[BuildingManager](src/server/Managers/BuildingManager.luau:35-44) enforces territory boundaries:

- Players can **only build** within their assigned quadrant
- Attempts to build outside the estate are **blocked**
- Keep is automatically spawned at the quadrant center
- Resource nodes spawn within 150 studs of the Keep

## Key Files Modified

1. **[SpawnManager.luau](src/server/Managers/SpawnManager.luau)** (NEW)
   - Assigns players to quadrants
   - Calculates spawn points per quadrant
   - Defines estate boundaries
   - Validates build positions

2. **[GameData.luau](src/shared/GameData/GameData.luau)**
   - Updated spawn points to match quadrant layout
   - Reduced BuildZoneRadius to 200 (matches 400x400 estate)
   - Added comments explaining the quadrant system

3. **[GameManager.server.luau](src/server/GameManager.server.luau)**
   - Uses SpawnManager for player assignment (line 224)
   - Maps quadrants to factions (line 227-232)
   - Passes quadrant spawn to initialization (line 253)
   - Cleans up quadrant assignment on player leave (line 125)

4. **[BuildingManager.luau](src/server/Managers/BuildingManager.luau)**
   - Added territory boundary checks (line 35-44)
   - Prevents building outside assigned estate

## Starting a Multiplayer Game

### Solo Testing
1. Start the game - you'll be assigned to Quadrant 1 (Kingdom)
2. Your Keep spawns at (-250, 10, 250)
3. You can only build within your 400x400 estate

### With Multiple Players
1. **Player 1** joins → Quadrant 1 (Northwest, Blue - Kingdom)
2. **Player 2** joins → Quadrant 2 (Northeast, Gold - Empire)
3. **Player 3** joins → Quadrant 3 (Southwest, Green - Tribes)
4. **Player 4** joins → Quadrant 4 (Southeast, Gray - IronLegion)

### Neutral Zone
- The center 100x100 stud area is **neutral** - no one can build there
- This provides natural separation between estates
- Future: Could be used for contested resources or PvP zones

## Testing Commands

Use admin commands to test the multiplayer setup:

```lua
/spawn 10          -- Spawn 10 peasants in your quadrant
/addres Wood 1000  -- Add resources to build
/econinfo          -- Check economy status
```

## Future Enhancements

### Recommended Additions:
1. **Visual Estate Boundaries**
   - Add semi-transparent walls or markers showing estate edges
   - Color-code boundaries by faction

2. **Minimap Territory Display**
   - Show quadrants on the minimap
   - Highlight your estate vs enemy estates

3. **Neutral Zone Resources**
   - Spawn contested resources in neutral areas
   - Encourage player interaction and conflict

4. **Team Alliances**
   - Allow players in adjacent quadrants to form alliances
   - Shared vision and trade routes

5. **Build Warning Messages**
   - Send client notification when trying to build out of bounds
   - Show visual indicator of build zone limits

## Configuration

To adjust the map layout, edit [SpawnManager.luau](src/server/Managers/SpawnManager.luau:13-20):

```lua
local MAP_CONFIG = {
    MapSize = 1000,           -- Total map size
    NeutralZoneWidth = 100,   -- Width of neutral area
    EstateSize = 400,         -- Size of each estate
    SpawnHeight = 10,         -- Y-level for spawning
}
```

## Debug Commands

Check quadrant assignments:
```lua
SpawnManager.printAssignments()  -- Shows which players are in which quadrants
SpawnManager.getPlayerQuadrant(userId)  -- Get a player's quadrant number
```

---

**Note**: The Keep auto-spawns on game start. There's no need to manually place it. Building placement now enforces estate boundaries automatically.
