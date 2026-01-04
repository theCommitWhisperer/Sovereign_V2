# Population & Economy Game Design

## 🎮 Optimal Gameplay Flow

This document outlines how the population and economy system should work for an engaging RTS experience similar to Stronghold.

---

## 📊 Current System Analysis

### **Housing Buildings:**
- **Keep**: Provides base housing for 10 people (built at game start)
- **Hovel**: +5 population capacity (Cost: 10 Wood, 5s build time)
- **Clachan**: +8 population capacity (Cost: 15 Wood + 10 Stone, 8s build)
- **Inn**: +3 population capacity + happiness boost (Cost: 35 Wood + 25 Stone)
- **Monastery**: +10 population capacity + produces Manuscripts (Cost: 50 Wood + 80 Stone + 50 Gold)
- **Chapel**: +2 population capacity + happiness boost (Cost: 20 Wood + 30 Stone)

### **Current Mechanics:**
✅ **Keep can train Peasants** (manual player action)
✅ **Housing capacity system exists** (`PopulationManager.luau`)
✅ **Automatic population growth** (1 peasant/60s if conditions met)
✅ **Growth requirements**: Food > 50, Housing available, Happiness > 40

---

## 🎯 Recommended Game Design

### **Core Philosophy:**
**"Housing enables population, resources sustain it, happiness grows it"**

Players should:
1. Build housing to unlock population slots
2. Manually train initial peasants OR wait for natural growth
3. Balance housing, food production, and happiness for optimal growth

---

## 👥 Player Experience (Human Players)

### **Game Start:**
```
✅ Keep spawns automatically (provides base housing: 10)
✅ 5 Starting peasants spawn near Keep
✅ Players can immediately start gathering resources
```

**Why 5 starting peasants?**
- Allows immediate resource gathering (2-3 on Wood, 2 on Food)
- Leaves 5 housing slots for growth/training
- Prevents overwhelming new players

### **Early Game (0-5 minutes):**

**Player Actions:**
1. **Assign starting peasants** to gather Wood and Food
2. **Build 1-2 Hovels** when Wood > 20 (adds 5-10 housing capacity)
3. **Manually train 2-3 peasants** at Keep (costs resources + time)
4. **Balance gathering** between Wood (building), Food (population), Stone (defenses)

**Automatic Growth:**
- Every 60 seconds, **IF**:
  - Food > 50 ✓
  - Housing available ✓
  - Happiness > 40 ✓
  - **THEN**: Spawn 1 free peasant near Keep

**Result:** Player has ~10-12 peasants by minute 5

### **Mid Game (5-15 minutes):**

**Player Actions:**
1. **Build more housing** (Hovels → Clachans for efficiency)
2. **Build happiness buildings** (Inn, Chapel) to boost growth rate
3. **Build specialized production** (Farms, Mills, Workshops)
4. **Train military units** when peace time ends

**Automatic Growth:**
- With **Food > 200**: Growth rate increases to 45s/peasant
- With **happiness > 70**: Faster growth
- With **housing capacity**: Unlimited potential

**Result:** Player has 20-30 peasants managing economy

### **Late Game (15+ minutes):**

**Focus shifts** from population to:
- Military production
- Advanced resources (Iron Bars, Weapons)
- Defensive structures
- Expansion

---

## 🤖 AI Experience (Computer Opponents)

### **Game Start:**
```
✅ Keep spawns automatically
❌ NO starting peasants (AIManager handles this)
✅ Resource nodes spawn around base
```

**AI Build Order (AIManager):**
1. **Build Keep** (3s delay for visual loading)
2. **Build Storehouse** (2s delay)
3. **Build Granary** (3s delay)
4. **Wait 2 seconds** (total 10s before peasants)
5. **Start training peasants** from Keep

### **AI Peasant Training Logic:**

**Current implementation:**
- Spawns peasants 30-50 studs from Keep (avoids pathfinding issues)
- Only spawns if `state.hasKeep = true`
- Training happens in AIManager's main loop

**Recommended AI behavior:**

```lua
-- AI should follow similar rules to players:

-- Phase 1: Initial peasants (0-2 minutes)
Train 5 peasants immediately after Keep built
Assign to basic resource gathering

-- Phase 2: Expansion (2-5 minutes)
Build 2 Hovels (+10 housing capacity)
Train 5 more peasants
Build Storehouse, Granary

-- Phase 3: Economy (5-10 minutes)
Build more housing as needed
Automatic growth handles population increase
AI focuses on building production chains

-- Phase 4: Military (10+ minutes)
Housing maxed out at reasonable level
AI trains military units
Focus on defense and attacks
```

---

## 🔧 Recommended Implementation Changes

### **1. Remove Initial Player Peasants Option**

**Current:** Players spawn with 5 peasants at game start
**Issue:** This is fine, but should be configurable

**Recommendation: Add lobby setting**
```lua
-- In lobby settings:
startingPeasants = "None" | "Low" (3) | "Standard" (5) | "High" (8)
```

This allows:
- **"None"**: Players must train all peasants manually (hardcore mode)
- **"Standard"**: Current behavior (5 peasants) - balanced
- **"High"**: Faster start for casual gameplay

### **2. Keep AI Peasants Disabled at Game Start** ✅ DONE

**Current:** I already commented out `spawnAIInitialSetup()` peasant spawning
**Status:** Fixed! AI no longer spawns peasants before Keep is built

### **3. AI Should Train Initial Batch**

**Location:** `AIManager.luau` - after Keep is built

**Current code:**
```lua
-- AIManager trains peasants one at a time randomly
```

**Recommended change:**
```lua
-- After Keep built, train initial batch:
function AIManager.trainInitialPeasants(ownerId, count)
    count = count or 5

    for i = 1, count do
        -- Train peasant at Keep
        -- Use same spawning logic (30-50 studs away)
        task.wait(2) -- Stagger spawning
    end
end

-- In runAILoop(), after Keep built:
AIManager.buildKeep(ownerId)
task.wait(3)
AIManager.trainInitialPeasants(ownerId, 5) -- Train 5 starting peasants
task.wait(2)
-- Continue with buildings...
```

### **4. Automatic Growth Should Work for AI**

**Current:** PopulationManager only works for Player objects
**Issue:** AI uses `ownerId` (number), not Player object

**Recommendation: Extend PopulationManager for AI**

Add AI support:
```lua
-- PopulationManager.luau
function PopulationManager.createAI(ownerId, ownerName)
    populationData[ownerId] = {
        currentPopulation = 0,
        housingCapacity = 0,
        lastGrowthCheck = tick(),
        isOvercrowded = false,
        isAI = true,
        aiName = ownerName,
    }
end

-- Modify tryGrowPopulation to work with both Player and ownerId
function PopulationManager.tryGrowPopulationAI(ownerId)
    -- Same logic but uses ownerId instead of player.UserId
end
```

This allows AI to benefit from automatic population growth just like players!

---

## 📋 Housing Progression Strategy

### **Optimal Housing Build Order:**

**Player/AI Early Game:**
1. **Keep** (10 housing) - Free at start
2. **2x Hovel** (10 housing) - Cheap, fast (20 Wood total)
3. **Total:** 20 population capacity

**Mid Game:**
4. **2x Clachan** (16 housing) - Better value (30 Wood + 20 Stone)
5. **1x Inn** (3 housing + happiness) - Boosts growth rate
6. **Total:** 39 population capacity

**Late Game:**
7. **Monastery** (10 housing + happiness + production) - Expensive but powerful
8. **Chapel** (2 housing + happiness) - Small but helpful
9. **Total:** 51 population capacity

**Strategic Notes:**
- **Hovel** = Best early game (2 wood per person)
- **Clachan** = Best mid game (1.875 wood + 1.25 stone per person)
- **Inn/Chapel** = Build for happiness bonus (faster growth)
- **Monastery** = Late game luxury (produces Manuscripts)

---

## ⚖️ Balance Recommendations

### **Population Growth Rates:**

**Current:**
- Base: 1 peasant per 60 seconds
- With Food > 200: 1 peasant per 45 seconds

**Recommendation:**
```lua
-- Adjust growth rates for better balance:

Base rate: 90 seconds (slower early game)
With Food > 100: 60 seconds (standard)
With Food > 300: 45 seconds (abundant food)
With Happiness > 70: 30 seconds (very happy population)
With overcrowding: 0 seconds (no growth)
```

### **Housing Costs:**

**Current costs are good**, but consider:
- **Hovel**: 10 Wood (good starting cost)
- **Clachan**: 15 Wood + 10 Stone (fair upgrade)
- **Inn**: 35 Wood + 25 Stone (expensive, but has other benefits)

**Recommendation:** Keep current costs, they're well-balanced

### **Keep Training:**

**Current:** Keep can train Peasants manually
**Issue:** Should there be a cost?

**Recommendation: Add training cost**
```lua
-- In UnitData or Keep building data:
Peasant_training_cost = {
    Wood = 5,
    Food = 10,
}
Peasant_training_time = 10 -- seconds
```

This makes players choose between:
- **Build housing + wait for free growth** (slow but free)
- **Pay resources to train now** (fast but costs resources)

---

## 🎯 Final Recommended System

### **For Players:**
1. ✅ Start with 5 peasants + Keep (10 housing)
2. ✅ Can manually train peasants at Keep (costs 5 Wood + 10 Food)
3. ✅ Automatic growth every 60-90s if conditions met
4. ✅ Must build housing to unlock growth
5. ✅ Happiness affects growth rate

### **For AI:**
1. ✅ Start with Keep only (10 housing)
2. ✅ AIManager trains 5 initial peasants after Keep built
3. ✅ AI builds Hovels/Clachans for housing
4. ✅ Automatic growth works same as players
5. ✅ AI balances housing with economy needs

### **Key Differences:**
- **Players** get starting peasants for immediate gameplay
- **AI** trains peasants after Keep (prevents visual issues)
- **Both** benefit from automatic growth with same rules
- **Both** can manually train peasants at Keep for faster growth

---

## 🚀 Implementation Priority

### **Phase 1: Fix Current Issues** ✅ DONE
- [x] Disable AI initial peasant spawn in `GameManager`
- [x] AI spawns peasants only after Keep via `AIManager`

### **Phase 2: Add AI Initial Training** (Recommended Next)
- [ ] Create `AIManager.trainInitialPeasants()` function
- [ ] Call after Keep is built with 5 peasant count
- [ ] Stagger spawns by 2 seconds each

### **Phase 3: Extend PopulationManager for AI** (Optional)
- [ ] Add `PopulationManager.createAI()` for AI players
- [ ] Modify growth functions to work with `ownerId`
- [ ] AI benefits from automatic population growth

### **Phase 4: Add Peasant Training Cost** (Balance)
- [ ] Add resource cost to manual peasant training
- [ ] Gives players strategic choice between building housing or training directly
- [ ] AI uses same system for fair gameplay

### **Phase 5: Add Lobby Settings** (Polish)
- [ ] `startingPeasants` setting (None/Low/Standard/High)
- [ ] `populationGrowthRate` setting (Slow/Normal/Fast)
- [ ] Custom game balance for different playstyles

---

## 📊 Expected Player Progression

**With this system:**

| Time  | Action | Population | Housing |
|-------|--------|------------|---------|
| 0:00  | Game start | 5 peasants | 10 (Keep) |
| 1:00  | Built 2 Hovels | 5 | 20 |
| 1:30  | +1 auto growth | 6 | 20 |
| 2:00  | Trained 2 peasants | 8 | 20 |
| 3:00  | +1 auto growth | 9 | 20 |
| 4:30  | +1 auto growth | 10 | 20 |
| 5:00  | Built Clachan | 10 | 28 |
| 6:00  | +1 auto growth | 11 | 28 |
| 7:30  | +1 auto growth | 12 | 28 |
| 10:00 | Built Inn + Chapel | 13 | 33 |
| 15:00 | Natural growth | 20+ | 40+ |

**Result:** Smooth, predictable progression with player agency

---

## 💡 Design Philosophy Summary

### **Good RTS Population System:**

✅ **Player has control** - Can build housing and train units manually
✅ **Automatic assistance** - Natural growth prevents micromanagement
✅ **Resource management** - Housing costs resources, training costs resources
✅ **Strategic choices** - Fast expensive training vs slow free growth
✅ **Scalable** - Works for 1 player or 8 AI opponents
✅ **Balanced** - Early game not too slow, late game not too fast

### **Poor RTS Population System:**

❌ **Too automatic** - Players feel like spectators
❌ **Too manual** - Excessive micromanagement required
❌ **No strategy** - Only one optimal path
❌ **Imbalanced** - AI has unfair advantages or disadvantages

---

## 🎮 Comparison to Stronghold

Your system is very similar to **Stronghold's** design:

| Feature | Stronghold | Your Game |
|---------|-----------|-----------|
| **Starting peasants** | 8-12 | 5 (configurable) |
| **Housing buildings** | Hovel | Hovel, Clachan, Inn, etc. |
| **Auto growth** | Yes (with food + housing) | Yes (with food + housing + happiness) |
| **Manual training** | Yes (at Keep) | Yes (at Keep) |
| **Population cap** | Based on housing | Based on housing |
| **Happiness affects growth** | Yes | Yes |

**Your game adds:**
- More housing variety (Clachan, Monastery, etc.)
- Happiness system integration
- Better pathfinding with A* grid system

**This is excellent!** You're following proven RTS design principles.

---

## 🏁 Conclusion

**Current Status:** ✅ AI peasants fixed (no longer spawn before Keep)

**Recommended Next Steps:**
1. Add AI initial peasant training (5 peasants after Keep)
2. Consider adding peasant training cost (5 Wood + 10 Food)
3. Extend PopulationManager to work with AI for automatic growth

**Design Quality:** Your population system is well-designed and follows Stronghold's proven formula. The housing capacity system, automatic growth, and manual training options create good strategic depth.

**Fun Factor:** Players will enjoy:
- Building housing to expand population
- Balancing resources between economy and military
- Strategic choices (housing vs direct training)
- Watching their settlement grow organically

This is a solid foundation for an engaging RTS economy!
