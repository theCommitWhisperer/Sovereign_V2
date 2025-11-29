<!-- Copilot / AI agent instructions for the Sovereign_V2 codebase (expanded) -->

# Quick orientation
- **Project type:** Roblox game using Luau modules. Sources live under `src/` and are mapped to the DataModel by `default.project.json` (used with Rojo).
- **Runtime split:** `src/client` (runs in StarterPlayerScripts), `src/server` (ServerScriptService), `src/shared` (ReplicatedStorage.Shared). UI code lives in `src/ui`.

This repository separates code by runtime: server logic lives under `src/server`, client controllers and UI under `src/client` and `src/ui`, and shared data/config/helpers under `src/shared`. The `default.project.json` file maps these folders into Roblox's DataModel for Rojo builds — update it if you move files between services.

# Important entry points
- `src/server/GameManager.server.luau` — the main server coordinator. It:
  - requires and initializes `Managers/` and `Systems/` in a specific order;
  - creates `ReplicatedStorage.RemoteEvents` (a `RemoteEvents` folder with `GameEvent`, `GetStats`, and a `CheckVisibility` RemoteFunction);
  - wires `Players.PlayerAdded`/`PlayerRemoving` and contains the primary RPC dispatch in `GameEvent.OnServerEvent`.
- `src/client/init.client.luau` — client bootstrap. It requires client subsystems (Selection, Movement, Combat UI managers). Add new client controllers here so they're loaded on player join.
- `src/shared/DebugManager/init.luau` — centralized, channel-based logging. Channels are created with `DebugManager.createChannel("Name", enabled)` and the global `DebugManager.Enabled` flag toggles printing. Most channels are created disabled by default (`false`).

Read `GameManager.server.luau` first to learn server flow; it contains helper functions used across managers (e.g., `spawnInitialSetup`, `setupKingHealthMonitoring`) and the authoritative list of client action strings.

# Patterns & conventions (copy these exactly)
- Module placement: server-only modules go under `src/server/Managers` (domain logic) or `src/server/Systems` (simulation/periodic systems). Client modules go under `src/client` and UI under `src/ui`. Shared modules and data go under `src/shared`.
- Naming: prefer suffixes like `.client.luau` and `.server.luau` to show runtime intent.
- Manager lifecycle: managers generally implement `init()` (or sometimes `start`/`startUpdates`) which `GameManager.server.luau` calls. When adding a manager: add the file under `src/server/Managers`, `require` it in `GameManager.server.luau`, and call `init()` at the appropriate spot.
- Systems: systems are periodic or physics-like (e.g., `MovementSystem`, `WeatherSystem`, `WallSystem`) and are initialized similarly from `GameManager`.
- Data mapping: `default.project.json` determines where files go in the Roblox DataModel. Always update it when moving files between services.
- Network API: the server creates `RemoteEvents` under `ReplicatedStorage.RemoteEvents`. The canonical event names live in `GameManager.server.luau`. Clients send actions with `GameEvent:FireServer(action, data)`; the server uses `GameEvent:FireClient(player, eventName, payload)` to notify clients.
- Model metadata: game objects are annotated with `Instance:SetAttribute` and read using `GetAttribute`. Common attribute names:
  - `Owner` — owner UserId
  - `UnitType` — text identifier for unit/building type
  - `IsKing` — boolean indicating King character
  - `BuildingType` — for buildings
  - Unit models use the `Model.Name` as the `UnitId`

Many managers depend on these exact attribute names across code; keep them consistent.

# Common client <-> server actions (examples from `GameManager.server.luau`)
- `GetStats` — server responds with economy and combat summaries via `GetStats` remote event.
- `StartGame` — sets map via `MapManager.setMap`, configures `SpawnManager`, spawns initial units/resources, and loads the player's character.
- `StartPlacement` / `PlaceBuilding` — start placement and finalize building creation via `BuildingManager.createBuilding`. Server checks resources before approving placement.
- `MoveUnit` / `MoveUnitsInFormation` — movement commands; server sets attributes like `TargetPosition` and `IsMoving` on unit models so systems respond.
- `StartTraining` / `GetTrainingQueue` — training requests handled by `TrainingManager`.
- `DeleteBuilding` — building deletion with checks (e.g., protects `Keep`).
- `AttackTarget` / `SetStance` — combat commands delegated to `CombatManager`.
- `LeaveGame` — cleans up player's buildings and units and resets player data.

Use these action strings verbatim when wiring client UI to send/receive messages.

# Build / dev commands (how to run & test locally)
- Dependencies: managed with `wally` (see `wally.toml`). Install Lua deps with:

```powershell
# from project root (PowerShell)

```

- Tools: `rokit` manages tool versions (see `rokit.toml`). Typical build for Studio / local testing:

```powershell
# build Rojo place file
rojo build -o Sovereign.rbxlx
```

- Tests: TestEZ is included under `Packages/_Index/.../testez`. Specs live in `src/shared/GameData.spec/`. Running tests requires a TestEZ runner in Roblox (Rojo + Studio or a CI runner that supports TestEZ). If you need a small TestEZ runner script added, ask and I'll add an example.

# Key files & where to look (by intent)
- `src/server/GameManager.server.luau` — server flow, RPC dispatch, spawn logic, and event names.
- `src/server/Managers/*` — domain managers (PlayerManager, BuildingManager, UnitManager, CombatManager, WorkerManager, etc.). Look inside a manager file to learn its responsibilities and public API (`init`, `create`, `get`, etc.).
- `src/server/Systems/*` — simulation systems that run or tick (MovementSystem, SeasonSystem, WallSystem).
- `src/shared/GameData/*` — configuration-driven data (building/unit definitions, factions) used by managers rather than hard-coded values.
- `src/shared/DebugManager/init.luau` — logging: prefer `DebugManager.createChannel("Area", false)` for new channels and enable them only during debugging.
- `default.project.json` — mapping between code folders and Roblox services; update on file moves.

# Common tasks & examples
- Add a Manager:
  1. Create `src/server/Managers/NewThingManager.luau` implementing `init()` and exported functions.
  2. In `GameManager.server.luau` require it: `local NewThingManager = require(Managers.NewThingManager)` and call `NewThingManager.init()` at the appropriate spot.

- Add a System:
  1. Add file under `src/server/Systems/` exposing `init()` or `start()`.
  2. Require and initialize it from `GameManager.server.luau` where other systems are initialized.

- Add a client controller/UI:
  1. Add module under `src/client` or `src/ui`.
  2. Require it from `src/client/init.client.luau` so it loads for players.

- Add a network action:
  1. Pick an action string and add handling in `GameManager.server.luau`'s `GameEvent.OnServerEvent`.
  2. Add corresponding client-side FireServer call and client-side `GameEvent` listener for responses.

# Pitfalls & gotchas discovered in the codebase
- `DebugManager.Enabled` is global — enabling it will make all channels print; prefer enabling single channels with `createChannel("Area", true)`.
- `Players.CharacterAutoLoads` is set to `false` in `GameManager.server.luau`. Game code expects to call `player:LoadCharacter()` when the player starts the game.
- Many flows rely on attributes on Instances (owner checks using `GetAttribute("Owner")`) — missing or misnamed attributes will break ownership logic.
- `Model.Name` is used as `UnitId` in V2 — do not rename unit models arbitrarily.

# What reviewers/maintainers expect from patches
- Keep server-only code under `src/server` and shared types/configs in `src/shared` so the Rojo mapping remains correct.
- If you add runtime-facing APIs (RemoteEvents / RemoteFunctions), update `GameManager.server.luau` and include the exact event names used by clients.
- Use `DebugManager.createChannel("YourArea", false)` to create new channels — do not enable noisy channels by default.
- Respect attribute-based metadata conventions (Owner, UnitType, IsKing, etc.) when creating or mutating Models.


Checklist for PR reviewers:
- Add Manager: file in `src/server/Managers/`, required + init call in `GameManager.server.luau`.
- Add System: file in `src/server/Systems/`, required + init call in `GameManager.server.luau`.
- Move between services: update `default.project.json` before PR.

# Subsystem deep dives
Below are focused notes for commonly-edited subsystems to help an AI agent understand call sites, data shapes and where to find logic.

- FogOfWarManager (`src/server/Managers/FogOfWarManager`):
  - Responsibilities: track visibility per-player, provide `init(player)`, `startUpdates()`, `isUnitVisible(player, unit)`, and `cleanup(player)`.
  - Usage: `GameManager` calls `FogOfWarManager.init(player)` on `PlayerAdded` and `FogOfWarManager.startUpdates()` once server is ready. Clients call `CheckVisibility` RemoteFunction which delegates to `FogOfWarManager.isUnitVisible` / `isBuildingVisible`.
  - Data shapes: visibility checks expect an `Instance` (Model). Manager stores per-player visibility maps keyed by `UnitId` or building name.

- BuildingManager (`src/server/Managers/BuildingManager`):
  - Responsibilities: validate placement, instantiate building models, set attributes (`Owner`, `BuildingType`), and return the model. Functions commonly used: `createBuilding(player, buildingName, cframe, wallPieceType, manualRotation)`.
  - Integration points: called from `GameManager` on `PlaceBuilding` action. After creation, `WorkerManager` or `SpawnManager` may assign workers or resources; `PlayerManager`'s resource state is updated before/after creation.
  - Pitfalls: ensure cost checks use `PlayerManager.hasEnoughResources` and that `PlayerManager.deductResources` is called atomically around `createBuilding` to avoid resource desync.

- SpawnManager (`src/server/Managers/SpawnManager`):
  - Responsibilities: assign quadrant spawn points, maintain mapping from `userId` to spawn CFrame, and `setMapConfig(mapConfig)` to configure spawn geometry.
  - Usage: `GameManager` sets the map via `MapManager.setMap`, then calls `SpawnManager.setMapConfig(mapConfig)` and `SpawnManager.assignPlayerToQuadrant(userId)` to select a quadrant.
  - Data shapes: spawn points are `CFrame` values stored per-player; `SpawnManager.getPlayerSpawnPoint(userId)` returns the player's spawn.

- CombatManager (`src/server/Managers/CombatManager`):
  - Responsibilities: provide APIs for combat behavior: `init()`, `setTarget(attackerModel, targetModel)`, `getActiveCombatUnits()`, `setStance(unitModel, stance)`.
  - Integration: `GameManager.OnServerEvent` delegates `AttackTarget` and `SetStance` actions to this manager. Systems (e.g., MovementSystem) may clear `CombatTarget` attributes when moving.
  - Data shapes: Combat units are tables with stats (health, maxHealth, attackDamage, armor, morale). `getActiveCombatUnits()` returns a list of such entries for aggregation (used by `GetStats`).

- PlayerManager (`src/server/Managers/PlayerManager`):
  - Responsibilities: create/remove per-player data objects (`create(player)`, `get(player)`, `remove(player)`), track resources, list of buildings and units, and `hasEnoughResources(player, cost)` / `deductResources(player, cost)` helpers used across `GameManager` flows.
  - Usage: `GameManager` calls `PlayerManager.create(player)` on `PlayerAdded`. Many managers consult `PlayerManager.get(player)` for current state.
  - Data shapes: playerData has keys like `Resources` (table), `Buildings` (array of Models), `Units` (array of Models), `GameState`, `Faction`, `SpawnPoint`.

- Tests / TestEZ runner (suggested):
  - Quick runner example: add `test/TestRunner.server.luau` that requires `testez` and runs specs under `src/shared/GameData.spec/`.
  - Minimal runner snippet (Luau):

```lua
local TestEZ = require(game.ReplicatedStorage.Packages.testez)
local results = TestEZ.TestBootstrap:Run({
    Paths = {"src/shared/GameData.spec"}
})
print("Tests complete", results)
```

  - Note: running TestEZ usually requires a Roblox environment (Studio or CI runner). For CI, use Rojo to build a place and run TestEZ via a headless runner or a custom TestEZ runner script in ServerScriptService.

# When to ask for help
- If you cannot find where a RemoteEvent name is defined, open `src/server/GameManager.server.luau` and search for the `RemoteEvents` creation block.
- If unsure where a module should live (server vs shared vs client), open `default.project.json` and follow the mapping rules: server -> `src/server`, shared -> `src/shared`, client -> `src/client`/`src/ui`.

---
If you'd like, I can replace the original `copilot-instructions.md` with this expanded file, or fold individual sections into the existing file. Tell me which you prefer and I'll apply the change.
