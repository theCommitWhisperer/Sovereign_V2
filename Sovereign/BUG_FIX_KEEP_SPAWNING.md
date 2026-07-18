# Bug Fix: Keep Placement Crash
**Date:** 2025-12-27
**Status:** ✅ FIXED
**Severity:** Critical (Game-breaking)

## Bug Report

### Error Message
```
ServerScriptService.Server.Managers.BuildingManager:269: attempt to index nil with 'Position'
Stack Begin
Script 'ServerScriptService.Server.Managers.BuildingManager', Line 269 - function createBuilding
Script 'ServerScriptService.Server.GameManager', Line 714
Stack End
```

### What Happened
1. Player placed Keep (FREE, as intended)
2. Keep building was created successfully
3. Pathfinding obstacle was added
4. **CRASH:** BuildingManager tried to access `building.PrimaryPart.Position`
5. `building.PrimaryPart` was `nil` → crash
6. Peasants never spawned (code never reached GameManager spawn logic)

### Root Cause

**OLD CODE** in BuildingManager.luau (lines 267-273) was trying to spawn a peasant when the Keep was placed:

```lua
-- OLD CODE (REMOVED)
-- Spawn 1 starting peasant when Keep is placed (gives player ability to start economy)
local UnitManager = require(script.Parent.UnitManager)
local keepPos = building.PrimaryPart.Position  -- ❌ CRASH: PrimaryPart is nil
local spawnOffset = Vector3.new(15, 0, 0)
local spawnPos = keepPos + spawnOffset
UnitManager.createUnit("Peasant", actualPlayer.UserId, spawnPos, playerData.Faction or "Kingdom")
BuildingDebug:info("Spawned 1 starting peasant for " .. actualPlayer.Name .. " after Keep placement")
```

**Why it crashed:**
- The building model was created but `PrimaryPart` wasn't set yet
- Trying to access `.Position` on `nil` caused the crash

**Conflict:**
- This old code conflicted with our new SpawnPointSystem implementation in GameManager
- We're now spawning 3 peasants using SpawnPointSystem, not 1 peasant here

### The Fix

**File:** `src/server/Managers/BuildingManager.luau`

**Changed lines 262-268:**

```lua
-- BEFORE (Crashed)
-- Special case for Keep
local playerData = PlayerManager.get(actualPlayer)
if playerData and buildingName == "Keep" then
	playerData.Keep = building

	-- Spawn 1 starting peasant when Keep is placed (gives player ability to start economy)
	local UnitManager = require(script.Parent.UnitManager)
	local keepPos = building.PrimaryPart.Position  -- ❌ CRASH
	local spawnOffset = Vector3.new(15, 0, 0)
	local spawnPos = keepPos + spawnOffset
	UnitManager.createUnit("Peasant", actualPlayer.UserId, spawnPos, playerData.Faction or "Kingdom")
	BuildingDebug:info("Spawned 1 starting peasant for " .. actualPlayer.Name .. " after Keep placement")
end
```

```lua
-- AFTER (Fixed)
-- Special case for Keep
local playerData = PlayerManager.get(actualPlayer)
if playerData and buildingName == "Keep" then
	playerData.Keep = building
	channel:info("Keep registered for " .. actualPlayer.Name)
	-- Note: Peasant spawning is now handled by GameManager using SpawnPointSystem
end
```

**What Changed:**
1. ✅ Removed old peasant spawning code
2. ✅ Kept `playerData.Keep = building` (needed for tracking)
3. ✅ Added note explaining new spawn location
4. ✅ Fixed `BuildingDebug` → `channel` (correct debug variable name)

### Expected Behavior After Fix

**Logs should now show:**

```
[GameManager] RiffetyRaff wants to place: Keep
[GameManager] Approving FREE Keep placement for RiffetyRaff (first building)
[GameManager] RiffetyRaff placing building: Keep
[GameManager] Placing FREE Keep for RiffetyRaff (first building)
[BuildingManager] Keep registered for RiffetyRaff
[PathfindingIntegration] Added obstacle: Keep_XXXXXX (grid version: 1)
[GameManager] Keep placed by RiffetyRaff, spawning initial peasants
[GameManager] Spawned peasant 1/3 for RiffetyRaff
[GameManager] Spawned peasant 2/3 for RiffetyRaff
[GameManager] Spawned peasant 3/3 for RiffetyRaff
[GameManager] Spawned 3 peasants around Keep for RiffetyRaff
```

### Testing Checklist

After this fix, verify:
- [ ] Keep places without crashing
- [ ] 3 peasants spawn in circle around Keep
- [ ] Peasants have correct faction
- [ ] Peasants are owned by player
- [ ] No error messages in output
- [ ] Other buildings can now be placed

### Build Status

✅ **Project builds successfully:**
```
Building project 'Sovereign_V2'
Built project to Sovereign.rbxl
```

No errors or warnings.

---

## Summary

**Problem:** Old peasant spawning code in BuildingManager crashed because `building.PrimaryPart` was nil.

**Solution:** Removed old code, peasant spawning now handled by GameManager with SpawnPointSystem.

**Result:** Keep placement should work correctly with 3 peasants spawning using the new pattern-based system.

**Status:** ✅ FIXED - Ready for testing!
