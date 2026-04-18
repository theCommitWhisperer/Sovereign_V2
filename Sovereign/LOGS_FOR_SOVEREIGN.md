  23:23:45.110  
========================================  -  Server - TestRunner:42
  23:23:45.110    🧪 SOVEREIGN TEST SUITE  -  Server - TestRunner:43
  23:23:45.110  ========================================
  -  Server - TestRunner:44
  23:23:45.135   ▶ ⚠️ WARN: [Storage] Building FakeBuilding has no storage initialized (x2)  -  Server - DebugManager:49
  23:23:45.136   ▶ ⚠️ WARN: [ConsumptionManager] IntegrationPlayer_888100 is STARVING! (Duration: 30s) (x2)  -  Server - DebugManager:49
  23:23:45.136  ⚠️ WARN: [ConsumptionManager] IntegrationPlayer_888100 is STARVING! (Duration: 60s)  -  Server - DebugManager:49
  23:23:45.136  ⚠️ WARN: [ConsumptionManager] IntegrationPlayer_888100 is STARVING! (Duration: 30s)  -  Server - DebugManager:49
  23:23:45.137  ⚠️ WARN: [VictoryCondition] IntegrationPlayer_888200 suffered DEFEAT: Population Extinction!  -  Server - DebugManager:49
  23:23:45.137  ⚠️ WARN: [VictoryCondition] IntegrationPlayer_888200 suffered DEFEAT: Economic Collapse!  -  Server - DebugManager:49
  23:23:45.137  ⚠️ WARN: [VictoryCondition] IntegrationPlayer_888200 suffered DEFEAT: Keep Destroyed!  -  Server - DebugManager:49
  23:23:45.138  ⚠️ WARN: [HappinessManager] HappinessTest has low happiness! Production efficiency reduced.  -  Server - DebugManager:49
  23:23:45.139  ⚠️ WARN: [HappinessManager] HappinessTest has very low happiness! Production has halted.  -  Server - DebugManager:49
  23:23:45.139  ❌ ERROR: [HappinessManager] HappinessTest is in open revolt! Some units have become hostile.  -  Server - DebugManager:47
  23:23:45.139   ▶ ⚠️ WARN: [MapManager] Attempted to set invalid map: ThisMapDoesNotExist (x2)  -  Server - DebugManager:49
  23:23:45.140  ⚠️ WARN: [ProductionChain] Smelter cannot produce - not enough Iron_Ore  -  Server - DebugManager:49
  23:23:45.146  Test results:
[+] Server
   [+] BuildingSystem
      [+] Manager
         [+] BuildingValidation
            [+] addToStorage — safe defaults
               [+] does not error when called with a destroyed building reference
               [+] returns 0 when building has no storage record
            [+] getStorageAmount — safe defaults
               [+] returns 0 for a building with no storage record
               [+] returns 0 for an unknown resource type on an unknown building
            [+] hasStorageSpace — safe defaults
               [+] returns false for a building with no storage record
               [+] returns false for unknown resource on unknown building
            [+] takeFromStorage — safe defaults
               [+] returns 0 for unknown resource type
               [+] returns 0 when building has no storage record
   [+] Integration
      [+] EconomyIntegration
         [+] food consumption tick
            [+] deducts food proportional to peasant population
            [+] does not consume food when player has no population
            [+] returns false and starts starvation when food runs out
            [+] returns true when food is sufficient
            [+] starvation duration accumulates across multiple starving ticks
            [+] starvation resets when food is available again
         [+] seasonal food consumption multipliers
            [+] Spring produces more on farms than Autumn (via SeasonManager)
            [+] Winter consumes more food than Summer for the same population
         [+] tax collection
            [+] 0% tax rate produces no gold
            [+] accumulated gold from multiple collections
            [+] collecting taxes with 0 population gives 0 gold
            [+] gold earned scales with population and tax rate
      [+] VictoryIntegration
         [+] defeat: already won blocks defeat check
            [+] does not set hasLost if the player already won
         [+] defeat: Keep Destroyed
            [+] does NOT fire when Keep is alive in workspace
            [+] fires when Keep model has been removed from workspace
            [+] fires when playerData.Keep is nil
         [+] defeat: Population Extinction
            [+] does NOT fire during peace time even with 0 population
            [+] does NOT fire when peasants are alive
            [+] fires when population is 0 and peace time has expired
         [+] victory: already lost blocks victory check
            [+] does not set hasWon if the player already lost
         [+] victory: Economic Prosperity
            [+] does NOT fire at 999 Gold
            [+] fires when player accumulates 1000 Gold
         [+] victory: Population Boom
            [+] does NOT fire at 49 population
            [+] fires when population reaches 50
         [+] victory: Resource Hoarder
            [+] does NOT fire if any one resource is below 500
            [+] fires when player has 500+ Wood, Stone, and Food
   [+] Managers
      [+] CaravanManager
         [+] create and get
            [+] creates caravan data for a player without erroring
            [+] get returns data after create
            [+] initial caravansLost is 0
            [+] initial completedTrades is 0
         [+] sendCaravan when trade is disabled
            [+] sendCaravan returns false (blocked) when trade is disabled
         [+] setTradeEnabled / isTradeEnabled
            [+] can be disabled
            [+] can be re-enabled after disabling
            [+] defaults to enabled
            [+] reflects the lobby 'Ability to Trade = false' setting
      [+] FactionManager
         [+] areEnemies
            [+] returns false for Neutral factions
            [+] returns true when relationship is Enemy
         [+] createFaction
            [+] calling createFaction twice on the same name does not error
            [+] creates a faction without erroring
         [+] default init() relationships
            [+] all four player factions are enemies with each other
            [+] Player and Rebel are enemies
            [+] Player and Viking are enemies
         [+] setRelationship and getRelationship
            [+] defaults to Neutral for unset faction pairs
            [+] relationship is symmetric — A→B equals B→A
            [+] returns Neutral for completely unknown factions
            [+] sets and retrieves a relationship
      [+] HappinessManager
         [+] checkForRevolt — stage boundaries (no transition)
            [+] happiness 10-19 stays at stage 2 when already at stage 2
            [+] happiness 20-39 stays at stage 1 when already at stage 1
            [+] happiness < 10 stays at stage 3 when already at stage 3
            [+] happiness >= 40 keeps stage at 0 (boundary = exactly 40)
            [+] happiness exactly 10 maps to stage 2 (< 10 is false)
            [+] happiness exactly 20 maps to stage 1 (< 20 is false)
            [+] happiness of 50 keeps stage at 0
         [+] checkForRevolt — stage transitions
            [+] recovers back to stage 0 when happiness rises to 40 or above
            [+] transitions from stage 0 to stage 1 when happiness drops below 40
            [+] transitions to stage 2 when happiness drops below 20
            [+] transitions to stage 3 when happiness drops below 10
         [+] create and get
            [+] initializes with happiness = 50
            [+] initializes with revoltStage = 0 (no revolt)
            [+] returns nil for a player who never had data created
      [+] MapManager
         [+] getAvailableMaps
            [+] each entry is a non-empty string
            [+] returns a non-empty list of map names
         [+] getCurrentMap
            [+] MaxPlayers is between 1 and 4
            [+] returns a config table with required fields
            [+] Size is a positive number
         [+] getMapConfig
            [+] returns config for a valid map name
            [+] returns nil for an unknown map name
         [+] setMap and getCurrentMapName
            [+] getCurrentMapName is unchanged after a failed setMap
            [+] returns false for an unknown map name
            [+] sets a valid map and getCurrentMapName reflects it
      [+] PlayerManager
         [+] addResources
            [+] accumulates across multiple calls
            [+] adds resources to existing totals
            [+] ignores unknown resource keys without erroring
         [+] create and get
            [+] creates player data and retrieves it by UserId
            [+] initialises all resource slots to 0
            [+] initialises Buildings and Units as empty tables
            [+] initialises GameState to MainMenu
            [+] returns nil for a player that has not been created
         [+] deductResources
            [+] clamps at 0 — never goes negative
            [+] subtracts resources correctly
         [+] hasEnoughResources
            [+] returns false for a player with no data
            [+] returns false when a resource is insufficient
            [+] returns false when player has none of a required resource
            [+] returns true when player has enough of each resource
         [+] remove
            [+] remove on unknown player does not error
            [+] removes player data so get returns nil
      [+] PopulationManager
         [+] canGrowPopulation
            [+] returns false when housing capacity is 0
            [+] returns false when population equals housing capacity
            [+] returns true when housingCapacity exceeds currentPopulation
         [+] create and get
            [+] creates population data without erroring
            [+] get returns data after create
            [+] initial currentPopulation is 0
            [+] initial housingCapacity is 0
            [+] initial isOvercrowded is false
         [+] createAI
            [+] creates AI population data without erroring
         [+] getCurrentPopulation
            [+] counts non-military tagged instances in playerData.Units
            [+] returns 0 when player has no units
         [+] isOvercrowded
            [+] returns false by default
            [+] returns true when isOvercrowded flag is set
      [+] ProductionChainManager
         [+] canProduce
            [+] edge cases
               [+] returns false for a building with no BuildingType attribute
               [+] returns false for an unknown building type
            [+] passive producers
               [+] Potato Farm returns true — no inputs required
            [+] production chain buildings
               [+] Smelter returns false when storage is empty (0 Iron_Ore < 2 needed)
         [+] consumeInputs
            [+] Potato Farm succeeds (returns true) without consuming anything
            [+] returns false for a building with no BuildingType attribute
            [+] returns false for an unknown building type
            [+] Smelter fails (returns false) when it has no Iron_Ore in storage
         [+] getProductionStatus
            [+] edge cases
               [+] returns canProduce=false for a building with no type attribute
               [+] returns canProduce=false for an unknown building type
            [+] Potato Farm (passive producer)
               [+] canProduce is true
               [+] inputResource is nil (no inputs needed)
               [+] outputResource is 'Food'
            [+] Smelter (production chain)
               [+] canProduce is false when no Iron_Ore in storage
               [+] inputAvailable is 0 when storage is not initialised
               [+] inputNeeded is 2 (consumption_rate from GameData)
               [+] inputResource is 'Iron_Ore'
               [+] outputResource is 'Iron_Bars'
         [+] isProductionChainBuilding
            [+] Granary does not produce resources → false
            [+] Keep does not produce resources → false
            [+] Lumberjack is a passive resource producer → true
            [+] Potato Farm is a resource producer → true
            [+] Smelter is a resource producer → true
            [+] Storehouse does not produce resources → false
            [+] unknown type returns false
      [+] RevoltManager
         [+] calculateRevoltRisk
            [+] 100% tax = 50 risk points (maximum tax contribution)
            [+] adds 25 when player has no food
            [+] adds happiness deficit when happiness < 50
            [+] caps the happiness contribution at 50 (happiness=0)
            [+] clamps total risk at 100 when all factors are maxed
            [+] does NOT add the food penalty when food > 0
            [+] returns 0 for a player with no happiness/tax/revolt data
            [+] returns 0 when all factors are zero (happiness=50, 0% tax, food=1)
            [+] returns only the tax portion when happiness=50, food>0
            [+] tax rate scales linearly: 50% tax = 25 risk points
         [+] create and get
            [+] creates revolt data without erroring
            [+] initializes revoltRisk at 0
         [+] recordUnitLoss
            [+] can be called multiple times to accumulate risk
            [+] caps revoltRisk at 100 — cannot exceed maximum
            [+] does not error when called for an unknown player
            [+] increments revoltRisk by 1
      [+] SeasonManager
         [+] advanceSeason
            [+] advances through all four seasons in a cycle
         [+] create and get
            [+] creates season data without erroring
            [+] get returns data after create
            [+] initial season is a valid Season string
         [+] getSeasonEffects
            [+] returns an effects table for the current season
         [+] season effect values are gameplay-sensible
            [+] all seasons have positive food consumption multipliers
            [+] Summer happiness modifier is positive
            [+] Summer has the highest farm production (peak harvest)
            [+] Winter happiness modifier is negative
            [+] Winter has the highest food consumption (people need warmth)
      [+] TaxManager
         [+] collectTaxes
            [+] adds gold to player resources based on unit count and tax rate
            [+] does not error when collecting taxes
         [+] create and get
            [+] creates tax data without erroring
            [+] get returns data after create
            [+] initial tax rate is 0.1 (10%)
         [+] setTaxRate
            [+] 0% tax rate stores correctly
            [+] 100% tax rate stores correctly
            [+] clamps tax rate to a maximum of 1.0 (100%)
            [+] clamps tax rate to a minimum of 0.0 (0%)
            [+] sets a valid tax rate
      [+] VictoryConditionManager
         [+] create and setGameStarted
            [+] create initialises data for a player without erroring
            [+] get returns the initialised data after create
            [+] setGameStarted records peace time without erroring
            [+] setGameStarted with 0 stores peaceTimeSeconds as 0
         [+] getLossConditions
            [+] each condition has name, description, and check fields
            [+] includes Population Extinction and Keep Destroyed conditions
            [+] returns a non-empty table
         [+] getVictoryConditions
            [+] each condition has name, description, and check fields
            [+] returns a non-empty table
         [+] setVictoryMode
            [+] accepts all valid lobby victory condition values
            [+] accepts nil/unknown without erroring (defaults to Score)
      [+] WeatherManager
         [+] create and get
            [+] creates weather data without erroring
            [+] get returns data after create
            [+] initial weather is a valid WeatherType string
         [+] getFarmProductionMultiplier
            [+] returns a number (not nil) even before any weather change
            [+] returns a positive number
         [+] getMiningProductionMultiplier
            [+] returns a positive number
         [+] getWeatherEffects
            [+] Clear weather has farm multiplier of 1.0
            [+] Drought reduces farm production below 1.0
            [+] Rain boosts farm production above 1.0
            [+] returns an effects table with expected fields
            [+] Storm reduces mining production below 1.0
      [+] WorkerManager
         [+] assignWorkerToBuilding
            [+] does nothing and does not error when building is nil
            [+] does nothing and does not error when peasant is nil
            [+] does nothing for a building that does not require workers (Keep)
            [+] does nothing for an unknown building type without erroring
            [+] sets AssignedTo to the building type on the peasant
            [+] sets IsWorking=true on the peasant for a worker-requiring building
         [+] createHaulerTask
            [+] does not error even if the hauler was never registered as idle
            [+] marks the hauler as not-idle in IdlePeasantManager after assignment
            [+] sets IsHauling=true on the hauler model
         [+] setProductionModifier
            [+] accepts 0 (halt) without error
            [+] accepts 1.0 (full) without error
            [+] clamps negative values to 0
            [+] clamps values above 1.0 to 1.0
            [+] exists and is callable without error
[+] Shared
   [+] DebugManager
      [+] Manager
         [+] DebugManager
            [+] DebugManager
               [+] should allow enabling/disabling channels
               [+] should be a table
               [+] should create channels
               [+] should handle logging with data tables
               [+] should handle logging with Vector3 data
               [+] should log an info message without errors
               [+] should respect channel enabled flag
   [+] GameData
      [+] BuildingsData
         [+] BuildingsData
            [+] should contain essential buildings like Keep
            [+] should define components for the Keep
            [+] should have a 'cost' table for the Keep
            [+] should load and be a non-empty table
      [+] ResourcesData
         [+] ResourcesData
            [+] should contain essential resources like Wood and Gold
            [+] should have correct data types for its entries
            [+] should have positive max_carry_amount for tradeable resources
            [+] should load and be a non-empty table
      [+] UnitsData
         [+] UnitsData
            [+] should contain core units like Peasant and King
            [+] should have a 'cost' table for the Peasant unit
            [+] should have correct data types for a combat unit
            [+] should load and be a non-empty table
   [+] GameSettings
      [+] setGameSpeed / getSpeedMultiplier
         [+] defaults to Normal (1.0x) before any call
         [+] falls back to 1.0x for nil input
         [+] falls back to 1.0x for unknown speed strings
         [+] sets Fast to 2.0x
         [+] sets Normal to 1.0x
         [+] sets Slow to 0.5x
      [+] waitInterval
         [+] doubles wait time at Slow speed (ticks less often)
         [+] halves wait time at Fast speed (ticks more often)
         [+] handles fractional base seconds
         [+] returns base seconds unchanged at Normal speed
         [+] scales ConsumptionSystem cycle correctly across all speeds
234 passed, 0 failed, 0 skipped  -  Server - TextReporter:87
  23:23:45.146  
========================================  -  Server - TestRunner:53
  23:23:45.146    ✅ ALL TESTS PASSED  (234 passed, 0 skipped)  -  Server - TestRunner:55
  23:23:45.147  ========================================
  -  Server - TestRunner:59
  23:24:02.876  ⚠️ WARN: [LobbyManager] Player not in lobby: | RiffetyRaff  -  Server - DebugManager:49
  23:24:08.927  ⚠️ WARN: [UnitManager] No Dummy found in ServerStorage, creating simple model  -  Server - DebugManager:49
  23:24:15.405  ⚠️ WARN: [PathfindingIntegration] Unit Peasant_8820940408_3552 is on unwalkable cell (340,400), finding nearest walkable position  -  Server - DebugManager:49
  23:24:29.404  ⚠️ WARN: [Movement] Unit Peasant_8820940408_5285 appears stuck, recalculating path  -  Server - DebugManager:49
  23:24:31.486  ⚠️ WARN: [PathfindingIntegration] Unit Peasant_8820940408_3552 is on unwalkable cell (339,386), finding nearest walkable position  -  Server - DebugManager:49
  23:24:33.733  Disconnect from 127.0.0.1|57768  -  Studio
  23:24:34.332  ⚠️ WARN: [LobbyManager] Player not in lobby: | RiffetyRaff  -  Server - DebugManager:49
  23:24:34.413  ServerScriptService.Server.Managers.UnitManager:320: attempt to call a nil value  -  Server - UnitManager:320
  23:24:34.413  Stack Begin  -  Studio
  23:24:34.413  Script 'ServerScriptService.Server.Managers.UnitManager', Line 320  -  Studio - UnitManager:320
  23:24:34.413  Stack End  -  Studio
  23:24:34.414  ServerScriptService.Server.Managers.UnitManager:320: attempt to call a nil value  -  Server - UnitManager:320
  23:24:34.414  Stack Begin  -  Studio
  23:24:34.414  Script 'ServerScriptService.Server.Managers.UnitManager', Line 320  -  Studio - UnitManager:320
  23:24:34.414  Stack End  -  Studio
  23:24:34.414  ServerScriptService.Server.Managers.UnitManager:320: attempt to call a nil value  -  Server - UnitManager:320
  23:24:34.414  Stack Begin  -  Studio
  23:24:34.414  Script 'ServerScriptService.Server.Managers.UnitManager', Line 320  -  Studio - UnitManager:320
  23:24:34.414  Stack End  -  Studio
  23:24:34.414  ServerScriptService.Server.Managers.UnitManager:320: attempt to call a nil value  -  Server - UnitManager:320
  23:24:34.414  Stack Begin  -  Studio
  23:24:34.414  Script 'ServerScriptService.Server.Managers.UnitManager', Line 320  -  Studio - UnitManager:320
  23:24:34.414  Stack End  -  Studio
  23:24:34.414  ServerScriptService.Server.Managers.UnitManager:320: attempt to call a nil value  -  Server - UnitManager:320
  23:24:34.414  Stack Begin  -  Studio
  23:24:34.414  Script 'ServerScriptService.Server.Managers.UnitManager', Line 320  -  Studio - UnitManager:320
  23:24:34.414  Stack End  -  Studio