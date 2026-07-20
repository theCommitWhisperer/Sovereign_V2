# Sovereign — Economy & Worker Design

_Branch: `economy-rework-v2`. This document is the source-of-truth for how the
economy, workers and the moment-to-moment gameplay loop are intended to behave._

## 1. What was broken

Peasants were being assigned to buildings but never turned into workers. Three
independent faults compounded:

1. **Arrival deadlock (the headline bug).** `MovementSystem` owns locomotion and
   declares a unit "arrived" at ~5 studs, clearing its move target. The old
   `WorkerManager` waited for a _tighter_ 3-stud tolerance before transforming.
   MovementSystem never delivered that, so the peasant parked 3–9 studs short of
   the entrance and the two systems ping-ponged forever. The worker never
   reached the "transform" step.
2. **Field mismatch.** `WorkerManager` read `buildingInfo.worker_type`, but the
   data defines `worker_job_type`. Every worker silently fell back to a generic
   `"Worker"` type instead of Farmer / Woodcutter / Smelter / etc.
3. **Production routing.** Only the three farms defined `production_time`, so
   every _other_ production building fell through to "walk to a world resource
   node" mode — and stalled if the map had no matching nodes.

## 2. Core loop (what happens now)

```
Peasant (idle, roaming near Keep)
        │  assigned (auto on placement, or + in the panel)
        ▼
Walk to BuildingEntrance ──► ON ARRIVAL: transform into job unit ──► Working
        │                                                              │
        │ (arrival is unified with MovementSystem; a stuck-timeout      │
        │  snap guarantees the worker always reaches the entrance)      │
        ▼                                                              ▼
   PASSIVE building                                         GATHER building
   walk to ProductionStation,                     walk to nearest ResourceNode,
   building produces on a timer                   harvest, walk back, DEPOSIT
   into its own storage                           (stored count rises on return)
        │                                                              │
        └──────────────► Haulers relay building storage ◄──────────────┘
                         → central storage (Keep / Storehouse / Granary)
                         and supply inputs → hungry processors
```

### Assignment (auto + manual)

- **Auto:** placing a production building claims the **nearest idle peasant**,
  which walks over and transforms. No micromanagement required.
- **Manual:** selecting the building opens the **Worker panel**. `+` staffs the
  nearest idle peasant (up to `worker_slots`); `−` releases one back to idle.
  Server actions `AssignWorker` / `UnassignWorker` are owner-checked.

### Production modes

| Mode | Buildings | Behaviour |
|------|-----------|-----------|
| **Passive** | Farms, Windmill/Water Mill, Bakery, Brewery, Smelter, Weaponsmith, Carpenter, Tannery, Siege Workshop, Monastery, Scriptorium | Once staffed, the building produces on a timer straight into its storage. Output scales with the number of staffed workers (capped at `worker_slots`). Production-chain buildings consume their input each tick. |
| **Gather** | Lumberjack, Stone Quarry, Iron Mine, Coal Mine | The worker walks out to the nearest matching `ResourceNode`, harvests up to its carry capacity, walks back and deposits — the stored count rises on return. If a map has no matching nodes, the gatherer falls back to passive output so the economy never stalls. |

### Hauling

Haulers are idle peasants temporarily borrowed to move goods:

- **Output haul:** when a producer's stored output ≥ 5, a hauler carries it to a
  storage building that can receive it (never back into the producer itself).
- **Supply haul (new):** when a processor is short of its input, a hauler pulls
  that input from a storage building that has it and delivers it to the
  processor — closing production chains like Iron Ore → Smelter → Weaponsmith.

## 3. Balance

All production tuning lives in one place: the `RESOURCE_TIERS` table in
`src/shared/GameData/BuildingsData.luau`. Editing a tier retunes every building
that makes that resource. `output` = units per passive tick (or hauled per node
visit); `interval` = seconds between passive ticks; `slots` = max workers.

| Resource | Output/tick | Interval (s) | Slots | Per-worker rate |
|----------|:-----------:|:------------:|:-----:|:---------------:|
| Wood | 2 | 4 | 3 | 0.50 /s |
| Stone | 2 | 5 | 3 | 0.40 /s |
| Food | 2 | 4 | 3 | 0.50 /s |
| Iron Ore | 1 | 5 | 3 | 0.20 /s |
| Coal | 1 | 5 | 3 | 0.20 /s |
| Flour | 2 | 5 | 2 | 0.40 /s |
| Bread | 2 | 5 | 2 | 0.40 /s |
| Ale | 2 | 6 | 2 | 0.33 /s |
| Iron Bars | 1 | 5 | 2 | 0.20 /s |
| Leather | 1 | 6 | 2 | 0.17 /s |
| Furniture | 1 | 6 | 2 | 0.17 /s |
| Weapons | 1 | 8 | 2 | 0.13 /s |
| Siege Equipment | 1 | 12 | 1 | 0.08 /s |
| Manuscripts | 1 | 8 | 1 | 0.13 /s |

Design intent: raw resources are the most abundant and support many slots so the
early game is fast; refined goods are gated by an input and a slower rate;
strategic goods (weapons, siege) are deliberately slow so a military economy is a
real investment. A fully-staffed building produces `output × slots ÷ interval`
per second (e.g. a 3-worker Lumberjack ≈ 1.5 wood/s; a 2-worker Weaponsmith
≈ 0.25 weapons/s, gated by iron bars).

## 4. Load-to-endgame gameplay flow

**Phase 0 — Spawn in.** The player places their **Keep** (0 cost). Five peasants
spawn and roam/gather around it. Starting resources (~500–700 Wood, ~150–250
Stone, ~800–1000 Gold, ~200–400 Food) fund the opening build order.

**Phase 1 — Food & wood first (first ~2 min).** Place a **farm** (Potato/Sheep/
Cow) and a **Lumberjack**. Each auto-claims the nearest peasant, who walks over,
transforms and starts producing. This is where the player first _sees_ the fixed
loop working: peasant → walks in → becomes a Farmer/Woodcutter → food and wood
climb. Add a **Granary** and **Storehouse** so haulers have somewhere to deliver.

**Phase 2 — Housing & population (next).** Build **Hovels/Clachans** to raise
housing capacity; population grows (each new peasant costs Food), giving more
bodies to staff buildings and haul. The player now balances mouths to feed
against workers gained.

**Phase 3 — Stone & the refined tier.** Add a **Stone Quarry**, then processors:
**Windmill → Bakery** (Food → Flour → Bread) and **Brewery** (→ Ale) which feeds
happiness via **Tavern/Inn**. Supply-haulers begin shuttling inputs between
buildings automatically. Happiness/tax systems start to matter.

**Phase 4 — Military economy.** **Iron Mine → Smelter → Weaponsmith** turns ore
into weapons; **Barracks/Archery Range/Stables** convert weapons + population into
soldiers. This chain is intentionally slow, so committing to war is a real
economic decision. **Armory** stores the output.

**Phase 5 — Defence & expansion.** Walls, **Towers** and **Arrow Towers**
(garrisoned by an assigned worker) fortify the settlement. **Market/Trading Post**
convert surplus to Gold; **Monastery/Scriptorium** produce Manuscripts and
popularity.

**Phase 6 — Endgame.** Victory is resolved by `VictoryConditionManager`
(destroy rival Keeps / survive / dominance). A mature economy with full worker
allocation, closed production chains and steady hauling sustains a standing army;
the loser's economy collapses as buildings go unstaffed and supply chains break.

## 5. Key files

| Concern | File |
|---------|------|
| Assignment, transform, production, hauling | `src/server/Managers/WorkerManager.luau` |
| Idle peasant behaviour | `src/server/Managers/IdlePeasantManager.luau` |
| Locomotion / pathfinding | `src/server/Systems/MovementSystem.luau` |
| Worker navigation points | `src/server/Systems/WorkerPointSystem.luau`, `BuildingManager.ensureWorkerPoints` |
| Building + economy data / balance | `src/shared/GameData/BuildingsData.luau` (`RESOURCE_TIERS`) |
| Production-chain inputs | `src/server/Managers/ProductionChainManager.luau` |
| Building classification | `src/shared/BuildingTypeHelper.luau` |
| Assignment UI | `src/ui/screens/HUD/WorkerAssignmentPanel.luau`, `HUD.luau` |

## 6. Tuning knobs

- **Movement/arrival:** `CONFIG` at the top of `WorkerManager.luau`
  (`MIN_ARRIVAL`, `GIVEUP_RADIUS`, `WALK_STUCK_TIMEOUT`, hauler cadence).
- **Economy balance:** `RESOURCE_TIERS` in `BuildingsData.luau`.
- **Carry capacity per job:** `carry_capacity` in `UnitsData.luau` (how much a
  gatherer hauls back before a return trip).
