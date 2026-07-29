# Complete Game Design - Sovereign RTS

## 🎯 Game Overview

**Sovereign** is a medieval RTS (Real-Time Strategy) game inspired by Stronghold, where players build economies, manage populations, and compete against AI opponents.

---

## 🏆 Victory Conditions

Players can choose from multiple victory conditions in the lobby:

### **1. Conquest (Default)**
**Goal:** Destroy all enemy Keeps

**How to Win:**
- Train military units (Archers, Knights, Cavalry, etc.)
- Launch attacks on enemy bases
- Destroy enemy Keep

**How AI Wins:**
- AI trains combat units automatically
- AI launches attack waves every 60 seconds (if enough units)
- AI targets nearest enemy Keep
- If AI destroys your Keep → **You Lose**

**Loss Condition:**
- ❌ **Keep Destroyed** - Your Keep has been destroyed

---

### **2. Economic Victory** (Multiple Paths)

Players can win through economic prosperity without combat:

#### **A. Economic Prosperity**
- **Goal:** Accumulate 1000 Gold
- **Strategy:** Build markets, trade with caravans, tax peasants

#### **B. Population Boom**
- **Goal:** Reach 50 population
- **Strategy:** Build housing (Hovels, Clachans, Inns), produce food, maintain happiness

#### **C. Trade Empire**
- **Goal:** Complete 20 successful trade caravans
- **Strategy:** Build marketplaces, send caravans, protect trade routes

#### **D. Resource Hoarder**
- **Goal:** Have 500+ of each basic resource (Wood, Stone, Food)
- **Strategy:** Build resource production chains, expand economy

#### **E. Industrial Titan**
- **Goal:** Have 100+ Weapons and 100+ Iron Bars
- **Strategy:** Build iron mines, smelters, weaponsmiths, blacksmiths

---

### **3. Wonder Victory**
- **Goal:** Build and defend a Wonder for set duration
- **How:** Construct massive expensive Wonder building, survive attacks
- **Note:** Not yet fully implemented

---

### **4. Score Victory**
- **Goal:** Highest score after set time
- **Scoring:** Population, buildings, resources, military, trade
- **Note:** Not yet fully implemented

---

### **5. Regicide**
- **Goal:** Keep your King alive, kill enemy Kings
- **Player King:** Your character IS the King unit
- **How AI Wins:** Kill the player's King unit
- **How Player Wins:** Kill all enemy Kings
- **Note:** "If the King dies, you lose" (from UnitsData)

---

## ❌ Loss Conditions

### **Immediate Defeat:**

1. **Keep Destroyed** ⚔️
   - Your main building (Keep) is destroyed
   - Game Over immediately

2. **King Dies** (Regicide mode) 👑
   - Your King unit is killed
   - "If the King dies, you lose"

### **Economic Collapse:**

3. **Population Extinction** 👥
   - All peasants have died or left
   - No workers = can't gather resources = death spiral

4. **Economic Collapse** 💰
   - 0 Gold + 0 Food + no way to produce either
   - No farms + no resources = can't recover

5. **Prolonged Starvation** 🍞
   - Starving for more than 5 minutes straight
   - Food consumption > production for too long

---

## 🎮 Complete Game Flow

### **Phase 1: Early Game (0-5 minutes)**

#### **Player Actions:**
```
✅ Start with:
   - Keep (FREE)
   - 5 Peasants
   - Starting troops (based on settings)
   - Resource nodes nearby

✅ First objectives:
   1. Assign peasants to gather Wood
   2. Assign peasants to gather Food
   3. Build 1-2 Hovels (for +5-10 housing)
   4. Build Granary (food storage)
   5. Build Storehouse (Wood/Stone storage)

✅ Economy focus:
   - Keep Food > 50 (enables auto peasant growth)
   - Build housing before population cap
   - Balance Wood/Stone gathering
```

#### **AI Actions (Identical):**
```
✅ Starts with:
   - Keep (FREE)
   - 5 Peasants
   - Starting troops
   - Resource nodes nearby

✅ First objectives (automated):
   1. Build Storehouse (for resources)
   2. Build Granary (for food)
   3. Assign peasants to gather resources
   4. Build housing when population cap reached
   5. Train more peasants if housing available

✅ Economy focus (automated):
   - Maintain Food > 50
   - Build housing for population growth
   - Gather resources for military
```

---

### **Phase 2: Mid Game (5-15 minutes)**

#### **Player Actions:**
```
✅ Population growth:
   - Every 60s: Free peasant if Food > 50 + housing available
   - Manually train peasants at Keep (will cost resources in future)
   - Build Hovels/Clachans to increase capacity

✅ Economy expansion:
   - Build Farms (food production)
   - Build Woodcutter (wood production)
   - Build Quarry (stone production)
   - Build Mines (iron ore)

✅ Military preparation:
   - Build Barracks (train soldiers)
   - Build Blacksmith (produce weapons)
   - Train Archers, Knights, Cavalry
   - Build defensive walls

✅ Choose victory path:
   - Economic? Focus on trade, gold, resources
   - Military? Focus on army, weapons, attack
   - Population? Focus on housing, food, happiness
```

#### **AI Actions (Automated):**
```
✅ Population growth:
   - Every 60s: Free peasant (same rules as player)
   - Builds housing when population capped
   - Maintains Food > 50

✅ Economy expansion:
   - Builds resource production buildings
   - Builds storage when needed
   - Gathers resources automatically
   - (Currently gets small resource cheat - can be removed)

✅ Military buildup:
   - Builds Barracks
   - Trains combat units (Archers, Knights, etc.)
   - Based on difficulty: Easy (3 units), Medium (5 units), Hard (8 units)
   - Builds defenses

✅ AI strategy (personality-based):
   - 50% chance "economy bias" or "military bias"
   - Prefers specific unit type (random: Archer/Knight/Cavalry)
   - Aggression bonus 0-30% (randomized)
```

---

### **Phase 3: Late Game (15+ minutes)**

#### **Player Actions:**
```
✅ Victory push:
   - Economic victory: Reach gold/population/trade goals
   - Military victory: Attack enemy Keeps
   - Wonder victory: Build and defend Wonder
   - Regicide: Hunt enemy Kings

✅ Advanced economy:
   - Build advanced production (Blacksmiths, Armories)
   - Trade caravans for gold
   - Tax system for income
   - Resource chains (Iron Ore → Iron Bars → Weapons)

✅ Military operations:
   - Coordinate attacks on enemy bases
   - Defend against AI attacks
   - Siege enemy fortifications
   - Protect economy from raids
```

#### **AI Actions (Automated):**
```
✅ Attack waves:
   - Every 60 seconds: AI evaluates strength
   - If enough units (based on difficulty):
     * Finds nearest enemy target (Keep/units)
     * Commands all combat units to attack
     * Units use A* pathfinding to reach target

✅ Defensive responses:
   - Monitors for threats near base
   - Trains replacement units if army destroyed
   - Rebuilds destroyed buildings

✅ Economy maintenance:
   - Continues gathering resources
   - Trains replacement peasants
   - Builds additional housing/production
```

---

## 🤖 AI Objectives & Behavior

### **What is the AI Striving For?**

The AI has **multiple concurrent objectives** with dynamic priority:

### **1. Economic Foundation** (Always Active)
```lua
-- AI constantly works to maintain:
✅ Food > 50 (enables population growth)
✅ Housing capacity > current population
✅ Resource stockpiles (Wood, Stone, Iron)
✅ Peasants assigned to resource gathering
✅ Storage buildings for resources
```

### **2. Population Growth** (Always Active)
```lua
-- AI aims for sustainable population:
✅ Build housing when approaching cap
✅ Maintain food production for growth
✅ Every 60s: Free peasant spawns (if conditions met)
✅ Target population: 20-30 for sustainable economy
```

### **3. Military Buildup** (Difficulty-Based)
```lua
-- AI trains army based on difficulty:
Easy:   3-5 combat units before attacking
Medium: 5-8 combat units before attacking
Hard:   8-12 combat units before attacking

-- AI trains preferred unit type:
- Random choice: Archer, Knight, Cavalry, Macemen, Swordsman
- Builds Barracks to enable training
- Produces weapons at Blacksmith
```

### **4. Conquest Victory** (Primary Goal)
```lua
-- AI's main victory condition: Destroy enemy Keeps
Every 60 seconds:
  1. Count combat units (exclude peasants)
  2. Evaluate strength (Strong/Medium/Weak)
  3. If enough units → Launch attack wave
  4. Find nearest enemy Keep
  5. Command all combat units to attack

-- Adaptive attack threshold:
if AI is "Strong":
    Attack with smaller forces more frequently
elif AI is "Weak":
    Wait for larger army before attacking
```

### **5. Defensive Responses** (Reactive)
```lua
-- AI responds to threats:
✅ Check for enemies near base every 10s
✅ If attacked → train more units
✅ Rebuild destroyed buildings
✅ Reassign peasants from danger zones
```

---

## 📊 AI Difficulty Levels

### **Easy AI:**
```lua
- Start delay: 10 seconds
- Build interval: 60 seconds (slow construction)
- Train interval: 45 seconds (slow unit production)
- Attack wave size: 3 units minimum
- Resource cheat: Small (10-20 per cycle)
- Aggression: Low
```

### **Medium AI:**
```lua
- Start delay: 5 seconds
- Build interval: 30 seconds (moderate construction)
- Train interval: 20 seconds (moderate unit production)
- Attack wave size: 5 units minimum
- Resource cheat: Moderate (20-40 per cycle)
- Aggression: Medium
```

### **Hard AI:**
```lua
- Start delay: 3 seconds
- Build interval: 15 seconds (fast construction)
- Train interval: 10 seconds (fast unit production)
- Attack wave size: 8 units minimum
- Resource cheat: Large (40-80 per cycle)
- Aggression: High + random 0-30% bonus
```

---

## 🎯 Strategic Depth

### **Player Choices:**

1. **Economic vs Military**
   - Focus on economy → faster growth, vulnerable to attacks
   - Focus on military → strong army, slow economy
   - Balanced → slower but safer

2. **Housing Management**
   - Build housing early → population boom
   - Delay housing → more resources for military
   - Trade-off: population = economy power

3. **Victory Path Selection**
   - Conquest: Aggressive, risky, decisive
   - Economic: Passive, stable, requires defense
   - Population: Long-term, requires planning
   - Trade: Active, requires protection

4. **Resource Allocation**
   - Wood → buildings, basic economy
   - Stone → defenses, advanced buildings
   - Food → population growth
   - Gold → luxury, trade, victory
   - Iron → weapons, military

---

## 🔄 Game Loop (Every 10 Seconds)

### **Player Systems (Automatic):**
```lua
Every 5 seconds:
  - Update population stats
  - Update resource consumption
  - Update building production
  - Check victory/loss conditions

Every 60 seconds:
  - Attempt population growth (if Food > 50, housing available)
  - Check economic victory conditions
  - Update AI attack timers
```

### **AI Loop (Automated):**
```lua
Every 10 seconds:
  1. Give AI resources (cheat - adjustable)
  2. Attempt building construction (based on needs)
  3. Attempt unit training (peasants, military)
  4. Manage peasant assignments (gather resources)
  5. Check defensive status (respond to threats)
  6. Launch attack wave (if timer expired + enough units)
  7. Send scouts (every 45 seconds)
```

---

## 🏅 Winning Strategies

### **Against Easy AI:**
```
Strategy: Economic boom → Military rush
1. Build 5 Hovels quickly (housing for 35 population)
2. Wait for auto-growth to 30+ peasants
3. Mass produce Archers (cheap, effective)
4. Attack AI Keep around minute 10
5. AI won't have strong army yet → Easy win
```

### **Against Medium AI:**
```
Strategy: Defensive economy → Late game power
1. Build walls around Keep early
2. Build balanced economy (farms, mines, production)
3. Train defenders (Archers on walls)
4. Reach economic victory (1000 gold or 50 pop)
5. OR build massive army for late assault
```

### **Against Hard AI:**
```
Strategy: Fast military → Constant pressure
1. Rush to Barracks (sacrifice some economy)
2. Train Knights immediately (strong units)
3. Attack AI peasants (disrupt economy)
4. Build defenses to survive counter-attacks
5. Wear down AI through attrition
6. Final assault when AI weakened
```

---

## 🎮 Player Experience

### **What Makes This Fun:**

1. **Clear Progression**
   - Start: 5 peasants → Build economy
   - Mid: 20-30 peasants → Choose strategy
   - Late: 50+ population OR military victory

2. **Multiple Paths to Victory**
   - Military player: "I'll destroy them!"
   - Economic player: "I'll out-grow them!"
   - Trade player: "I'll out-trade them!"
   - All valid, all fun

3. **Automatic Systems Reduce Micro**
   - Auto population growth (every 60s)
   - Pathfinding handles movement
   - Production buildings work automatically
   - Can focus on strategy, not clicking

4. **AI Provides Challenge**
   - AI follows same rules (fair)
   - AI adapts to situation (smart)
   - AI has personality (variety)
   - Difficulty levels (scalable)

5. **Strategic Depth**
   - Resource management
   - Population balance
   - Military timing
   - Economic optimization
   - Defensive planning

---

## 📝 Design Philosophy

### **Inspired by Stronghold:**

✅ **Economic focus** - Population is your economy
✅ **Housing limits** - Must build housing to grow
✅ **Food/happiness** - Keep peasants fed and happy
✅ **Automatic growth** - Free peasants over time
✅ **Military from economy** - Strong economy = strong army
✅ **Castle building** - Walls, towers, defenses
✅ **Multiple victory paths** - Not just conquest

### **Modern Improvements:**

✅ **Better pathfinding** - A* grid-based, no stuck units
✅ **Fair AI** - Follows same rules as players
✅ **Automatic systems** - Less micromanagement
✅ **Clear victory conditions** - Know what you're working toward
✅ **Difficulty scaling** - AI adapts to player skill

---

## 🎯 Summary

**Game Goal:** Build a medieval settlement and achieve victory through conquest, economy, or population

**Player Role:** Lord/Lady managing economy, population, and military

**AI Role:** Opponent following same rules, working toward same goals

**Victory Conditions:**
- Destroy enemy Keeps (Conquest)
- Reach 1000 Gold (Economic Prosperity)
- Reach 50 Population (Population Boom)
- Complete 20 Trades (Trade Empire)
- Stockpile Resources (Resource Hoarder)
- Produce Weapons (Industrial Titan)

**Loss Conditions:**
- Keep Destroyed
- King Dies (Regicide)
- Population Extinct
- Economic Collapse
- Prolonged Starvation

**AI Objectives:**
1. Build sustainable economy
2. Grow population to 20-30
3. Train military units
4. Launch attacks every 60s (if strong enough)
5. Destroy enemy Keeps (primary goal)
6. Defend base from counter-attacks

**What Makes It Fun:**
- Multiple paths to victory
- Strategic resource management
- Population growth mechanics
- Fair AI opponents
- Clear progression
- Automatic helper systems

**This is a complete, well-designed RTS with clear goals, fair mechanics, and strategic depth!** 🏰⚔️
