# Combat System v2

The combat engine was rebuilt as a modular system under `src/server/Combat/`. The old `CombatManager` remains as a thin facade with an unchanged public API, so `GameManager`, `UnitManager`, and `VikingRaidSystem` needed no changes.

## Architecture

```
server/Combat/
├── CombatService.luau     Core loop, targeting, engagement, siege, public API
├── CombatTypes.luau       Shared CombatUnit / CombatBuilding / Stance types
├── SpatialGrid.luau       Uniform hash grid — replaces O(n²) enemy scans
├── DamageResolver.luau    Pure damage math (counter matrix, stances, positioning)
├── ProjectileSystem.luau  Ranged flight time, accuracy vs moving targets
├── AbilitySystem.luau     Celtic Fury, War Cry, Shield Wall + expanded roster
├── CombatReplication.luau Batched VFX events → one RemoteEvent per tick
└── CombatSandbox.luau     /arena and /battle instant-test harness

shared/GameData/CombatConfig.luau   All tuning in one nested table
client/Combat/CombatEffectsClient/  Renders hits, deaths, projectiles, abilities
```

## What's new

Counter system: every unit has a damage type (Slash/Pierce/Blunt/Magic/Siege) and armor class (Unarmored/Light/Medium/Heavy/Structure) from `CombatConfig.UnitProfiles`, multiplied through `CombatConfig.CounterMatrix`. Tag bonuses layer on top — Spearmen ×1.8 vs cavalry, Knights ×1.3 vs ranged and civilians.

Ranged combat: archers/slingers/longbowmen/casters fire projectiles with real travel time and accuracy rolls (moving targets are harder to hit). Misses land visibly offset. Visuals are client-animated parabolic arcs.

Formations and positioning: flanking (×1.4), rear (×1.6), and high-ground (×1.25) bonuses; formation cohesion (3+ nearby allies → −12% damage taken); Shield Wall for defensive stances; braced spears fully negate charges and counter-strike the charger.

Siege: units can attack buildings (auto-acquired in Aggressive stance when no enemy units are near, or via manual attack orders). Building HP is defined in `CombatConfig.BuildingHealth`. Siege-type damage does ×3 vs structures; most weapons are weak against them.

Abilities: kept Celtic Fury / War Cry / Shield Wall, plus Heal (Monk/Druid/Priest), Battle Song aura (Bard), Wail (Banshee), Pack Hunter (Wolfhound), Trample (Knight/Hobelar), Hit and Run (Kern/Hobelar), Berserk (Viking/Fianna), Ambush (Bonnacht), Shield Bash stun (Gallowglass), Volley (Longbowman).

Performance: spatial-grid targeting, idle units scan at 2 Hz while fighters tick at 10 Hz, and all VFX moved off the server into one batched RemoteEvent per tick — sized for 100–200 unit battles.

## Fast testing (no need to play up to combat)

Admin chat commands (`TestCommandManager`, admin IDs at top of that file):

```
/arena                                  build a flat arena and teleport there
/battle 10xSpearman,5xArcher vs 12xViking       instant fight, side A is yours
/battle 8xKnight vs 10xSpearman @Empire         optional enemy faction override
/killall                                remove every combat unit
```

When one side is wiped, a battle report prints (Studio output + notification): winner, duration, survivors by type, top damage dealers. Bare unit names count as 1 (`/battle Knight vs 3xSpearman`).

Auto-arena on playtest: set the Workspace attribute `CombatSandboxAutoStart = true` and the arena is built and announced as soon as you join in Studio.

## Tuning

Everything lives in `shared/GameData/CombatConfig.luau`: the counter matrix, per-unit profiles, stance modifiers, positional bonuses, projectile speeds/accuracy, ability numbers, and building HP. No engine code changes needed for balance passes.
