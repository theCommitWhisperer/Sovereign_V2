# Building Points Quick Reference Guide

## 🎯 Quick Start: Adding Worker Points to Buildings

This is a simple 5-minute guide to add worker navigation points to your building models.

## For Production Buildings (Lumberjack, Farms, Mines, etc.)

### Required Parts - Only **3 points needed!**

| Part Name | Where to Place It | Purpose |
|-----------|------------------|---------|
| `BuildingEntrance` | Front door/entrance area | Workers spawn here when first assigned |
| `ProductionStation` | At the work area (forge, workbench, mill, etc.) | Where workers perform their job |
| `ResourceDropoff` | At storage area/shed | Where workers deposit AND haulers pick up resources |

**Important Notes:**
- **`ResourceDropoff` is shared** - Workers deposit here, haulers pick up from the same spot
- **No `ResourcePickup` needed** - Resources are picked up from where workers drop them off
- **No `WorkerRestPosition` needed** - Workers rest at `ProductionStation` (simplified)
- For **resource gatherers** (Lumberjack): Worker goes to trees in world → returns to `ResourceDropoff` → Hauler picks up
- For **auto-producers** (Farm, Smelter): Worker stays at `ProductionStation` → deposits at `ResourceDropoff` → Hauler picks up

### How to Add
1. Insert a `Part` into your building model
2. Rename it (e.g., "BuildingEntrance")
3. Set properties:
   - **Transparency:** 1 (invisible in game)
   - **CanCollide:** false
   - **Anchored:** true
   - **Size:** 2×2×2 studs (small)
4. Position it where workers should go
5. Repeat for all 5 points

## For Storage Buildings (Keep, Storehouse, Granary, Armory)

### Required Parts
Add these storage area parts:

| Part Name | Purpose |
|-----------|---------|
| `BuildingEntrance` | Main entrance |
| `StorageAreaWood` | Wood storage bay |
| `StorageAreaStone` | Stone storage bay |
| `StorageAreaFood` | Food storage bay |
| `StorageAreaIron` | Iron storage bay |
| `StorageAreaGold` | Gold/treasury storage |
| `StorageAreaWeapons` | Weapons storage |
| `StorageAreaGeneral` | General/fallback storage area |

### Pro Tips
- Place storage points in different areas of the building (wood in one corner, stone in another, etc.)
- This makes haulers look realistic as they deliver to different bays
- If you don't have room for all, at least add `StorageAreaGeneral` as a fallback

## 🎨 Studio Tips

### Making Points Visible in Studio (But Invisible in Game)
1. Set **Transparency** to 0.5 while editing (you can see them)
2. Set **Color** to different colors for each point type:
   - BuildingEntrance → Green
   - ProductionStation → Blue
   - ResourceDropoff → Yellow
   - Storage points → Red, Orange, Purple, etc.
3. Before publishing, set **Transparency** to 1 (invisible)

### Quick Copy-Paste
1. Create one properly configured point part
2. Duplicate it (Ctrl+D)
3. Rename and reposition
4. Done!

## 📦 Example: Lumberjack Building

```
Lumberjack (Model)
├── MainHouse (MeshPart) - The actual building visual
├── BuildingEntrance (Part) - At front door
│   ├── Size: 2, 2, 2
│   ├── Transparency: 1
│   ├── CanCollide: false
│   └── Position: (10, 0, 5) [front door]
├── ProductionStation (Part) - At chopping block/workbench
│   └── Position: (12, 0, 8) [where worker "works"]
└── ResourceDropoff (Part) - At storage shed
    └── Position: (8, 0, 10) [workers deposit wood, haulers pick up]
```

**That's it! Just 3 points!**

## ✅ Testing Your Points

Once you've added points to a building:

1. Place the building in workspace
2. Open Output window
3. Run this in Command Bar:
```lua
local WorkerPointSystem = require(game.ServerStorage.Server.Systems.WorkerPointSystem)
local building = workspace.Buildings:GetChildren()[1] -- First building
WorkerPointSystem.debugPrintPoints(building)
```

You should see all your points listed with their positions!

## ⚠️ Common Mistakes

❌ **DON'T:**
- Leave `CanCollide = true` (workers will bump into points)
- Make points huge (keep them small, 2×2×2 studs)
- Put all points in the same spot
- Forget to set `Anchored = true`

✅ **DO:**
- Make points invisible (`Transparency = 1`)
- Spread points around the building realistically
- Use different positions for each point type
- Test in-game to see worker movement

## 🚀 Priority Buildings

Start with these buildings first:

### High Priority (Core Gameplay)
1. **Lumberjack** - Most common worker building
2. **Keep** - Main storage building
3. **Storehouse** - Secondary storage
4. **Potato Farm** - Food production
5. **Stone Quarry** - Stone gathering

### Medium Priority
6. Smelter
7. Weaponsmith
8. Barracks
9. Granary
10. Armory

### Low Priority
- Everything else (system works with fallbacks)

## 🎯 Minimum Viable Points

**Good news!** The system is already minimal:

**Production buildings:** Just need 3 points
1. **BuildingEntrance** - Where workers enter
2. **ProductionStation** - Where work happens
3. **ResourceDropoff** - Where resources are stored

**Storage buildings:** Just need 2 points minimum
1. **BuildingEntrance** - Where haulers enter
2. **StorageAreaGeneral** - Where everything is stored

If points are missing, the system automatically falls back to the building center.

## 📝 Checklist

**For Production Buildings (Lumberjack, Farms, Mines, etc.):**
- [ ] Added `BuildingEntrance` part at front door
- [ ] Added `ProductionStation` part at work area
- [ ] Added `ResourceDropoff` part at storage/shed area
- [ ] Set all parts to `Transparency = 1` (invisible)
- [ ] Set all parts to `CanCollide = false`
- [ ] Set all parts to `Anchored = true`
- [ ] Tested in-game - workers walk to correct spots

**For Storage Buildings (Keep, Storehouse, etc.):**
- [ ] Added `BuildingEntrance` part at main entrance
- [ ] Added storage area parts for each resource type
- [ ] Added `StorageAreaGeneral` as fallback
- [ ] Set all parts to `Transparency = 1`
- [ ] Set all parts to `CanCollide = false` and `Anchored = true`
- [ ] Tested in-game - haulers deliver to correct bays

---

That's it! The code is already done - you just need to add the physical parts to your building models and the system will automatically use them! 🎉
