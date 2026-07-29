# Next session prompt

Paste the block below into a fresh session. Everything above the line is context
a cold start would not have; everything below is the actual work.

---

## Context

You are working on **Sovereign**, a mature Roblox RTS (Luau + Rojo + React) on
branch `sovereign-rework`. Read `Sovereign/docs/EconomyRedesign.md` first — it is
the design contract for the economy and worker systems, and its "Still open"
section lists known loose ends.

Recent work you are inheriting:

- **Workers**: three competing state machines were replaced by one engine,
  `server/Systems/WorkerService.luau`. `WorkerManager` and `IdlePeasantManager`
  are thin shims over it. 27 trades are data in `shared/GameData/WorkerRoles.luau`,
  resolving to four behaviours (Gatherer / Producer / Hauler / Server).
- **Economy**: six production chains now close end to end (previously one).
  `shared/GameData/BuildingSpec.luau` is the canonical accessor — read building
  config through it, never touch `BuildingsData` fields directly.
  `ResourcesData` is the single resource registry.
- **UI**: `HUD.luau` (1,989 lines) was deleted. `AdaptiveHUD` picks
  `DesktopShell` or `MobileShell`; `state/HUDStore.luau` owns all state and
  remote wiring; `Theme.luau` and `BuildingCatalog.luau` are the new design and
  data layers.
- **Verification**: `python3 Sovereign/tools/check_luau.py Sovereign/src` checks
  encoding, requires, Rojo collisions and Luau ambiguous syntax. Run it after
  every change. There are 244 unit tests; they run automatically on play.

Two environment facts that will otherwise waste your time:

1. **Rojo silently stops syncing.** If Studio behaves like your edits did not
   land, compare a file's byte count on disk against `Source` length in Studio
   before debugging anything else. Studio also will not apply script changes
   while playing.
2. **`execute_luau` runs in its own require cache.** Requiring a module from the
   command bar gives you a *fresh, uninitialised copy*, not the one the running
   game uses. Do not use it to inspect live singleton state — instrument the
   source instead.

---

## The work, in priority order

### 1. Playtest the economy and worker engine (highest value, do this first)

None of the worker or economy rework has ever been verified in play. It
typechecks and the unit tests pass, but no peasant has actually walked to a
tree. Start a match, place a Keep, and confirm:

- Peasants idle at the Keep, then get claimed when a building is placed
- Gatherers walk to nodes, harvest, and deposit
- The grain chain runs: farm produces grain, mill makes flour, bakery makes bread
- Haulers move goods between buildings and storage
- Workers are released when a building is destroyed by combat, not just by the
  UI delete button
- The staggered scheduler (40 workers/frame) holds up at high unit counts

Fix what you find. Trust the running game over the code.

### 2. Fix the population/tax interaction bug

When a peasant takes a job, `UnitType` is overwritten with the trade name, but
`PopulationManager.getCurrentPopulation` counts only `"Peasant"` and `"Ox"` — so
employed villagers stop counting as population. This predates the rework, but it
now matters much more, because tax income scales with population: staffing your
economy quietly shrinks your own tax base. Decide whether population should
count all civilians (probably yes) and fix it at the source.

### 3. Army selection UI

Selecting units still falls through to the old `UnitSelectionPanel`. Formations
and stances are a genuinely different shape from the building panel and were
deliberately left undesigned. Build it in `Theme`'s vocabulary, for both shells:
unit type breakdown, formation picker, stance picker, and group commands. Mobile
needs this in the thumb zone.

### 4. Multiplayer lobby

The lobby has AI opponents, ready-up, countdown, factions, spawn picking,
colours and setting votes. It has **no concept of** teams, kicking, spectating,
chat, or a host. Decide the matchmaking model first, because it changes
everything else: one lobby per Roblox server (simplest — Roblox's server list
becomes your matchmaking), multiple rooms per server, or teleport to reserved
servers. Then add teams (`FactionManager` already models relationships, so the
plumbing exists), host controls, and a defined path for late joiners.

### 5. Finish the UI migration

- Seven panels still reach for `RemoteEvents` directly instead of going through
  `HUDStore`: `TechTree`, `AbilityTreePanel`, `Policies`, `Menu`, `MiniMap`,
  `HeroAbilitiesPanel`, `UpgradePanel`. This breaks the "panels are
  presentational" rule the store exists to enforce.
- The legacy screens under `screens/HUD` still draw with `UIConfig`'s browns
  inside. The shells around them are new; their innards are not.
- `MiniMapEnhanced` is richer than the `MiniMap` actually in use — consolidate
  or delete.
- `StanceController` is a complete feature that was never wired to the HUD.

### 6. Rigs and animation

Console shows `Oillipheist` models have no Motor6D joints and no Bones — static
welded models, so they cannot walk. Units are skinned MeshPart rigs and stock
R6/R15 animations silently no-op; animation keys off an `AnimSet` attribute.
Audit which unit models are actually animatable.

### 7. Balance pass, once the loop demonstrably runs

Only after 1 and 2 are solid. The market glut curve, tax policies and popularity
sources were tuned by simulation, not play. Verify the four routes to wealth in
`EconomyDesign` section 3 are actually distinct, and that `Extortionate` tax is
survivable-but-risky rather than either free or suicidal.

## Working agreement

- Commit incrementally with real reasoning in the message; each commit should
  leave the game runnable.
- Comments explain **why**, not what.
- When a design decision is genuinely the user's (visual direction, game feel,
  scope), ask rather than guess — a wrong guess here has already cost a full
  rebuild of the HUD shells.
- Prefer verifying in Studio over reasoning about the code.
