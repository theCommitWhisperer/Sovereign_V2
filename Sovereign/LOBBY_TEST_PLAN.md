# Lobby System Test Plan

This test plan provides a systematic approach to testing the Lobby screen functionality.

## Setup Complete

Strategic debug logging has been enabled for the following modules:
- **MainMenu** - Tracks navigation from main menu
- **Lobby** - Tracks all lobby client-side functionality
- **LobbyManager** - Tracks all server-side lobby operations
- **GameManager** - Tracks server event routing

## Test Flow

### Phase 1: Main Menu to Lobby Navigation

**Steps:**
1. Start the game in Roblox Studio
2. You should see the Main Menu with background and 3 buttons (Play, Settings, Exit)
3. Open the **Output Console** in Roblox Studio (View > Output)
4. Click the **Play** button

**Expected Console Output:**
```
ℹ️ INFO: [MainMenu] render() called. UI should be visible.
ℹ️ INFO: [MainMenu] PlayGameButton clicked - Navigating to lobby
ℹ️ INFO: [Lobby] Lobby:init() - Initializing lobby component
ℹ️ INFO: [Lobby] Initial lobby state created | mapCount: 4
ℹ️ INFO: [Lobby] Waiting for RemoteEvents
ℹ️ INFO: [Lobby] RemoteEvents found and connected
ℹ️ INFO: [Lobby] Sending JoinLobby request to server
ℹ️ INFO: [GameManager] Lobby event from <YourName>: JoinLobby
ℹ️ INFO: [LobbyManager] Created new lobby session: <SessionId>
ℹ️ INFO: [LobbyManager] Player joined lobby: <YourName>
ℹ️ INFO: [Lobby] Received LobbyEvent from server | action: LobbyStateUpdate
ℹ️ INFO: [Lobby] Lobby state updated from server
ℹ️ INFO: [Lobby] Players updated | playerCount: 1
```

**What to Check:**
- [ ] Main menu displays correctly with all 3 buttons
- [ ] Clicking Play navigates to lobby screen
- [ ] Console shows MainMenu navigation log
- [ ] Console shows Lobby initialization logs
- [ ] Console shows server receiving JoinLobby event
- [ ] Console shows LobbyManager adding player
- [ ] Console shows client receiving lobby state update

**If any logs are missing, report which ones and what happened instead.**

---

### Phase 2: Lobby UI Display

**Steps:**
1. After navigating to lobby, observe the UI layout

**Expected UI Elements:**
- **Left Panel:**
  - [ ] Map Preview (visual representation of selected map)
  - [ ] Map Selector dropdown/list (Default Map, Forest Lands, Desert Sands, Frozen Peaks)
  - [ ] Map Settings section

- **Right Panel:**
  - [ ] Player List showing your player
  - [ ] Add AI button
  - [ ] Game Settings section with multiple subsections:
    - Starting Resources (Gold, Food, Weapons, Resources, Troops)
    - Gameplay Modifiers
    - Pacing & Economy

- **Bottom Panel:**
  - [ ] Faction selector with 4 factions (Kingdom, Empire, Tribes, IronLegion)
  - [ ] Ready button
  - [ ] Back button

**What to Check:**
- [ ] All UI elements are visible and properly positioned
- [ ] No overlapping or missing panels
- [ ] Text is readable
- [ ] Map preview shows an image

**Report any missing or misaligned UI elements.**

---

### Phase 3: Map Selection

**Steps:**
1. Click on each map in the Map Selector list

**Expected Console Output (for each map click):**
```
ℹ️ INFO: [Lobby] Map selected: <MapName>
ℹ️ INFO: [GameManager] Lobby event from <YourName>: VoteSetting
ℹ️ INFO: [LobbyManager] <YourName> voted for selectedMap = <MapName>
ℹ️ INFO: [Lobby] Received LobbyEvent from server | action: LobbyStateUpdate
ℹ️ INFO: [Lobby] Lobby state updated from server
```

**What to Check:**
- [ ] Map Preview updates to show the selected map
- [ ] Selected map button highlights differently
- [ ] Console shows client sending map selection
- [ ] Console shows server processing vote
- [ ] Console shows client receiving state update

**Report any issues with map selection or missing logs.**

---

### Phase 4: Game Settings Modification

**Steps:**
1. Click on various settings toggles/dropdowns (Starting Gold, Game Speed, Victory Condition, etc.)
2. Cycle through different values

**Expected Console Output (for each setting change):**
```
ℹ️ INFO: [Lobby] Setting changed: <settingId> | <newValue>
ℹ️ INFO: [GameManager] Lobby event from <YourName>: VoteSetting
ℹ️ INFO: [LobbyManager] <YourName> voted for <settingId> = <newValue>
ℹ️ INFO: [Lobby] Received LobbyEvent from server | action: LobbyStateUpdate
```

**What to Check:**
- [ ] Settings controls are interactive
- [ ] Values change when clicked
- [ ] Console shows client sending setting changes
- [ ] Console shows server processing votes
- [ ] Settings persist when you change multiple values

**List which settings work and which don't respond.**

---

### Phase 5: Adding AI Players

**Steps:**
1. Click the **Add AI** button multiple times (up to 3 times to reach max 4 players)

**Expected Console Output (for each AI added):**
```
ℹ️ INFO: [Lobby] Add AI button clicked
ℹ️ INFO: [GameManager] Lobby event from <YourName>: AddAI
ℹ️ INFO: [LobbyManager] AI player added: AI_Opponent<N>
ℹ️ INFO: [Lobby] Received LobbyEvent from server | action: LobbyStateUpdate
ℹ️ INFO: [Lobby] Players updated | playerCount: <NewCount>
```

**What to Check:**
- [ ] AI players appear in the Player List
- [ ] AI players show correct names (AI_Opponent0, AI_Opponent1, etc.)
- [ ] AI players show as "Ready" automatically
- [ ] Maximum of 4 total players (human + AI) enforced
- [ ] Console shows proper AI creation flow

**Report how many AI can be added and any issues.**

---

### Phase 6: Faction Selection

**Steps:**
1. Click on each faction button (Kingdom, Empire, Tribes, IronLegion)
2. Try selecting a different faction
3. If you have AI players, observe if factions become unavailable

**Expected Console Output (for each faction selection):**
```
ℹ️ INFO: [Lobby] Faction selected: <FactionName>
ℹ️ INFO: [GameManager] Lobby event from <YourName>: SelectFaction
ℹ️ INFO: [LobbyManager] <YourName> selected faction: <FactionName>
ℹ️ INFO: [Lobby] Received LobbyEvent from server | action: LobbyStateUpdate
```

**What to Check:**
- [ ] Faction buttons highlight when selected
- [ ] Only one faction can be selected at a time
- [ ] Previously selected faction deselects when new one is chosen
- [ ] Faction shows next to your name in Player List
- [ ] Console shows faction selection flow

**Report faction selection behavior and any issues.**

---

### Phase 7: Ready System

**Steps:**
1. Click the **Ready** button
2. Observe the button text change
3. Click it again to unready

**Expected Console Output:**
```
ℹ️ INFO: [Lobby] Toggle ready clicked
ℹ️ INFO: [GameManager] Lobby event from <YourName>: ToggleReady
ℹ️ INFO: [LobbyManager] <YourName> ready status: true
ℹ️ INFO: [Lobby] Received LobbyEvent from server | action: LobbyStateUpdate
```

**What to Check:**
- [ ] Button text changes from "Ready" to "Not Ready"
- [ ] Button color changes when ready
- [ ] Your ready status shows in Player List
- [ ] Console shows ready toggle flow

---

### Phase 8: Ready Countdown (All Players Ready)

**Steps:**
1. Make sure all players (you + any AI) are ready
2. Observe what happens

**Expected Console Output:**
```
ℹ️ INFO: [LobbyManager] Starting countdown: 5 seconds
ℹ️ INFO: [Lobby] Received LobbyEvent from server | action: CountdownStarted
ℹ️ INFO: [Lobby] Countdown started: 5 | seconds
```

**What to Check:**
- [ ] Countdown display appears showing "Starting in X..."
- [ ] Countdown timer decreases each second (5, 4, 3, 2, 1)
- [ ] Console shows countdown start

---

### Phase 9: Countdown Cancellation

**Steps:**
1. While countdown is active, click Ready button to unready yourself
2. Observe countdown behavior

**Expected Console Output:**
```
ℹ️ INFO: [Lobby] Toggle ready clicked
ℹ️ INFO: [LobbyManager] Countdown cancelled
ℹ️ INFO: [Lobby] Received LobbyEvent from server | action: CountdownCancelled
ℹ️ INFO: [Lobby] Countdown cancelled
```

**What to Check:**
- [ ] Countdown display disappears
- [ ] Ready button shows "Ready" again
- [ ] Console shows countdown cancelled

---

### Phase 10: Back Navigation

**Steps:**
1. Click the **Back** button at the bottom of the lobby

**Expected Console Output:**
```
ℹ️ INFO: [Lobby] BackButton clicked - Navigating to mainMenu
ℹ️ INFO: [GameManager] Lobby event from <YourName>: LeaveLobby
ℹ️ INFO: [LobbyManager] Player left lobby: <YourName>
ℹ️ INFO: [MainMenu] render() called. UI should be visible.
```

**What to Check:**
- [ ] Returns to Main Menu
- [ ] Main Menu displays correctly
- [ ] Console shows leave lobby flow
- [ ] No errors when leaving lobby

---

## Summary Report Template

After completing all phases, please provide a summary:

### Working Features
- List all features that worked correctly

### Issues Found
- Describe each issue with:
  - Phase number
  - What you expected to happen
  - What actually happened
  - Console logs (copy/paste relevant logs)

### Missing Logs
- List any expected console logs that didn't appear

### UI Problems
- Describe any visual or layout issues

### Performance Notes
- Any lag, delays, or unusual behavior

---

## Next Steps

After completing this lobby test:
1. We'll address any issues found
2. Move on to testing the next system
3. Gradually enable debug logs for other modules as we test them

## Disabling Logs

When we're done testing the lobby, we can disable logs by setting channels to `false`:
- `MainMenu` channel in [MainMenu.luau:13](src/ui/screens/MainMenu/MainMenu.luau#L13)
- `Lobby` channel in [Lobby.luau:13](src/ui/screens/Lobby/Lobby.luau#L13)
- `LobbyManager` channel in [LobbyManager.luau:8](src/server/Managers/LobbyManager.luau#L8)
- `GameManager` channel in [GameManager.server.luau:13](src/server/GameManager.server.luau#L13)
