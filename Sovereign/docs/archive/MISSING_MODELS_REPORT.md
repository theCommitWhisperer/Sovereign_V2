# Missing & Placeholder Models Report
_Generated from BuildingsData.luau — models needed in ReplicatedStorage > Assets > Buildings_

---

## 🔴 MISSING MODELS (model_asset_name = nil)
These buildings show a grey box placeholder. You need to add a model to Studio
and then tell me the name so I can set it in BuildingsData.luau.

| Building | Category | Priority | Expected model name (suggestion) |
|---|---|---|---|
| **Iron Mine** | Industry | 🔥 High | `Iron_Mine` |
| **Stone Quarry** | Industry | 🔥 High | `Stone_Quarry` |
| **Coal Mine** | Industry | 🔥 High | `Coal_Mine` |
| **Market** | Industry | Medium | `Market` |
| **Trading Post** | Industry | Medium | `Trading_Post` |
| **Fire Pit** | Defense | Low | `Fire_Pit` |
| **Wooden Palisade** | Defense | Low | `Wooden_Palisade` |
| **Moat** | Defense | Low | `Moat` |

**How to add a model in Studio:**
1. Build or import the model in Studio
2. Place it inside `ReplicatedStorage > Assets > Buildings`
3. Name it exactly (e.g. `Iron_Mine`)
4. Tell me the name and I'll update BuildingsData.luau

---

## 🟡 PLACEHOLDER MODELS (sharing another building's model)
These buildings currently display the wrong visual. They work fine, but the
model doesn't match what the building actually is. Fix when you have custom models ready.

| Building | Currently using | Should use | Notes |
|---|---|---|---|
| **Potato Farm** | `Pig_Farm` | `Potato_Farm` | Wrong model — shows pig farm |
| **Arrow Tower** | `Large_Tower_Stone_Wall` | `Arrow_Tower` | Shared with Round Tower |
| **Barracks** | `Siege_Camps/Red_Siege_Camp` | `Barracks` | Siege camp stand-in |
| **Guard House** | `Siege_Camps/Blue_Siege_Camp` | `Guard_House` | Siege camp stand-in |
| **Training Ground** | `Siege_Camps/Red_Siege_Camp` | `Training_Ground` | Same as Barracks |
| **Armory** | `Storehouse` | `Armory` | Uses storehouse model |
| **Stables** | `Storehouse` | `Stables` | Uses storehouse model |
| **Water Mill** | `Windmill` | `Water_Mill` | Same model as Windmill |
| **Hovel** | `Houses/House` | `Hovel` | Shared with Clachan |
| **Clachan** | `Houses/House` | `Clachan` | Shared with Hovel |
| **Town Hall** | `Mead_Hall` | `Town_Hall` | Same model as Mead Hall |
| **Chapel** | `Church` | `Chapel` | Same model as Church |
| **Siege Workshop** | `Carpenter` | `Siege_Workshop` | Uses carpenter model |

---

## ✅ BUILDINGS WITH CORRECT DEDICATED MODELS
These are fine as-is.

| Building | Model |
|---|---|
| Keep | `Stone_Wall_Large_Keep` |
| Stone Wall | `Stone_Wall_Straight` |
| Short Tower | `Stone_Wall_Small_Tower` |
| Wall Gatehouse | `Stone_Wall_Gatehouse` |
| Wall Ladder | `Stone_Wall_Ladder` |
| Round Tower | `Large_Tower_Stone_Wall` |
| Smelter | `Weapon_Smith` |
| Weaponsmith | `Weapon_Smith` |
| Lumberjack | `Lumberjack` |
| Storehouse | `Storehouse` |
| Tannery | `Tannery` |
| Carpenter | `Carpenter` |
| Sheep Farm | `Sheep_Farm` |
| Cow Farm | `Cow_Farm` |
| Fishermans Hut | `Fisherman_Shop` |
| Windmill | `Windmill` |
| Bakery | `Bakery` |
| Brewery | `Brewery` |
| Granary | `Granary` |
| Tavern | `Tavern` |
| Mead Hall | `Mead_Hall` |
| Inn | `Inn` |
| Monastery | `Scriptorium` |
| Church | `Church` |
| Scriptorium | `Scriptorium` |
| Celtic Cross | `Honor_Statue` |

---

## How to wire up a new model once added to Studio

Once you've added a model to `ReplicatedStorage > Assets > Buildings` and told me its exact name,
I'll update the `model_asset_name` field in BuildingsData.luau. For example:

```lua
-- Before
BuildingsData["Iron Mine"] = {
    model_asset_name = nil,
    ...
}

-- After (once model named "Iron_Mine" exists in Assets/Buildings)
BuildingsData["Iron Mine"] = {
    model_asset_name = "Iron_Mine",
    ...
}
```
