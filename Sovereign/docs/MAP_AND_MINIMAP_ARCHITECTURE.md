# Map, Minimap & Match Architecture

Status: **plan, not yet implemented.** Written 2026-07-30.
Supersedes the "Dedicated map places" section of `docs/archive/MAP_DELIVERY_CHECKLIST.md`.

Decisions locked in:

1. **Multi-place universe** — root lobby place, one place per map, reserved servers via `TeleportAsync`.
2. **Baked zone grid** — painted territory becomes a packed buffer the server queries in O(1).
3. **Order of work** — this doc → minimap rewrite → teleport pipeline → zone grid.

---

## 0. Current state, honestly

### What works

- The **two-tier map model is correct**: static terrain authored in Studio (baked into the place),
  gameplay data committed to git as `BuiltinMapData/<Key>.luau` + a `MapData.Maps` entry.
- `LobbyManager` is genuinely good — factions, colours, spawn picking, team layouts, AI seats,
  ready-up, countdown, server-authored `pendingStartSettings`.
- `MapManager.lockMatchMap` correctly prevents a second client changing the map mid-match.
- `MapPreview.luau` already renders zone data correctly *in the lobby*, reading `mapConfig.Size`.

### What is broken

| # | Problem | Evidence |
|---|---------|----------|
| 1 | Painted zone data is never read at runtime | `getZoneAt` exists only in `MapEditorManager.luau:71`. Build check is `SpawnManager.isPositionInEstate:161` — a radius test. |
| 2 | Three client systems poll a blocking RemoteFunction per object, 2×/sec | `MiniMapEnhanced:121`, `FogOfWarClient:47,85,111,149,166,199`, `HealthBarManager:148` |
| 3 | `MAP_SIZE = 1000` hardcoded; `TheIslands` is 1600 | `MiniMap.luau:20`, `MiniMapEnhanced.luau:20` vs `MapData.luau:61` |
| 4 | Map config never reaches the client at match start | `LobbyManager:1123` `GameStarted` payload has no `Size`/`KeepSpawnZones` |
| 5 | One place = one terrain, so map #2 cannot be added | `UseStudioTerrain` at `GameManager:882` |
| 6 | `FogOfWarManager` builds a per-player visibility cache nothing reads | `updateVisibility:184-202`; `isUnitVisible` recomputes from scratch |
| 7 | `StreamingEnabled = true` with no `Persistent` overrides | `default.project.json:26`; zero `ModelStreamingMode` hits repo-wide |
| 8 | `FactionManager` team relationships are not reset on `LeaveGame` | acknowledged in comment at `GameManager:1054-1059` |

Problem 2 is the most severe. With fog disabled by default (`FogOfWarManager:32`) each call
returns `true` immediately, so the cost is pure round-trip latency — but at 200 units × 3 systems
× 2 Hz × 4 clients that is thousands of serialized `InvokeServer` calls per second. It will not
survive a real match. **Enabling fog makes it worse**, because `isPositionVisible:69-114` is O(N)
over every unit and building the player owns, with no spatial index.

Problem 7 compounds problem 2: nothing is marked `ModelStreamingMode = Persistent`, so a client
scanning `workspace.Units` physically cannot see units outside its streaming radius. On a
1600-stud map the current minimap is structurally incapable of showing the whole map, regardless
of how the visibility check is implemented.

---

## 1. Minimap rewrite

### Principle

The minimap must be fed by **server push**, not by scanning `workspace`. This fixes the round-trip
storm and the `StreamingEnabled` blindness in one move, because blips stop depending on whether an
Instance happens to be replicated to this client.

### 1.1 Server: `src/server/Systems/BlipReplicator.luau` (new)

Runs one loop at **4 Hz**. Per player, builds a compact snapshot of what that player may see:

- Own + allied units, buildings, and Keeps — always included.
- Enemy units/buildings — included only when `FogOfWarManager` says visible.
- Resource nodes — included when discovered (currently: always; fog is off).

Encode into a `buffer`, not a Lua table. Per blip, 6 bytes:

| Offset | Type | Meaning |
|--------|------|---------|
| 0 | `i16` | world X, studs |
| 2 | `i16` | world Z, studs |
| 4 | `u8`  | owner slot (0–7) in low nibble, relation (self/ally/enemy/neutral) in high nibble |
| 5 | `u8`  | kind: 0=unit 1=building 2=resource, plus subtype index in high nibble |

Dedupe on an 8-stud grid per `(owner, kind)` before encoding — the minimap is ~170 px wide, so
sub-8-stud precision is invisible. A 500-unit battle collapses to roughly 60–120 blips.
Snapshot cost lands around 1 KB, i.e. **~4 KB/s per player** replacing thousands of round trips.

Transport: a new **`UnreliableRemoteEvent`** named `BlipSnapshot`. This is a latest-state-wins
stream; a dropped packet is corrected 250 ms later and costs nothing. Do not use a reliable remote
here — head-of-line blocking on a 4 Hz stream is exactly what unreliable remotes exist to avoid.

Reuse the loop already sitting dead in `FogOfWarManager.updateVisibility:184-202`. It already
computes per-player visible sets at 0.5 s and nothing consumes them. Point it at `BlipReplicator`
instead of deleting it.

### 1.2 Server: fix the fog query itself

Before `BlipReplicator` can run at 4 Hz with fog enabled, `isPositionVisible` needs a spatial
index. Add a coarse **64-stud hash grid** of each player's vision sources (units, buildings,
Keeps), rebuilt once per replicator tick, and query the 3×3 neighbourhood instead of scanning
every owned object. This turns an O(N) per-object test into O(1) amortised and is what makes fog
affordable to turn on by default later.

### 1.3 Client: `src/client/Minimap/MinimapService.luau` (new)

Owns the decoded blip array. Subscribes to `BlipSnapshot`, decodes the buffer into a flat
pre-allocated array, exposes `MinimapService.getBlips()` and `MinimapService.getMapConfig()`.
**Never calls `setState`.** Mirrors the incremental-cache pattern already proven by
`UnitAnimator.tracked` and server-side `BuildingIndex`.

### 1.4 Client: rendering

Replace React `setState`-per-tick with a **Frame pool**:

- Pre-allocate 256 blip `Frame`s once, parented to the minimap, `Visible = false`.
- On each snapshot, write `Position`/`BackgroundColor3`/`Visible` directly on the pooled frames.
  Hide the unused tail. Zero instance churn, zero React reconciliation.
- React owns only the static chrome (border, buttons, ping overlay) and re-renders rarely.

Background terrain: use the existing baked **`PreviewImage`** asset
(`MapData.luau:82`, `rbxassetid://99833618647614`) as an `ImageLabel` behind the blips. This is
already authored per map and removes procedural terrain drawing from the HUD entirely.

`EditableImage` was considered for blips and rejected — the Frame pool is simpler, has no API
gating, and performs fine on mobile at these counts.

### 1.5 Kill `MAP_SIZE`

Add to the `GameStarted` payload at `LobbyManager.luau:1123`:

```luau
mapConfig = {
    Name = mapConfig.Name,
    Size = mapConfig.Size,
    PreviewImage = mapConfig.PreviewImage,
    KeepSpawnZones = mapConfig.KeepSpawnZones,
}
```

`HUDStore` caches it (`HUDStore.setGameStartData:328`). Both minimaps read `Size` from the store.
Delete the constant from `MiniMap.luau:20` and `MiniMapEnhanced.luau:20`.

There are currently two minimap components — `MiniMapEnhanced` (desktop, `DesktopShell:18`) and
`MiniMap` (mobile, `MobileShell:82`). **Merge them.** One component, one data source, layout
differences via props. Maintaining two copies of coordinate maths is how the `MAP_SIZE` bug
survived in both files.

### 1.6 Retire the other polling loops

`FogOfWarClient` and `HealthBarManager` should consume the same pushed visibility set from
`MinimapService` rather than running their own `InvokeServer` loops. Keep the `CheckVisibility`
RemoteFunction for genuine one-off queries; delete every loop that calls it per object.

### Files touched

| File | Change |
|------|--------|
| `src/server/Systems/BlipReplicator.luau` | new |
| `src/server/Managers/FogOfWarManager.luau` | spatial hash; feed BlipReplicator; drop dead cache |
| `src/server/GameManager.server.luau` | create `BlipSnapshot` UnreliableRemoteEvent; start replicator |
| `src/server/Managers/LobbyManager.luau` | add `mapConfig` to `GameStarted` payload |
| `src/client/Minimap/MinimapService.luau` | new |
| `src/client/Combat/FogOfWarClient/init.luau` | consume pushed set, delete per-object loop |
| `src/client/Combat/HealthBarManager/init.luau` | same |
| `src/ui/screens/HUD/MiniMap.luau` | rewrite as the single shared component |
| `src/ui/screens/HUD/MiniMapEnhanced.luau` | delete, re-point `DesktopShell` |
| `src/ui/state/HUDStore.luau` | store `mapConfig` slice |

---

## 2. Multi-place teleport pipeline

### 2.1 Place layout

| Place | Role | Contents |
|-------|------|----------|
| Root (`Sovereign`) | Lobby | No terrain, no RTS systems. Menu + lobby UI. Fast load. |
| `Sovereign — The Islands` | Match | Hand-built islands terrain + shared code |
| `Sovereign — <Map 2>` | Match | Map 2 terrain + shared code |

Players arriving from the Roblox launcher **always land in the root place**, so the root place must
be the lobby. This is the single most important structural fact about Roblox discovery.

### 2.2 Place role config

New `src/shared/GameData/PlaceData.luau`:

```luau
PlaceData.Places = {
    [0] = { Role = "Lobby" },                              -- fill in real PlaceIds
    [0] = { Role = "Match", MapKey = "TheIslands" },
}
PlaceData.LobbyPlaceId = 0
```

Add `PlaceId: number` to each `MapData.Maps` entry. A server decides its own behaviour from
`game.PlaceId` at boot — one codebase, no forks, exactly as `MAP_DELIVERY_CHECKLIST.md` requires.

### 2.3 Publishing workflow — important

`default.project.json` currently owns `Workspace` (`StreamingEnabled`, `Lighting`).
**Do not `rojo upload`** to a match place: it would overwrite hand-built terrain.

The workflow is:

1. `rojo serve` + Rojo plugin live-sync into the open place in Studio.
2. Publish that place manually from Studio (**File → Publish to Roblox As**).
3. Repeat per place. Code is identical because it came from the same repo.

Optionally split `default.project.json` into a code-only project (no `Workspace` node) used for
sync, keeping the current file for fresh place bootstrapping.

### 2.4 Match ticket store

`MAP_DELIVERY_CHECKLIST.md` is explicit: *"recover match settings from a server-owned ticket
store"*, not from client-returned teleport data. Use `MemoryStoreService`:

```
MemoryStoreHashMap("SovereignMatchTickets")
key   = matchId (GUID from the lobby server)
value = { Settings, Players = {UserId -> playerSettings}, AIPlayers, TeamOf, MapKey }
TTL   = 300s
```

`MemoryStoreService` is currently unused in the repo — confirmed, zero hits.

### 2.5 Lobby side

Rewrite the tail of `LobbyManager.startGame:768`. Today it fires `LobbyGameStart` to the client,
and the client fires `StartGame` **back to the same server** (`Lobby.luau:182-188` →
`GameManager:821`). That round trip is what the teleport replaces:

```
startGame()
  build playerSettings + aiPlayers + teamOf   -- already exists, L842-882
  matchId = HttpService:GenerateGUID(false)
  MemoryStore:SetAsync(matchId, ticket, 300)
  code = TeleportService:ReserveServer(mapPlaceId)
  opts = TeleportOptions{ ReservedServerAccessCode = code }
  opts:SetTeleportData({ matchId = matchId })
  TeleportService:TeleportAsync(mapPlaceId, humanPlayers, opts)
```

Only `matchId` travels in teleport data. Everything authoritative is fetched server-side from the
ticket. AI opponents are not `Player` instances and cannot teleport — they ride in the ticket as
the existing `{ UserId, Name, Faction }` tuples (`LobbyManager:843-851`) and are re-registered by
the destination via `AIManager.registerAI`. Personality is re-rolled, which is fine — it was
random anyway (`AIManager:105-138`).

While here: `difficulty` is never plumbed from the lobby to `registerAI` (call site
`GameManager:1205` omits it), so every AI is Medium. Add `Difficulty` to the AI tuple.

### 2.6 Match side

New `src/server/MatchBootstrap.server.luau`. On `PlayerAdded`:

1. Read `player:GetJoinData().TeleportData.matchId`.
2. Fetch the ticket from MemoryStore. **If absent, reject** — kick back to the lobby place.
3. Verify this `UserId` is in the ticket roster.
4. Verify `ticket.MapKey` matches this place's `PlaceData` entry.
5. Call the shared setup function.

**Refactor prerequisite:** `GameManager.server.luau:842-1217` — the whole `StartGame` body — must
be extracted into `src/server/Match/StartMatch.luau` with two entry points: the existing
same-server remote (retained for solo and Studio testing) and the teleport bootstrap. This
extraction is the bulk of the work in this phase.

### 2.7 Validation debt

The recon found that almost nothing in the `StartGame` handler is validated. Only `map` is truly
enforced (via `lockMatchMap`); `playerColor`, `teamOf`, and `quadrant` get shallow type checks.
These are trusted verbatim:

`gameSpeed`, `victoryCondition`, `faction`, `startingResources`, `startingGold`, `startingFood`,
`startingWeapons`, `vikingRaids`, `unitMorale`, `abilityToTrade`, `showTutorial`,
`teamOf` contents, `quadrant` ownership.

The ticket store fixes this for multiplayer, but the solo path at `GameManager:842`
(`settings = lobbySettings or data`) still falls through to raw client data. Add a
`validateMatchSettings(settings)` in `StartMatch.luau` applied on **both** paths.

### 2.8 Also fix while in here

- `MapManager.lockMatchMap` becomes vestigial — one place, one map, enforced by `PlaceId`.
  Keep it as a cheap assertion, not as the mechanism.
- `FactionManager` relationships are never reset on `LeaveGame` (`GameManager:1054-1059`).
  Under reserved-server-per-match this stops mattering, but add the reset anyway.
- `workerLoopStarted` (`GameManager:176`) is never reset. Fine under one-match-per-server, which
  reserved servers guarantee. Leave a comment saying so.
- No late-joiner path exists. Reserved servers make this an explicit product decision —
  recommend closing matches to joiners for now (`TeleportService` access code is not shared).

---

## 3. Zone grid

### 3.1 The problem

`TheIslands.luau` is 65 KB, almost entirely `ZonePaintStrokes` — thousands of 40-stud circles.
Nothing at runtime reads them. Buildable area is four 400-stud circles from `KeepSpawnZones`.
Territory can therefore never be shaped, and the map file pays 65 KB for nothing.

### 3.2 The fix

Rasterize once at export, in `MapEditorManager`'s export path (~L1323):

- Cell size **8 studs**. A 1600-stud map → 200 × 200 = 40,000 cells.
- 4 bits per cell (zones 0–6 fit in 3; 4 keeps nibble alignment) → **20,000 bytes**.
- Emit as a base64 string literal in the `.luau` module; decode to a `buffer` at require time.

New `src/shared/GameData/ZoneGrid.luau`:

```luau
ZoneGrid.fromBase64(encoded: string, size: number, cell: number): ZoneGrid
ZoneGrid:getZoneAt(x: number, z: number): number   -- O(1)
```

Result: **65 KB of tables → 20 KB of buffer**, and an O(1) lookup replacing an O(strokes) scan.

### 3.3 Wiring

- `SpawnManager.isPositionInEstate:161` — use the grid when present, keep the radius fallback for
  procedural and player-made maps.
- `BuildingManager:164` — additionally reject zone 6 (No Build).
- `PathfindingIntegration` — feed zone 5 (Impassable) in as static obstacles.
- Keep `ZonePolygons` in the source data (needed to re-edit in the map editor); ship only the
  baked grid in `BuiltinMapData`. Drop `ZonePaintStrokes` from shipped data entirely.

---

## 4. Adding map #2

Once phases 1–3 land, a new map is:

1. Duplicate the match place in Studio. Build terrain. Add a `MapBounds` part.
2. Add `UseStudioTerrain = true` BoolValue to `Workspace`.
3. Run the in-game map editor: four Keep spawn zones, resource patches, territory polygons.
4. Export → commit `src/shared/GameData/BuiltinMapData/<Key>.luau` (now with a baked zone grid).
5. Upload a preview image; record the asset ID.
6. Add the `MapData.Maps["<Key>"]` entry with `Size`, `MaxPlayers`, `PreviewImage`, `PlaceId`.
7. Add the `PlaceData.Places[<PlaceId>]` entry.
8. Publish. It appears in the lobby automatically.

Roughly a day of terrain work plus one data file.

---

## 5. Sequencing

| Phase | Work | Ships |
|-------|------|-------|
| **1** | Minimap rewrite (§1) | Removes the worst production risk; fixes the 1000/1600 bug; makes the minimap streaming-safe |
| **2** | Extract `StartMatch.luau` + validation (§2.6, §2.7) | No behaviour change, pure refactor — the risky part, done in isolation |
| **3** | Teleport pipeline (§2.1–2.6) | Requires published PlaceIds; unblocks map #2 |
| **4** | Zone grid (§3) | Shrinks map data, makes painted territory real |
| **5** | Build map #2 (§4) | Content |

Phase 2 before 3 is deliberate: pulling 375 lines out of `GameManager` while *also* changing the
transport is how you get a bug you cannot bisect.

### Verification per phase

- `rojo build` clean; no new Luau type errors (`--!strict` is on across these files).
- Run the existing spec suite — `MapManager.spec`, `PlayerManager.spec`, `FactionManager.spec`,
  `VictoryIntegration.spec` all touch code in scope.
- Studio **Start Server** with 2–4 clients, per `MAP_DELIVERY_CHECKLIST.md` §"Multiplayer validation".
- Phase 1 specifically: spawn 200+ units and confirm minimap frame time and network graph are flat.

---

## 6. Open questions

- **PlaceIds.** Nothing can be wired until the lobby and match places are published. Ordering the
  publish early unblocks phase 3.
- **Fog by default.** The spatial hash makes it affordable. Do you want fog on in shipped matches?
  It changes the blip payload substantially.
- **Late joiners.** Reserved servers close the match. Confirm that is the intent.
- **Custom maps.** `__custom__` maps have no place of their own. Options: a single generic
  "Custom" match place that generates terrain from sculpt strokes at load, or drop custom maps from
  multiplayer and keep them solo-only.
