# Lobby UI Redesign - Faction Selection Integration

## Summary
Moved faction selection from a separate bottom panel into the Player List for better UX and cleaner interface.

## Changes Made

### 1. Enhanced PlayerList Component
**File:** [PlayerList.luau](src/ui/screens/Lobby/PlayerList.luau)

**New Features:**
- Each player row now shows faction selector inline
- Player rows are now 60px tall with two sections:
  - **Top row:** Player name, ready status, remove button (for AI)
  - **Bottom row:** "Faction:" label + 4 faction buttons
- Local player is highlighted in gold color
- Faction buttons show visual states:
  - **Green** = Selected by this player
  - **Dark gray** = Taken by another player
  - **Medium gray** = Available
- Players can now set factions for AI opponents (not just their own)

**New Props:**
- `onSelectFaction` - Callback when faction is selected
- `localPlayerId` - To identify the local player for highlighting

**Visual Improvements:**
- Better spacing and padding
- Clear visual hierarchy
- Faction buttons are properly sized (23% width each)
- Dark semi-transparent background for each player card

### 2. Updated Lobby Component
**File:** [Lobby.luau](src/ui/screens/Lobby/Lobby.luau)

**Changes:**
- Removed standalone `FactionFrame` from bottom button area
- Removed `createFactionButton()` helper function
- Updated `selectFaction()` to accept `targetUserId` parameter
  - Can now select factions for any player (including AI)
  - Defaults to local player if no target specified
- Pass new props to PlayerList component
- Adjusted layout orders for remaining buttons (Countdown, Ready, Back)

### 3. Updated LobbyManager (Server)
**File:** [LobbyManager.luau](src/server/Managers/LobbyManager.luau)

**Changes:**
- Updated `selectFaction()` signature to accept optional `targetUserId`
- Can now set factions for AI players from the lobby
- Improved logging to show which player's faction was set

## Benefits

1. **Cleaner UI** - Less cluttered, faction selection is contextual to each player
2. **Better UX** - See at a glance which player has which faction
3. **AI Control** - Players can now assign factions to AI opponents
4. **Scalable** - Easier to see all players and their factions in one view
5. **Consistent** - All player info (name, ready status, faction) in one place

## Testing Checklist

- [ ] Faction selection works for local player
- [ ] Faction selection works for AI players
- [ ] Faction conflict prevention (can't select taken factions)
- [ ] Visual states update correctly (green/gray highlighting)
- [ ] Local player is highlighted in gold
- [ ] Ready status displays correctly
- [ ] AI remove button works
- [ ] Add AI button still functional
- [ ] Countdown and Ready buttons still work
- [ ] Back button navigation works

## Before & After

### Before:
```
┌────────────────────────────┐
│ Players                    │
│ • RiffetyRaff ✓            │
│ • AI_Opponent1 (AI) ✓  [X] │
└────────────────────────────┘

┌────────────────────────────┐
│ Faction:                   │
│ [Kingdom] [Empire]         │
│ [Tribes] [IronLegion]      │
└────────────────────────────┘
```

### After:
```
┌──────────────────────────────────────┐
│ Players                              │
│ ┌──────────────────────────────────┐ │
│ │ RiffetyRaff        ✓ Ready       │ │
│ │ Faction: [Kingdom] [Empire]      │ │
│ │          [Tribes] [IronLegion]   │ │
│ └──────────────────────────────────┘ │
│ ┌──────────────────────────────────┐ │
│ │ AI_Opponent1 (AI)  ✓ Ready   [✕] │ │
│ │ Faction: [Kingdom] [Empire]      │ │
│ │          [Tribes] [IronLegion]   │ │
│ └──────────────────────────────────┘ │
└──────────────────────────────────────┘
```

## Next Steps

After testing this redesign:
1. Continue with remaining lobby tests (countdown, game start)
2. Test multiplayer scenarios with multiple human players
3. Move on to testing other game systems
