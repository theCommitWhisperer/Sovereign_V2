# Map System Guide

## Overview

The game now supports multiple maps with different sizes, terrain types, and resource distributions. Maps can be selected when starting a game.

## How It Works

### 1. Character Spawning Fixed
- **Your character will NOT spawn when you join the server**
- Character only spawns when you click "Start Game"
- This prevents the character from appearing in the middle of the map before the game starts
- Character spawns directly at your assigned quadrant position

### 2. Available Maps

#### Classic Plains (Default)
- **Size**: 1000x1000 studs
- **Players**: 4
- **Quadrant Size**: 400x400 studs per estate
- **Neutral Zone**: 100 studs
- **Terrain**: Open plains with forests
- **Resources**: Balanced distribution

#### Large Continent
- **Size**: 1500x1500 studs
- **Players**: 4
- **Quadrant Size**: 600x600 studs per estate
- **Neutral Zone**: 150 studs
- **Terrain**: Mixed (mountains, lakes, rivers, forests)
- **Resources**: Abundant (30% more than Classic)
- **Features**: Central lake, mountains, rivers

#### Small Island
- **Size**: 700x700 studs
- **Players**: 4
- **Quadrant Size**: 280x280 studs per estate
- **Neutral Zone**: 70 studs
- **Terrain**: Compact island
- **Resources**: Limited (25% less than Classic)
- **Features**: Central lake, quick matches

#### Barren Wasteland
- **Size**: 1000x1000 studs
- **Players**: 4
- **Quadrant Size**: 400x400 studs per estate
- **Neutral Zone**: 100 studs
- **Terrain**: Desert
- **Resources**: Wood scarce (60% less), Stone abundant (33% more)
- **Features**: Central oasis, challenging survival gameplay

#### Duel Arena
- **Size**: 600x600 studs
- **Players**: 2 (head-to-head)
- **Quadrant Size**: 250x250 studs per estate
- **Neutral Zone**: 50 studs
- **Terrain**: Arena-style
- **Resources**: Moderate
- **Features**: Focused 1v1 combat

#### Highland Fortress
- **Size**: 1200x1200 studs
- **Players**: 4
- **Quadrant Size**: 480x480 studs per estate
- **Neutral Zone**: 120 studs
- **Terrain**: Mountains
- **Resources**: Stone-rich (50% more), Wood-poor (40% less), Iron-rich (87% more)
- **Features**: Elevated positions, strategic highlands

## How to Select a Map

### Option 1: Default (No Selection)
If you don't specify a map, the game will use **Classic Plains**.

### Option 2: Via Menu (Future Enhancement)
A map selection menu will be added to the Start Game screen where you can choose from available maps.

### Option 3: Via Code (For Testing)
In the Menu.luau file, you can pass the map name when starting the game:

```lua
gameEvent:FireServer("StartGame", {
    vikingRaids = vikingRaidsEnabled,
    peaceTime = peaceTime,
    map = "LargeContinent" -- Add this line with desired map name
})
```

Available map names:
- `"ClassicPlains"` (default)
- `"LargeContinent"`
- `"SmallIsland"`
- `"BarrenWasteland"`
- `"DuelArena"`
- `"HighlandFortress"`

## Map Configuration Structure

Each map is defined in [MapData.luau](src/shared/GameData/MapData.luau) with the following properties:

```lua
{
    Name = "Display Name",
    Description = "Description text",
    Size = 1000, -- Map size in studs
    TerrainType = "Plains", -- Visual/gameplay type
    MaxPlayers = 4, -- Number of player quadrants
    QuadrantSize = 400, -- Estate size per player
    NeutralZoneWidth = 100, -- Buffer between estates
    SpawnHeight = 10, -- Y-level for spawning
    ResourceDensity = {
        Wood = 20,  -- Number of resource nodes
        Stone = 15,
        Food = 10,
        Iron_Ore = 8,
    },
    Features = {
        HasCentralLake = true,
        HasMountains = true,
        HasForests = true,
        HasRivers = true,
    },
}
```

## Creating Custom Maps

To add your own map:

### 1. Define the Map in MapData.luau

Open [MapData.luau](src/shared/GameData/MapData.luau) and add a new entry to `MapData.Maps`:

```lua
["YourMapName"] = {
    Name = "Your Map Display Name",
    Description = "Description of your map",
    Size = 1000, -- Adjust size
    TerrainType = "Custom",
    MaxPlayers = 4,
    QuadrantSize = 400,
    NeutralZoneWidth = 100,
    SpawnHeight = 10,
    ResourceDensity = {
        Wood = 20,
        Stone = 15,
        Food = 10,
        Iron_Ore = 8,
    },
    Features = {
        HasCentralLake = false,
        HasMountains = false,
        HasForests = true,
        HasRivers = false,
    },
} :: MapConfig,
```

### 2. Map is Automatically Available

Once defined in MapData, your map is automatically:
- Detected by MapManager
- Available for selection
- Configures SpawnManager with correct quadrants
- Distributes resources according to density settings

## Technical Details

### Files Involved

1. **[MapData.luau](src/shared/GameData/MapData.luau)**
   - Defines all map configurations
   - Shared between client and server

2. **[MapManager.luau](src/server/Managers/MapManager.luau)**
   - Handles map selection
   - Tracks active map
   - Provides map configuration to other systems

3. **[SpawnManager.luau](src/server/Managers/SpawnManager.luau)**
   - Uses map configuration for quadrant calculations
   - Dynamically adjusts spawn points based on map size
   - Enforces estate boundaries

4. **[GameManager.server.luau](src/server/GameManager.server.luau)**
   - Sets the active map on game start
   - Configures SpawnManager with map data
   - Spawns character at quadrant position

### Character Spawning Flow

1. **Player Joins Server**
   - `CharacterAutoLoads = false` (prevents spawn)
   - PlayerData created
   - Player sees menu

2. **Player Clicks "Start Game"**
   - Map is loaded (default or selected)
   - SpawnManager gets map configuration
   - Player assigned to quadrant
   - Character spawns via `player:LoadCharacter()`
   - Character teleported to quadrant spawn point

3. **Game Begins**
   - Keep spawns at quadrant center
   - Resources spawn around Keep
   - Camera activates at player position

## Map Size Recommendations

- **Small (600-800)**: Quick games, 2-4 players
- **Medium (900-1200)**: Standard games, 4 players
- **Large (1300-1600)**: Epic games, longer matches

## Quadrant Calculation

The system automatically calculates spawn points based on map size:

```
Quadrant 1 (NW): (-offset, height, offset)
Quadrant 2 (NE): (offset, height, offset)
Quadrant 3 (SW): (-offset, height, -offset)
Quadrant 4 (SE): (offset, height, -offset)

Where:
offset = (QuadrantSize / 2) + (NeutralZoneWidth / 2)
```

### Example: Classic Plains
- QuadrantSize: 400
- NeutralZoneWidth: 100
- offset = (400/2) + (100/2) = 250

Spawns:
- Q1 (NW): (-250, 10, 250)
- Q2 (NE): (250, 10, 250)
- Q3 (SW): (-250, 10, -250)
- Q4 (SE): (250, 10, -250)

## Testing Maps

Use admin commands to test different scenarios:

```
/econinfo - Check economy status
/spawn 10 - Spawn peasants in your quadrant
/addres Wood 1000 - Add resources
```

The map size and resource density will affect gameplay balance!

## Future Enhancements

Planned features:
1. Map selection UI in the menu
2. Map preview/minimap
3. Random map selection option
4. Custom terrain generation per map type
5. Map-specific victory conditions
6. Procedurally generated maps

---

**Note**: Character spawning is now controlled - you won't see your character until you start the game! The quadrant system is fully integrated with the map system.
