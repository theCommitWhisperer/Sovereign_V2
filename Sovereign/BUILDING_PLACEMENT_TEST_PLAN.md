# Building Placement Test Plan
**Date:** 2025-12-27
**Tester:** User
**System:** Early Game Building & Economy

## Test Objective
Validate the core building placement workflow from game start through basic economy setup.

---

## Pre-Test Setup

1. **Launch Game**
   - Start from Main Menu
   - Click "Play" → Navigate to Lobby
   - Click "Ready" → Start game (solo, no AI)
   - Wait for spawn and HUD load

2. **Initial State Verification**
   - ✅ Player spawned at quadrant location
   - ✅ Keep should be pre-placed at spawn
   - ✅ Initial troops spawned near Keep
   - ✅ Resource display showing starting resources

---

## Phase 1: Initial Keep Verification

### What to Check
The Keep should already be placed at your spawn location (players start with a Keep).

### Steps
1. Look around spawn area
2. Verify Keep exists
3. Check Keep properties (if possible):
   - Owned by you
   - Functional (can click for UI)

### Expected Logs
```
[GameManager] <YourName> starting game...
[GameManager] Map loaded: <MapName> (XXXxXXX)
[GameManager] Assigned <YourName> to Quadrant X (<Faction>)
[SpawnManager] Spawning initial setup for <YourName>
[BuildingManager] Creating building: Keep
[BuildingManager] Building created: Keep
[GameManager] Character spawned and teleported <YourName> to quadrant X (tagged as King)
[GameManager] <YourName> spawned as <Faction>
```

### Success Criteria
- [ ] Keep visible at spawn location
- [ ] Keep has correct faction appearance
- [ ] No error logs during spawn
- [ ] Character teleported correctly

---

## Phase 2: Storehouse Placement

### Building Info
- **Name:** Storehouse
- **Cost:** Wood: 50, Stone: 30
- **Purpose:** Increases resource storage capacity
- **Placement:** Should snap to terrain, no special requirements

### Steps
1. Open build menu (check HUD for button/hotkey)
2. Select "Storehouse"
3. Enter placement mode
4. Move mouse to find valid placement location near Keep
5. Observe placement preview (green = valid, red = invalid)
6. Click to confirm placement
7. Verify building appears and resources are deducted

### Expected Logs
```
[GameManager] <YourName> wants to place: Storehouse
[BuildingManager] Creating building: Storehouse
[PlayerManager] Deducting resources for <YourName>
[BuildingManager] Building created: Storehouse
```

### Success Criteria
- [ ] Placement preview appears when selected
- [ ] Preview shows green on valid terrain
- [ ] Preview shows red on invalid terrain (too close to other buildings, water, etc.)
- [ ] Building places on click
- [ ] Resources deducted correctly
- [ ] Building appears in world with correct model
- [ ] No error logs

### Common Issues to Watch For
- Placement preview not appearing
- Buildings not snapping to ground
- Resources not deducting
- Building not appearing after click
- Multiple buildings spawning (double-click issue)

---

## Phase 3: Granary Placement

### Building Info
- **Name:** Granary
- **Cost:** Wood: 60, Stone: 40
- **Purpose:** Stores food resources
- **Placement:** Should snap to terrain

### Steps
1. Open build menu
2. Select "Granary"
3. Enter placement mode
4. Find valid location (preferably near future farms)
5. Click to confirm placement
6. Verify building appears and resources deducted

### Expected Logs
```
[GameManager] <YourName> wants to place: Granary
[BuildingManager] Creating building: Granary
[PlayerManager] Deducting resources for <YourName>
[BuildingManager] Building created: Granary
```

### Success Criteria
- [ ] Placement mode activates
- [ ] Preview works correctly
- [ ] Building places successfully
- [ ] Resources deducted
- [ ] No errors

---

## Phase 4: Wood Cutter Placement

### Building Info
- **Name:** Wood Cutter (or Lumber Camp)
- **Cost:** Wood: 40, Stone: 20
- **Purpose:** Gather wood from nearby trees
- **Placement:** Should be near forest/trees for efficiency

### Steps
1. Open build menu
2. Select "Wood Cutter" (or similar building)
3. Enter placement mode
4. Find location near trees/forest
5. Click to confirm
6. Verify placement and resource deduction

### Expected Logs
```
[GameManager] <YourName> wants to place: Wood Cutter
[BuildingManager] Creating building: Wood Cutter
[PlayerManager] Deducting resources for <YourName>
[BuildingManager] Building created: Wood Cutter
```

### Success Criteria
- [ ] Building places near resource nodes
- [ ] Resources deducted correctly
- [ ] Building functional (check if workers auto-assign)

---

## Phase 5: Resource Gathering Verification

### What to Check
After placing resource buildings, verify the economy starts working.

### Steps
1. Wait 10-30 seconds
2. Check resource display in HUD
3. Verify resources increasing (Wood from Wood Cutter, etc.)
4. Check if workers are assigned automatically or manually

### Expected Logs
```
[ResourceNode] Worker gathering from node
[PlayerManager] Adding resources to <YourName>
[EconomyDashboard] Resource update sent
```

### Success Criteria
- [ ] Resources increase over time
- [ ] Workers visible at buildings
- [ ] No resource gathering errors
- [ ] Economy dashboard updates

---

## Phase 6: Additional Buildings (Optional)

If time permits, test:
- **Stone Quarry** - Gathers stone
- **Farm** - Produces food
- **Barracks** - Trains military units
- **House** - Increases population cap

Follow same pattern: Select → Preview → Place → Verify

---

## How to Capture Logs

### Studio Output Window
1. Open Roblox Studio
2. Play solo test
3. View → Output window (Ctrl+Shift+X)
4. Copy all output after game start
5. Paste into `LOGS.md` file

### Log Format
Please capture logs in this format:

```md
# Game Start and Building Placement Logs
**Date:** 2025-12-27
**Test:** Early Game Building Placement

## Game Start Sequence
[Paste logs from game initialization here]

## Keep Spawn
[Paste logs showing Keep placement]

## Storehouse Placement
[Paste logs from Storehouse placement attempt]

## Granary Placement
[Paste logs from Granary placement]

## Wood Cutter Placement
[Paste logs from Wood Cutter placement]

## Resource Gathering
[Paste logs showing resource gathering over 30 seconds]

## Any Errors
[Paste any warning or error messages]
```

---

## What I'm Looking For

When you paste the logs, I'll analyze:

1. **Placement Flow**
   - Does StartPlacement → PlacementEnded → PlaceBuilding work?
   - Are resources deducted at the right time?
   - Any timing issues or race conditions?

2. **BuildingManager Integration**
   - Are buildings created successfully?
   - Do they have correct owners?
   - Are positions valid?

3. **Resource Management**
   - Resources deducted correctly?
   - Sufficient balance checks?
   - Any duplication bugs?

4. **Error Handling**
   - Invalid placements rejected gracefully?
   - Clear error messages?
   - No crashes or silent failures?

5. **Performance**
   - Any lag or stuttering during placement?
   - Excessive logging?
   - Memory leaks?

---

## Quick Reference: Expected Game Flow

```
1. Game Start
   ↓
2. Keep Auto-Placed
   ↓
3. Player Opens Build Menu
   ↓
4. Selects Building (e.g., Storehouse)
   ↓
5. Placement Preview Appears (Client)
   ↓
6. Player Moves Mouse (Preview Updates)
   ↓
7. Player Clicks (Requests Placement)
   ↓
8. Server Validates (Resources, Position)
   ↓
9. Server Deducts Resources
   ↓
10. Server Creates Building
   ↓
11. Building Appears in World
   ↓
12. Client Updates UI (Resource Display)
```

---

## Ready to Start!

**Next Steps:**
1. Launch the game in Roblox Studio
2. Follow Phase 1-5 above
3. Copy ALL output logs
4. Create `LOGS.md` file with the logs
5. Let me know when ready and I'll analyze!

**Tips:**
- Don't worry about length - paste everything
- Include timestamps if visible
- Note any visual bugs even if no error logs
- Take screenshots if helpful (describe what you see)

Let me know when you're ready to begin or if you have any questions!
