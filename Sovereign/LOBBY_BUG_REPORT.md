# Lobby System Bug Report

## Bug #1: Boolean Setting Concatenation Error ✅ FIXED

**Status:** FIXED
**Severity:** High (crashes setting changes)
**Date Found:** 2025-12-27
**Found During:** Phase 4 - Game Settings Modification testing

### Description
When toggling boolean settings (randomEvents, vikingRaids, showTutorial, legendsMode, unitMorale, abilityToTrade), the server crashes with:
```
attempt to concatenate string with boolean
```

### Location
[LobbyManager.luau:216](src/server/Managers/LobbyManager.luau#L216)

### Root Cause
The log statement attempted to concatenate a boolean value directly into a string:
```lua
LobbyDebug:info(player.Name .. " voted for " .. settingId .. " = " .. value)
```

When `value` is a boolean, Lua cannot concatenate it with `..` operator.

### Fix Applied
1. Changed log to use data parameter:
   ```lua
   LobbyDebug:info(player.Name .. " voted for " .. settingId, { value = value })
   ```

2. Updated function signature to accept any type:
   ```lua
   function LobbyManager.voteSetting(player: Player, settingId: string, value: any)
   ```

### Test Results After Fix
You should now be able to toggle all boolean settings without errors. Please re-test:
- [ ] randomEvents toggle
- [ ] vikingRaids toggle
- [ ] showTutorial toggle
- [ ] legendsMode toggle
- [ ] unitMorale toggle
- [ ] abilityToTrade toggle

Expected console output for boolean settings:
```
ℹ️ INFO: [Lobby] Setting changed: | <settingId>
ℹ️ INFO: [GameManager] Lobby event from <YourName>: VoteSetting
ℹ️ INFO: [LobbyManager] <YourName> voted for <settingId> | value: true (or false)
ℹ️ INFO: [Lobby] Received LobbyEvent from server | action: LobbyStateUpdate
```

---

## Bug #2: Confusing Boolean Toggle Display ✅ FIXED

**Status:** FIXED
**Severity:** Medium (UX issue, not functional bug)
**Date Found:** 2025-12-27
**Found During:** Phase 4 - Game Settings Modification testing (second run)

### Description
Boolean toggles displayed raw values (`true`/`false`) instead of user-friendly labels, making it confusing for players to understand the current setting state.

### Location
[Toggle.luau:90](src/ui/components/Toggle.luau#L90)

### Root Cause
The Toggle component displayed boolean values using `tostring(value)`, which outputs the literal text "true" or "false".

**Before:**
```
Random Events: < true >
Viking Raids: < false >
```

**Expected:**
```
Random Events: < Enabled >
Viking Raids: < Disabled >
```

### Fix Applied
Updated the ValueLabel to display user-friendly text for boolean values:
```lua
Text = " " .. (
    if typeof(value) == "boolean" then
        (if value then "Enabled" else "Disabled")
    else
        tostring(value)
) .. " ",
```

### Affected Settings
All boolean toggles now display properly:
- Random Events
- Viking Raids
- Show Tutorial
- Legends Mode
- Unit Morale
- Ability to Trade

### Test Results After Fix
Boolean settings should now display:
- `< Enabled >` when true
- `< Disabled >` when false
- Still toggleable with left/right arrows
- String values (like "Standard", "High") remain unchanged

---

## Bug #3: Boolean Toggle Requires Two Clicks ✅ FIXED

**Status:** FIXED
**Severity:** High (breaks user interaction)
**Date Found:** 2025-12-27
**Found During:** Phase 4 - Boolean toggle testing (third run)

### Description
Boolean toggles (especially "Show Tutorial") required **two clicks** to change from Disabled to Enabled. First click appeared to do nothing, second click finally changed the value.

### Location
[LobbyManager.luau:67-87](src/server/Managers/LobbyManager.luau#L67-L87)

### Root Cause
**Type mismatch** between client and server default values:

**Client (LobbySettings.luau):**
```lua
{ id = "showTutorial", defaultValue = true }  -- boolean
{ id = "randomEvents", defaultValue = true }  -- boolean
{ id = "vikingRaids", defaultValue = false }  -- boolean
```

**Server (LobbyManager.luau) - BEFORE FIX:**
```lua
showTutorial = "Disabled",  -- string!
randomEvents = "Enabled",   -- string!
vikingRaids = "Enabled",    -- string!
```

### Why This Caused Two Clicks

1. **First visit:** Server has `showTutorial = "Disabled"` (string)
2. **Client clicks:** Sends `false` (boolean) to server
3. **Voting logic:** Compares `"Disabled"` vs `false` - NOT EQUAL!
4. **Vote count:** `"Disabled"`: 0 votes, `false`: 1 vote
5. **Winner:** `false` wins, but visually looks the same as "Disabled"
6. **Second click:** Sends `true` (boolean)
7. **Now it works:** Boolean to boolean comparison

### Fix Applied
Changed server default values to use **booleans** and also synced all defaults with [LobbySettings.luau](src/ui/LobbySettings.luau):

```lua
Settings = {
    -- Boolean settings now use actual booleans
    unitMorale = true,        -- was "Enabled"
    abilityToTrade = true,    -- was "Enabled"
    randomEvents = true,      -- was "Enabled"
    legendsMode = false,      -- was "Disabled"
    vikingRaids = false,      -- was "Enabled" (also wrong default!)
    showTutorial = true,      -- was "Disabled" (wrong default!)

    -- Also fixed string defaults to match client
    startingTroops = "Standard",      -- was "Normal"
    startingGold = "Standard",        -- was "Normal"
    startingFood = "Standard",        -- was "Normal"
    startingWeapons = "Bronze",       -- was "Normal"
    startingResources = "Standard",   -- was "Normal"
    resourceDensity = "Standard",     -- was "Normal"
    victoryCondition = "Conquest",    -- was "Domination"
    peaceTime = "10 minutes",         -- was "5 Minutes"
    wildlifeHostility = "Peaceful",   -- was "Normal"
    honor = "Standard",               -- was "100"
    rank = "Knight",                  -- was "1"
}
```

### Impact
This fix also resolved:
- **Inconsistent defaults** between client and server
- **Viking Raids** defaulting to Enabled (should be Disabled per design)
- **Show Tutorial** defaulting to Disabled (should be Enabled per design)
- All string-based settings having wrong "Normal" values

### Test Results After Fix
All toggles should now:
- [ ] Work on **first click**
- [ ] Start with correct default values matching LobbySettings
- [ ] Sync properly between client and server
- [ ] Show consistent state immediately

---

## Summary from Initial Test Run

### ✅ Confirmed Working Features
1. **Main Menu Navigation** - All buttons functional
2. **Lobby Initialization** - Clean startup with proper event connections
3. **Map Selection** - All 4 maps selectable with state sync
4. **String-based Settings** - Working correctly:
   - startingGold, startingTroops, startingResources, startingFood, startingWeapons
   - resourceDensity, wildlifeHostility
   - victoryCondition, peaceTime, gameSpeed
   - honor, rank
5. **AI Player Management** - Successfully added AI_Opponent1
6. **Faction Selection** - All 4 factions (Kingdom, Empire, Tribes, IronLegion) working
7. **Ready System** - Countdown triggers correctly when all players ready
8. **Client-Server Communication** - Perfect round-trip timing (~30ms)

### 🔍 Features Still Need Testing
(After applying the fix above)
- [ ] Boolean setting toggles (6 settings)
- [ ] Multiple AI players (test adding up to 3 AI)
- [ ] Removing players/AI
- [ ] Countdown cancellation (unready while counting down)
- [ ] Back button navigation
- [ ] Full game start sequence
- [ ] Multiple human players (multiplayer test)
- [ ] Faction conflict (two players selecting same faction)

### 📊 Performance Notes
- Event round-trip time: ~30-35ms (excellent)
- No lag or delays observed
- State updates are instant and reliable
- No memory leaks detected during testing session

---

## Next Steps

1. **Re-run Phase 4** with the boolean settings fix applied
2. **Complete Phases 5-10** of the test plan
3. **Document any new issues** found
4. **Move to next system** once lobby is fully validated
