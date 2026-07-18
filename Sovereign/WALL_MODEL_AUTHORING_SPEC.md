# Wall Model Authoring Spec — Tower Variants & Door Alignment

What every new wall/tower model needs so the placement code can align
connection faces, walkway doors, and ground doors automatically.
Follows the existing `ConnectionPoints` convention from WallSystem/WallGridConfig.

## Models needed

| Model | Purpose | Connection faces |
|---|---|---|
| `Stone_Wall_Tower_Corner90` | 90° corners (can reuse current small tower) | 2 faces, 90° apart |
| `Stone_Wall_Tower_Corner45` | 45° corners | 2 faces, 135° apart |
| `Stone_Wall_Tower_Octagon` *(alternative)* | One model for ALL corner angles + T-junctions | 8 faces, 45° apart |

**Recommendation:** build the octagonal tower. One model with 8 potential
connection faces handles 45°, 90°, 135° corners and T-junctions purely by
rotation — no variant-picking logic, and doors always land on a face.

## Required in every model (checklist)

1. **PrimaryPart** — a part named `Root`, invisible, centered on the tower's
   vertical axis at ground level. Never leave PrimaryPart unset.
   Pivot = Root's position.

2. **`ConnectionPoints` folder** — one part named `ConnectionPoint` per face
   a wall can attach to. Each CP:
   - positioned at the center of that face, at the SAME height as the wall
     segment CPs (world Y=10 convention / 0 studs above ground locally)
   - **oriented with its LookVector pointing outward** along the direction
     the attached wall runs (this is new — lets code solve rotation exactly)
   - at the same horizontal distance from Root on every face
     (= the tower's radius; record it, see attribute below)

3. **`WalkwayDoors` folder** — one part named `WalkwayDoor` per connection
   face, centered on the upper door threshold:
   - floor of the door opening EXACTLY 30 studs above the ConnectionPoint
     (matches Wall Segment walkway offset in WallGridConfig)
   - door opening width = wall walkway width (measure your walkway inner
     width — every variant must use the same value)
   - LookVector pointing outward, same direction as its ConnectionPoint

4. **`GroundDoor` part** (one, optional but recommended) — centered on the
   ground-floor entrance threshold, LookVector pointing outward. The
   "face-the-keep" logic will orient this toward the player's keep.

5. **Model attributes** (set in Studio Properties):
   - `TowerRadius` (number) — Root-to-face distance, e.g. 12
   - `WalkwayHeight` (number) — 30 (or your standardized value)
   - `ConnectionCount` (number) — 2, 4, or 8

## Invariants that must hold across ALL wall models

- Walkway height above CP: identical everywhere (currently 30).
- Wall end profile (width × thickness at the join): identical everywhere,
  so any wall butt-joins flush against any tower face.
- CP height: identical everywhere (ground level).
- Faces flat and full wall-profile sized — the wall end should disappear
  into the face with zero visible seam.

## What the code will do once models have this

- Read CPs + LookVectors instead of hardcoded `TowerRadius`/rotation math.
- At each corner, rotate the tower so two CP LookVectors match dirIn/dirOut
  exactly (octagon: always solvable for 45° multiples).
- Use the remaining free symmetry (if any) to point `GroundDoor` toward the keep.
- Walkway doors line up automatically because height + width are invariant.
