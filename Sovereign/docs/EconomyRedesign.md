# Sovereign — Economy & Worker Redesign

Target: the Stronghold Legends loop — a kingdom that feels *alive*, with many
buildings and many worker trades, but **one** system underneath running all of
them, and several genuinely different routes to serious wealth.

This document is the contract. Code should match it; where they disagree, the
code is wrong.

---

## 1. Why the current system fights itself

Findings from the audit (file:line evidence in commit history):

| Problem | Detail |
|---|---|
| Three competing state machines | `WorkerTask.state`, `HaulerTask.state`, and `IdlePeasantManager.IdleBehavior` all independently decide what a unit is doing. Four separate predicates (`isUnitBusy`, `isAssignableCivilian`, `IsWorking`, `IsIdle`) answer the same question with different answers. |
| A unit can be in limbo | `releaseFromWork` clears `IsWorking` but never sets `IsIdle` or re-adds to the idle pool — a fourth, unnamed state. |
| Workers leak on building death | `BuildingManager`'s `Destroying` handler only unregisters the pathfinding obstacle. Only the *UI delete* path releases workers, so a building destroyed by combat leaves its worker invisible, non-colliding, flagged not-working, and never returned to the pool. |
| Authored balance numbers are dead | A load-time loop in `BuildingsData` overwrites `production_rate`, `production_time`, `production_output` and `worker_slots` for every producing building from a central `RESOURCE_TIERS` table. Every per-building number authored in the file body is silently clobbered before any system reads it. |
| Config has 3 pairs of overlapping fields | `produces_resource`/`production_rate` vs `production_time`/`production_output`; `worker_job_type` vs `worker_type` (never set by anything); `requires_worker` vs `worker_slots`. |
| `worker_points` / `storage_points` are write-only | Declared on ~30 buildings, read by nothing. `WorkerPointSystem` does its own `FindFirstChild` by hardcoded string instead. |
| Population is counted two ways | A cached number *and* a live scan of unit instances, refreshed on different clocks. |
| Two growth loops race | `PopulationManager.startLoop` (60s) and `PopulationSystem.startLoop` (10s) both drive `tryGrowPopulation`, with separate bookkeeping. |
| Virtualising a worker deletes population | Only one physical NPC exists per building; extra workers are `:Destroy()`ed and counted in a table. Nothing calls `PlayerManager.removeUnit`, and population is derived by scanning live instances — so **staffing a building shrinks your recorded population**. |
| Only one production chain actually works | Iron_Ore → Iron_Bars → Weapons. |
| The grain chain is broken | Windmill consumes **Food** to make Flour. Bakery and Brewery also consume **Food** — not Flour. Flour is produced by two buildings and consumed by none. |
| Six resources can never reach the player | `PlayerManager.addResources` only credits a resource already present in the `Resources` table. Flour, Leather, Furniture, Coal, Manuscripts and Siege_Equipment are never seeded, so they are silently dropped with no error. |
| Revolts cannot happen | `RevoltSystem` is never `init`'d or started, so `RevoltManager.update(player)` is never called. |
| Building food consumption is dead | `ConsumptionManager` gates on a `HasWorker` attribute that nothing in the repo ever sets. |
| Per-frame O(buildings) scans | Haulers linear-scan `Workspace.Buildings:GetChildren()` **per hauler, per frame** while walking. |

The through-line: the game has *more systems than it has wiring*. The redesign
adds almost no new concepts — it deletes duplicate ones and connects what is
already there.

---

## 2. The target loop

```
        Housing ──> population cap
                        │
    Food + Popularity ──┴──> peasants arrive at the Keep campfire
                                        │
                                  LABOUR POOL
                                        │
                    buildings claim workers from the pool
                                        │
                ┌───────────────────────┼───────────────────────┐
            gatherers               producers                servers
          (wood/stone/ore)      (chains: flour→bread)   (ale, faith, taxes)
                └───────────────────────┼───────────────────────┘
                                        │
                                   goods + food
                                        │
                    ┌───────────────────┴──────────────────┐
              consumption                                market / caravans
             (rations, ale, faith)                              │
                    │                                           │
                POPULARITY  ◄── taxes drain it ──►  GOLD  ◄──────┘
```

**Popularity is the real currency.** Gold is downstream of it. You *spend*
popularity by taxing, and you *buy* popularity with food rations, ale, faith
and low crowding. Everything interesting in the economy is a trade against that
one budget.

---

## 3. Four routes to wealth (each with a real cost)

Kevin's requirement: "ways for the user to make a ton of money, of course with
some tradeoffs." Four distinct strategies, deliberately not equally easy.

### 3.1 The Tax State — wide and loyal
Income scales with **population**, so this rewards building tall housing and
keeping popularity high enough to survive a punishing rate.

- `income = population × rate × popularityMultiplier`
- High Tax (30%) carries a −30 popularity hit; Extortionate (45%) carries −50.
- You offset it with Double Rations (+20), ale (+up to 20), faith (+up to 15).
- **Cost:** every popularity source consumes food, workers or buildings. A
  fully-buffered tax state spends roughly a third of its labour on keeping
  people happy rather than producing.
- **Failure mode:** popularity under 30 halves income; under 15 it quarters;
  at 0 nobody pays and the revolt timer starts.

### 3.2 Industry — long chains, high margin
Raw goods are nearly worthless; finished goods are where the money is.

```
Iron_Ore ──> Iron_Bars ──> Weapons        (2.0 → 4.0 → 8.0 gold)
Grain ─────> Flour ─────> Bread           (0.5 → 1.2 → 2.4)
Grain ─────> Ale                          (→ 3.0, also feeds popularity)
Hide ──────> Leather ───> Furniture       (1.0 → 2.5 → 6.0)
Vellum ────> Manuscripts                  (→ 10.0, the luxury good)
```

- **Cost:** each stage needs its own building *and* its own workers. A full
  weapons chain is 3 buildings and 6 workers producing nothing edible.
- **Cost:** capital. Chain buildings are the expensive ones.

### 3.3 The Market — with a glut penalty (new)
Selling floods the market. Each sale pushes that good's price down; it recovers
over time.

- Price floor 40% of base, ceiling 160%.
- Each unit sold moves price by `−0.6%`, recovering `+2%` of the gap per 30s tick.
- **This is the key anti-exploit and the reason diversification pays.** Dumping
  1000 weapons earns far less than 1000 weapons at base price. Running three
  chains into three markets beats running one chain at four times the volume.

### 3.4 Caravans & Estates — risk and territory
Already implemented; retuned so the risky routes are actually worth it.

- Limerick: 120g / 120s at 20% loss risk → expected 96g.
- **Cost:** up-front goods, and a caravan in transit is capital you can't spend.
- Estates yield supply carts but must be **held**, which splits your army.

---

## 4. Worker model — keep the flavour, collapse the logic

Kevin wants the kingdom to feel alive, so **all ~24 trade names stay**. What
changes is that they stop being *code* and become *data*.

Every trade resolves to one of four **behaviours**:

| Behaviour | What it does | Trades using it |
|---|---|---|
| `Gatherer` | Walks to a world ResourceNode, harvests, carries home | Woodcutter, Stonemason, Miner, Farmer, Fisherman, Hunter |
| `Producer` | Stands at a station, converts inputs → outputs on a cycle | Smelter, Blacksmith, Baker, Brewer, Miller, Tanner, Carpenter, Scribe, Fletcher |
| `Hauler` | Moves goods between buildings and storage | Hauler, Ox driver |
| `Server` | Provides a non-material effect (popularity, faith, tax) | Innkeeper, Priest, Monk, Administrator, Merchant, Trader |

A trade is defined purely as data:

```lua
WorkerRoles.Baker = {
    displayName = "Baker",
    behaviour   = "Producer",
    rigSet      = "Peasant_Male",   -- resolved by the existing getUnitModel
    animSet     = "Craft",
}
```

Adding a trade = adding a table entry. No new branches anywhere.

### 4.1 One state machine

```
      ┌──────────────────────────────────────────────┐
      ▼                                              │
   Idle ──claim──> Travelling ──arrive──> Working ───┤
      ▲                  │                    │      │
      │                  │                 (carrying)│
      │                  │                    ▼      │
      └───── release ────┴──────────── Hauling ──────┘
```

Five states, one table, one owner. `Idle` is a real state in the machine, not a
separate manager — this removes the limbo case entirely.

Every transition goes through one function so that attributes, the idle pool,
and the task table can never disagree:

```lua
WorkerService.setState(worker: Model, next: WorkerState, ctx: TransitionContext?)
```

### 4.2 Every worker is real
Virtual workers are removed. A staffed building has as many NPCs as it has
filled slots, and population is a single authoritative count maintained by
`PlayerManager` — not derived by scanning instances. This kills the
"staffing a building shrinks your population" bug at the root, and makes the
building visibly busy, which is most of the *alive* feeling.

Cost control comes from budgeting instead: workers tick on a **staggered
scheduler** (N per frame, round-robin) rather than every worker every frame.

### 4.3 Cleanup is owned by one signal
`WorkerService` subscribes to the building's `Destroying` signal. Any cause of
death — combat, siege, UI delete, cleanup — releases workers identically.

---

## 5. Config schema

One shape, no overlapping fields. The tier table becomes **defaults you may
override**, not a clobber:

```lua
BuildingsData.Bakery = {
    model_asset_name = "Bakery",
    category  = "Food",
    cost      = { Wood = 40, Gold = 10 },
    build_time = 20,

    work = {
        role    = "Baker",       -- selects behaviour + rig from WorkerRoles
        slots   = 2,
        cycle   = 5,             -- seconds per production cycle
        inputs  = { Flour = 2 }, -- consumed per cycle
        outputs = { Bread = 3 }, -- produced per cycle
    },

    storage  = { Flour = 50, Bread = 50 },
    housing  = nil,
    upkeep   = { Gold = 2 },
}
```

Removed as dead: `worker_type`, `worker_points`, `storage_points`,
`produces_resource`/`production_rate` (superseded by `work.inputs/outputs`),
`requires_worker` (implied by `work.slots > 0`).

A migration shim keeps the old field names readable for one release so nothing
breaks mid-refactor.

---

## 6. Resource registry

All resources are declared in **one** place and auto-seeded into every player's
`Resources` table, so `addResources` can never silently drop a good again.

| Tier | Resources |
|---|---|
| Raw | Wood, Stone, Iron_Ore, Coal, Grain, Hide, Food, Fish |
| Refined | Iron_Bars, Flour, Leather, Vellum |
| Finished | Weapons, Bread, Ale, Furniture, Manuscripts, Siege_Equipment |
| Abstract | Gold, Honor, Glory |

---

## 7. Bugs fixed as part of this work

1. Duplicate population growth loops → `PopulationSystem` owns growth; `PopulationManager` becomes pure state.
2. Virtual workers deleting population → virtual workers removed entirely.
3. Worker leak on building destruction → single `Destroying` subscription.
4. Grain chain → Windmill consumes Grain, Bakery consumes Flour, Brewery consumes Grain.
5. Six resources silently dropped → central resource registry seeds all.
6. `RevoltSystem` never started → wired into `GameManager`.
7. `HasWorker` never set → building consumption reads real staffing.
8. Per-frame O(buildings) hauler scans → cached per-owner building index, rebuilt on change.
9. Authored balance numbers clobbered → tiers become defaults, not overrides.

---

## 8. UI — one adaptive HUD

Not two codebases. One component tree, one state store, a `Platform` module
that reports the device and a set of layout tokens that everything reads.

```lua
Platform.kind          -- "Desktop" | "Mobile" | "Console"
Platform.pointer       -- "Mouse" | "Touch" | "Gamepad"
Platform.tokens        -- { hitTarget, fontScale, padding, panelWidth, ... }
Platform.safeArea      -- notch / gesture-bar insets
```

### Design rules
- **Touch targets ≥ 44px** on mobile; desktop may go to 28px.
- **Thumb zones.** On mobile, primary actions sit in the lower third — the top
  bar is display-only. Nothing interactive within 60px of the top edge.
- **Progressive disclosure.** Desktop shows the building menu as a wide grid;
  mobile uses category → drawer, one level at a time.
- **Selection-driven bottom bar.** What's selected determines the action bar.
  This replaces the desktop habit of having every panel visible at once.
- **No hover-only affordances.** Anything that only appears on hover must have
  a tap equivalent (long-press for tooltips).
- **Camera gestures.** Mobile: one-finger drag = pan, pinch = zoom, two-finger
  twist = rotate. Desktop keeps edge-scroll + WASD + wheel.

### HUD decomposition
`HUD.luau` is 1,989 lines holding ~30 pieces of state in one class component.
It splits into:

```
ui/state/HUDStore.luau        -- all game state, one subscribe point
ui/Platform.luau              -- device + tokens
ui/layouts/DesktopShell.luau  -- chrome only
ui/layouts/MobileShell.luau   -- chrome only
ui/panels/*.luau              -- presentational, platform-agnostic
```

Panels receive props and render; they never reach into remotes. Both shells
mount the same panels in different frames.

---

## 9. Sequencing

Each step is a commit that leaves the game runnable.

1. ~~Encoding + `.gitattributes`~~ ✅
2. ~~Dead-module removal~~ ✅
3. Resource registry + config schema + migration shim
4. `WorkerRoles` data + unified `WorkerService` state machine
5. Wire cleanup signal, delete virtual workers, staggered scheduler
6. Fix chains, retune economy, market glut, wire `RevoltSystem`
7. `Platform` module + `HUDStore` extraction
8. Desktop shell on new store (parity, no visual change)
9. Mobile shell
10. Verification pass
