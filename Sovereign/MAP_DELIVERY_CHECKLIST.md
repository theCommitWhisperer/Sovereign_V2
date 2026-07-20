# Shipping a Studio-authored Sovereign map

This project treats a map as two separate deliverables:

1. The static world, authored and published in Roblox Studio.
2. The small gameplay data set committed to this repository.

The static world must be the only map present in a match server's Workspace.
Never combine multiple complete maps at the same coordinates.

## Studio authoring

1. Duplicate the current published map place or create a new place inside the Sovereign experience.
2. Create one `MapBounds` anchored part covering the playable X/Z area. Make it invisible and non-collidable. The RTS camera automatically constrains itself to this part when it exists.
3. Build terrain, collision, and static decoration in Studio. Keep visual foliage non-collidable, anchor static parts, and use simple collision shapes for pathfinding obstacles.
4. For a hand-authored map, add a `UseStudioTerrain` BoolValue to Workspace and set it to `true`.
5. Use the in-game map editor to set four Keep spawn zones, resource patches, and ownership zones. Export the data when balance and placement are final.
6. Upload a lobby preview image and record its asset ID.

## Repository data

1. Add the exported gameplay data as `src/shared/GameData/BuiltinMapData/<MapKey>.luau`.
2. Add the matching `MapData.Maps["<MapKey>"]` entry in `src/shared/GameData/MapData.luau` with the exact size, `MaxPlayers`, preview ID, and Keep spawn zones.
3. Do not add a map key to `MapData` until its Studio terrain and preview are ready; lobby map entries are live choices.

## Multiplayer validation

1. In Studio, run **Start Server** with 2-4 clients.
2. Have each client enter the lobby, choose spawns, and ready up.
3. Confirm all clients start on the same map, each gets its selected zone, and the terrain is not regenerated as later clients start.
4. Pan the RTS camera across the full map at low client graphics quality; terrain should stream in before the camera reaches it.
5. Test a client submitting a different `StartGame` map after the match began. The server must reject it.

## Dedicated map places

When a map needs its own Roblox place, keep the game code shared between places and configure server-side `TeleportService:TeleportAsync()` with a reserved server. Do not trust map IDs, factions, resources, or spawn zones sent back from a client after the teleport. The target place should validate its expected map and recover match settings from a server-owned ticket store.

Teleporting cannot be fully wired until the published destination PlaceId values are available. The current server-safe lifecycle is intentionally complete for same-place matches, including the existing `TheIslands` map.
