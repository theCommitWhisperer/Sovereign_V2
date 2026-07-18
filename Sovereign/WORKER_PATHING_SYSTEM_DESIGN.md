# Worker Pathing System Design Document

## Overview
A comprehensive worker pathing system that uses named attachment points in building models to guide worker behavior. This system mirrors the successful `SpawnPointSystem` design and provides precise control over where workers spawn, idle, work, and deliver resources.

## Current System Issues
1. Workers currently use `WorkerPoint` as a single position marker (see WorkerManager.luau:299)
2. No distinction between idle, working, and delivery positions
3. Storehouse buildings lack specialized storage points for different resources
4. Workers path to building centers rather than specific functional areas

## Proposed Solution: WorkerPointSystem

### Core Concept
Similar to how `SpawnPointSystem` finds and uses `SpawnPoint` parts in buildings, the new `WorkerPointSystem` will search for multiple named points within each building model:

#### Point Types for Production Buildings (Lumberjack, Quarry, Farms, etc.)
- **`SpawnPoint`** - Where workers initially appear when assigned to the building
- **`WorkerIdlePoint`** - Where workers stand when idle/waiting
- **`WorkerWorkingPoint`** - Where workers perform their work activity
- **`DeliveryPoint`** (optional) - Where haulers/workers pick up completed resources

#### Point Types for Storage Buildings (Storehouse, Keep, Granary)
- **`SpawnPoint`** - Default entry point for the building
- **`DefaultStoragePoint`** - Generic storage location
- **`WoodStoragePoint`** - Specific point for wood deliveries
- **`StoneStoragePoint`** - Specific point for stone deliveries
- **`FoodStoragePoint`** - Specific point for food deliveries
- **`IronStoragePoint`** - Specific point for iron ore/bars
- **`GoldStoragePoint`** - Specific point for gold
- **`WeaponStoragePoint`** - Specific point for weapons

### Building Model Structure Example

```
Lumberjack (Model)
├── MainBuilding (MeshPart/Part)
├── SpawnPoint (Part) - Front door area
├── WorkerIdlePoint (Part) - Near workbench
├── WorkerWorkingPoint (Part) - At the chopping block
└── DeliveryPoint (Part) - Storage shed area

Storehouse (Model)
├── MainBuilding (MeshPart/Part)
├── SpawnPoint (Part) - Front entrance
├── DefaultStoragePoint (Part) - Center of building
├── WoodStoragePoint (Part) - Left storage bay
├── StoneStoragePoint (Part) - Right storage bay
├── FoodStoragePoint (Part) - Back left corner
└── IronStoragePoint (Part) - Back right corner
```

## System Architecture

### 1. WorkerPointSystem Module (New)
Location: `src/server/Systems/WorkerPointSystem.luau`

```lua
-- Similar structure to SpawnPointSystem
export type WorkerPointType =
    "SpawnPoint" |
    "WorkerIdlePoint" |
    "WorkerWorkingPoint" |
    "DeliveryPoint" |
    "DefaultStoragePoint" |
    "WoodStoragePoint" |
    "StoneStoragePoint" |
    "FoodStoragePoint" |
    "IronStoragePoint" |
    "GoldStoragePoint" |
    "WeaponStoragePoint"

-- Main functions:
function WorkerPointSystem.findPoint(buildingModel: Model, pointType: WorkerPointType): BasePart?
function WorkerPointSystem.getPointPosition(buildingModel: Model, pointType: WorkerPointType): Vector3?
function WorkerPointSystem.getPointCFrame(buildingModel: Model, pointType: WorkerPointType): CFrame?
function WorkerPointSystem.hasPoint(buildingModel: Model, pointType: WorkerPointType): boolean
function WorkerPointSystem.getStoragePointForResource(buildingModel: Model, resourceType: string): Vector3?
```

### 2. BuildingsData Updates
Add optional `worker_points` configuration to building data:

```lua
BuildingsData.Lumberjack = {
    -- ... existing fields ...
    worker_points = {
        spawn_point_name = "SpawnPoint",
        idle_point_name = "WorkerIdlePoint",
        working_point_name = "WorkerWorkingPoint",
        delivery_point_name = "DeliveryPoint",
    },
} :: BuildingData

BuildingsData.Storehouse = {
    -- ... existing fields ...
    storage_points = {
        Wood = "WoodStoragePoint",
        Stone = "StoneStoragePoint",
        Food = "FoodStoragePoint",
        Iron_Ore = "IronStoragePoint",
        Iron_Bars = "IronStoragePoint",
        Weapons = "WeaponStoragePoint",
        default = "DefaultStoragePoint", -- Fallback
    },
} :: BuildingData
```

### 3. WorkerManager Integration

#### Current Flow (Resource Gathering Buildings)
1. Worker assigned → walks to building (uses `WorkerPoint` or building center)
2. Worker transforms to job type
3. Worker goes to resource node
4. Worker gathers resources
5. Worker returns to building

#### New Flow (Resource Gathering Buildings)
1. Worker assigned → walks to **SpawnPoint**
2. Worker transforms to job type
3. Worker moves to **WorkerIdlePoint** (brief pause)
4. Worker walks to **WorkerWorkingPoint**
5. For resource gatherers: Worker goes to nearby resource node
6. Worker gathers resources
7. Worker returns to **DeliveryPoint** (or WorkingPoint)
8. Hauler picks up from **DeliveryPoint**

#### New Flow (Production Buildings - Smelter, Weaponsmith, etc.)
1. Worker assigned → walks to **SpawnPoint**
2. Worker transforms to job type (Smelter, Blacksmith, etc.)
3. Worker moves to **WorkerIdlePoint**
4. Worker walks to **WorkerWorkingPoint**
5. Worker stays at **WorkerWorkingPoint** and produces resources
6. Resources accumulate in building storage
7. Hauler picks up from **DeliveryPoint**

#### Storage Building Flow
1. Hauler picks up resources from production building
2. Hauler finds nearest storage with capacity
3. Hauler walks to **`{ResourceType}StoragePoint`** (e.g., WoodStoragePoint)
4. If specific point doesn't exist, use **DefaultStoragePoint**
5. Hauler deposits resources

## Implementation Plan

### Phase 1: Core System
- [ ] Create `WorkerPointSystem.luau` module
- [ ] Implement point finding functions (similar to SpawnPointSystem)
- [ ] Add fallback logic (use building center if points missing)
- [ ] Unit tests for point finding

### Phase 2: Data Configuration
- [ ] Update `BuildingsData.luau` with worker point configurations
- [ ] Add `worker_points` field to BuildingData type
- [ ] Add `storage_points` field to storage building types
- [ ] Document point naming conventions

### Phase 3: WorkerManager Integration
- [ ] Replace `getAccessibleBuildingPosition()` with `WorkerPointSystem.getPointPosition()`
- [ ] Update worker state machine to use different points per state
- [ ] Update hauler logic to use storage-specific points
- [ ] Add debug visualization (optional: show point markers in studio)

### Phase 4: Building Models
- [ ] Add point parts to all production building models
- [ ] Add storage-specific points to Storehouse, Keep, Granary models
- [ ] Ensure points are non-collidable, invisible, and properly positioned
- [ ] Test with multiple workers per building

### Phase 5: Testing & Polish
- [ ] Test each building type with workers
- [ ] Verify workers path correctly between points
- [ ] Test storage buildings with multiple resource types
- [ ] Performance testing with many workers
- [ ] Debug visualization tools

## Worker State Machine Update

```
GoingToWorkplace State:
    moveTowardsBuilding(workplace, "SpawnPoint")
    on arrival:
        transformWorker()
        state = Transforming

Transforming State (new):
    moveTowardsBuilding(workplace, "WorkerIdlePoint")
    on arrival:
        state = MovingToWork

MovingToWork State (new):
    moveTowardsBuilding(workplace, "WorkerWorkingPoint")
    on arrival:
        state = Gathering (or Producing for production chains)

Gathering State:
    if resource_gathering_building:
        find resource node
        gather from node
    else: # production building
        stay at WorkerWorkingPoint
        produce resources over time

    when full:
        state = ReturningToWorkplace

ReturningToWorkplace State:
    moveTowardsBuilding(workplace, "DeliveryPoint" or "WorkerWorkingPoint")
    on arrival:
        deposit resources
        state = MovingToWork
```

## Hauler Logic Update

```lua
-- When depositing to storage
local storagePoint = WorkerPointSystem.getStoragePointForResource(
    targetStorage,
    task.resourceType
)

if storagePoint then
    moveTowards(hauler, storagePoint, speed)
else
    -- Fallback to DefaultStoragePoint or building center
    local defaultPoint = WorkerPointSystem.getPointPosition(
        targetStorage,
        "DefaultStoragePoint"
    )
    moveTowards(hauler, defaultPoint or targetStorage:GetPivot().Position, speed)
end
```

## Benefits

1. **Precise Worker Behavior**: Workers move to realistic positions within buildings
2. **Visual Polish**: Workers appear to actually use workbenches, forges, storage areas
3. **Data-Driven**: Easy to configure per building type in BuildingsData
4. **Flexible**: Fallback to building center if points missing
5. **Scalable**: Easy to add new point types for future features
6. **Consistent**: Mirrors proven SpawnPointSystem architecture
7. **Organized Storage**: Haulers deliver to specific areas based on resource type

## Fallback Strategy

If a building model doesn't have the required points:
1. Check for point in BuildingsData configuration
2. Search building model for named part (recursive)
3. If not found, use building PrimaryPart position
4. Log warning for missing points (in debug mode)

This ensures the system works even with incomplete building models during development.

## Future Enhancements

1. **Multi-Worker Buildings**: Support multiple WorkerWorkingPoint# parts (WorkerWorkingPoint1, WorkerWorkingPoint2, etc.)
2. **Animation Triggers**: Points could trigger specific worker animations
3. **Efficiency Bonuses**: Properly configured buildings could give production bonuses
4. **Visual Indicators**: Show point locations in Studio for builders
5. **Dynamic Points**: Points that move (e.g., rotating mill wheels, moving carts)

## Example Usage

```lua
-- In WorkerManager
local function moveWorkerToWorkingPosition(task: WorkerTask)
    local workingPos = WorkerPointSystem.getPointPosition(
        task.workplace,
        "WorkerWorkingPoint"
    )

    if workingPos then
        return moveTowards(task.worker, workingPos, speed)
    else
        -- Fallback to old system
        return moveTowardsBuilding(task.worker, task.workplace, speed)
    end
end

-- In HaulerManager
local function deliverToStorage(haulerTask: HaulerTask)
    local deliveryPoint = WorkerPointSystem.getStoragePointForResource(
        haulerTask.targetStorage,
        haulerTask.resourceType
    )

    if deliveryPoint then
        return moveTowards(haulerTask.hauler, deliveryPoint, speed)
    end
end
```

---

## Next Steps

1. Review and approve this design
2. Create WorkerPointSystem module
3. Update BuildingsData with point configurations
4. Integrate with WorkerManager
5. Update building models with point parts
6. Test and iterate

This system will make your worker and hauler behavior much more realistic and visually polished, while keeping the code clean and maintainable!
