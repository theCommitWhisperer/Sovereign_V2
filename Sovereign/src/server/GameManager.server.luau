--!strict
-- GameManager: Main server-side game coordinator

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local StarterPlayer = game:GetService("StarterPlayer")

-- Require game data (safe - read-only configs)
local GameData = require(ReplicatedStorage.Shared.GameData)
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)

local GameManagerDebug = DebugManager.createChannel("GameManager", true)

GameManagerDebug:info("Loading server-side managers...")

-- Disable automatic character spawning - players will spawn when they start the game
Players.CharacterAutoLoads = false
GameManagerDebug:info("CharacterAutoLoads disabled - players will spawn on game start")

-- Require from Managers subfolder (secure - server-only logic)
local Managers = script.Parent.Managers
local PlayerManager = require(Managers.PlayerManager)
local BuildingManager = require(Managers.BuildingManager)
local UnitManager = require(Managers.UnitManager)
local ResourceNodeManager = require(Managers.ResourceNodeManager)
local WorkerManager = require(Managers.WorkerManager)
local TrainingManager = require(Managers.TrainingManager)
local AIManager = require(Managers.AIManager)
local CombatManager = require(Managers.CombatManager) -- Updated CombatManager
local FormationManager = require(Managers.FormationManager)
local HappinessManager = require(Managers.HappinessManager)
local TaxManager = require(Managers.TaxManager)
local RevoltManager = require(Managers.RevoltManager)

-- Import FormationCohesion for formation movement tracking
local FormationCohesion = require(script.Parent.Systems.FormationCohesion)
local SpawnPointSystem = require(script.Parent.Systems.SpawnPointSystem)
local FactionManager = require(Managers.FactionManager)
local PopulationManager = require(Managers.PopulationManager)
local IdlePeasantManager = require(Managers.IdlePeasantManager)
local ConsumptionManager = require(Managers.ConsumptionManager)
local MaintenanceManager = require(Managers.MaintenanceManager)
local EventManager = require(Managers.EventManager)
local SeasonManager = require(Managers.SeasonManager)
local WeatherManager = require(Managers.WeatherManager)
local TradeManager = require(Managers.TradeManager)
local CaravanManager = require(Managers.CaravanManager)
local EconomyDashboardManager = require(Managers.EconomyDashboardManager)
local VictoryConditionManager = require(Managers.VictoryConditionManager)
local NotificationManager = require(Managers.NotificationManager)
local TestCommandManager = require(Managers.TestCommandManager)
local SpawnManager = require(Managers.SpawnManager)
local MapManager = require(Managers.MapManager)
local FogOfWarManager = require(Managers.FogOfWarManager)
local AbilityManager = require(Managers.AbilityManager)
local UpgradeManager = require(Managers.UpgradeManager)
local ResearchManager = require(Managers.ResearchManager)
local QuestManager = require(Managers.QuestManager)
local AchievementManager = require(Managers.AchievementManager)
local GameplayEnhancementManager = require(Managers.GameplayEnhancementManager)
local LobbyManager = require(Managers.LobbyManager)
local MapEditorManager = require(Managers.MapEditorManager)

CombatManager.init()
FormationManager.init()
HappinessManager.init()
TaxManager.init()
RevoltManager.init()
FactionManager.init()
PopulationManager.init()
ConsumptionManager.init()
MaintenanceManager.init()
EventManager.init()
SeasonManager.init()
WeatherManager.init()
TradeManager.init()
CaravanManager.init()
EconomyDashboardManager.init()
VictoryConditionManager.init()
NotificationManager.init()
AbilityManager.init()
UpgradeManager.init()
ResearchManager.init()
QuestManager.init()
AchievementManager.init()
GameplayEnhancementManager.init()

-- Require from Systems subfolder
local Systems = script.Parent.Systems
local PathfindingIntegration = require(Systems.PathfindingIntegration)
local MovementSystem = require(Systems.MovementSystem)
local VikingRaidSystem = require(Systems.VikingRaidSystem)
local PopulationSystem = require(Systems.PopulationSystem)
local ConsumptionSystem = require(Systems.ConsumptionSystem)
local MaintenanceSystem = require(Systems.MaintenanceSystem)
local EventSystem = require(Systems.EventSystem)
local SeasonSystem = require(Systems.SeasonSystem)
local WeatherSystem = require(Systems.WeatherSystem)
local TradeSystem = require(Systems.TradeSystem)
local CaravanSystem = require(Systems.CaravanSystem)
local DashboardSystem = require(Systems.DashboardSystem)
local VictorySystem = require(Systems.VictorySystem)
local WallSystemServer = require(Systems.WallSystemServer)
local TerrainGenerator = require(Systems.TerrainGenerator)

-- Initialize pathfinding first (required by MovementSystem)
GameManagerDebug:info("Initializing A* grid-based pathfinding...")
local currentMap = MapManager.getCurrentMap()
local mapSize = currentMap and currentMap.Size or 1024
PathfindingIntegration.initialize(mapSize)
GameManagerDebug:info("Pathfinding initialized for map size: " .. mapSize)

-- Initialize systems
PopulationSystem.init()
ConsumptionSystem.init()
MaintenanceSystem.init()
EventSystem.init()
SeasonSystem.init()
WeatherSystem.init()
TradeSystem.init()
CaravanSystem.init()
DashboardSystem.init()
VictorySystem.init()

GameManagerDebug:info("Managers loaded successfully")
GameManagerDebug:info("Server starting...")

-- Create RemoteEvent for game actions
local RemoteEvents = Instance.new("Folder")
RemoteEvents.Name = "RemoteEvents"
RemoteEvents.Parent = ReplicatedStorage

local GameEvent = Instance.new("RemoteEvent")
GameEvent.Name = "GameEvent"
GameEvent.Parent = RemoteEvents

local GetStatsEvent = Instance.new("RemoteEvent")
GetStatsEvent.Name = "GetStats"
GetStatsEvent.Parent = RemoteEvents

local CheckVisibilityFunc = Instance.new("RemoteFunction")
CheckVisibilityFunc.Name = "CheckVisibility"
CheckVisibilityFunc.Parent = RemoteEvents

-- Create LobbyEvent for multiplayer lobby system
local LobbyEvent = Instance.new("RemoteEvent")
LobbyEvent.Name = "LobbyEvent"
LobbyEvent.Parent = RemoteEvents

-- Create MapEditorEvent for map editor system
local MapEditorEvent = Instance.new("RemoteEvent")
MapEditorEvent.Name = "MapEditorEvent"
MapEditorEvent.Parent = RemoteEvents

GameManagerDebug:info("RemoteEvents created")

-- Initialize systems that depend on RemoteEvents
WallSystemServer.initialize()
TestCommandManager.init()
GameManagerDebug:info("RemoteEvents-dependent systems initialized")

-- Start fog of war updates
FogOfWarManager.startUpdates()
GameManagerDebug:info("FogOfWarManager updates started")

-- Handle visibility checks from client
CheckVisibilityFunc.OnServerInvoke = function(player: Player, objectType: string, object: Instance): boolean
	if objectType == "Unit" and object:IsA("Model") then
		return FogOfWarManager.isUnitVisible(player, object)
	elseif objectType == "Building" and object:IsA("Model") then
		return FogOfWarManager.isBuildingVisible(player, object)
	end
	return false
end

-- Helper function to find a unit model by its UnitId (which is the Model.Name in V2)
local function findUnit(unitId: string): Model?
	local unitsFolder = Workspace:FindFirstChild("Units")
	if unitsFolder then
		return unitsFolder:FindFirstChild(unitId)
	end
	return nil
end

-- Helper function to setup King health monitoring
local function setupKingHealthMonitoring(player: Player, character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	-- Send initial health update
	GameEvent:FireClient(player, "KingHealthUpdate", {
		health = humanoid.Health,
		maxHealth = humanoid.MaxHealth,
	})

	-- Listen for health changes
	local healthConnection = humanoid.HealthChanged:Connect(function(health)
		GameEvent:FireClient(player, "KingHealthUpdate", {
			health = math.floor(health),
			maxHealth = humanoid.MaxHealth,
		})
	end)

	-- Handle death
	local deathConnection = humanoid.Died:Connect(function()
		-- GameManagerDebug:warn(`King {player.Name} has died!`)
		GameEvent:FireClient(player, "KingHealthUpdate", {
			health = 0,
			maxHealth = humanoid.MaxHealth,
		})

		-- Respawn the King after 10 seconds
		task.delay(10, function()
			if player and player.Parent then
				local playerData = PlayerManager.get(player)
				if playerData and playerData.SpawnPoint then
					GameManagerDebug:info(`Respawning King for {player.Name}`)

					-- Respawn character
					player:LoadCharacter()
					local newCharacter = player.Character or player.CharacterAdded:Wait()
					local humanoidRootPart = newCharacter:WaitForChild("HumanoidRootPart") :: BasePart
					humanoidRootPart.CFrame = playerData.SpawnPoint * CFrame.new(0, 3, 0)

					-- Re-tag as King
					newCharacter:SetAttribute("OwnerId", player.UserId)
					newCharacter:SetAttribute("UnitType", "King")
					newCharacter:SetAttribute("IsKing", true)

					-- Notify client of respawn
					GameEvent:FireClient(player, "KingRespawned", {
						message = "Your King has been resurrected!",
					})

					GameManagerDebug:info(`King respawned for {player.Name}`)
				end
			end
		end)
	end)

	-- Clean up connections when character is removed
	character.AncestryChanged:Connect(function(_, parent)
		if not parent then
			healthConnection:Disconnect()
			deathConnection:Disconnect()
		end
	end)

	GameManagerDebug:info(`King health monitoring setup for {player.Name}`)
end

-- Player joined - create their data
Players.PlayerAdded:Connect(function(player)
	PlayerManager.create(player)
	FogOfWarManager.init(player)
	QuestManager.initializePlayerQuests(player)
	AchievementManager.initializePlayer(player)
	GameManagerDebug:info(`{player.Name} joined - character will spawn when game starts`)

	-- Monitor character respawns for health bar updates
	player.CharacterAdded:Connect(function(character)
		local playerData = PlayerManager.get(player)
		if playerData and playerData.GameState == "InGame" then
			-- Re-tag character as King after respawn
			character:SetAttribute("OwnerId", player.UserId)
			character:SetAttribute("UnitType", "King")
			character:SetAttribute("IsKing", true)

			-- Setup health monitoring for respawned character
			setupKingHealthMonitoring(player, character)
			GameManagerDebug:info(`{player.Name} character respawned and re-tagged as King`)
		end
	end)
end)

-- Player left - clean up
Players.PlayerRemoving:Connect(function(player)
	SpawnManager.removePlayer(player.UserId)
	FogOfWarManager.cleanup(player)
	PlayerManager.remove(player)
end)

-- Helper function to calculate starting resources based on lobby setting
local function calculateStartingResources(setting: string, resourceType: string): number
	local multipliers = {
		Low = 0.5,
		Standard = 1.0,
		High = 2.0,
	}

	local baseValues = {
		Wood = 400,
		Stone = 200,
		Gold = 500,
		Food = 300,
		Iron_Bars = 15,
		Weapons = 8,
	}

	local multiplier = multipliers[setting] or 1.0
	local baseValue = baseValues[resourceType] or 0
	return math.floor(baseValue * multiplier)
end

-- Helper function to calculate starting troop count based on lobby setting
local function calculateTroopCount(setting: string): number
	local counts = {
		None = 0,
		Low = 2,
		Standard = 4,
		High = 8,
	}
	return counts[setting] or 4
end

local function spawnInitialSetup(player: Player, factionData: any, spawnPointOverride: CFrame?, lobbySettings: any)
	local spawnPoint = spawnPointOverride or factionData.SpawnPoint

	-- 1. Player's character IS the King - we'll tag it when character loads
	GameManagerDebug:info(`Player {player.Name} will be the King (character-based)`)

	-- 2. NO KEEP SPAWNED - Player must place their Keep manually
	-- The first building they place MUST be a Keep
	GameManagerDebug:info(`{player.Name} will need to place their Keep manually`)

	-- 3. Spawn starting troops (if peace time is off, otherwise queue them)
	local troopCount = calculateTroopCount(lobbySettings.startingTroops or "Standard")
	local troopTypes = { "Archer", "Knight", "Light_Cavalry", "Macemen" }

	if troopCount > 0 then
		-- Check if peace time is active
		local peaceTimeActive = lobbySettings.peaceTime and lobbySettings.peaceTime ~= "None"

		if not peaceTimeActive then
			-- Spawn troops immediately
			for i = 1, troopCount do
				local troopType = troopTypes[((i - 1) % #troopTypes) + 1]
				local angle = (math.pi * 2 * i) / troopCount
				local offset = Vector3.new(math.cos(angle) * 20, 0, math.sin(angle) * 20)
				local troopSpawnPos = spawnPoint.Position + offset
				UnitManager.createUnit(troopType, player.UserId, troopSpawnPos, factionData.Name)
			end
			GameManagerDebug:info(`Spawned {troopCount} troops for {player.Name}`)
		else
			-- Queue troops to spawn after peace time ends
			local peaceTimeMinutes = 0
			local minutes = lobbySettings.peaceTime:match("(%d+)")
			if minutes then
				peaceTimeMinutes = tonumber(minutes) or 10
			end

			local peaceTimeSeconds = peaceTimeMinutes * 60

			-- Schedule troop spawn after peace time
			task.delay(peaceTimeSeconds, function()
				if player and player.Parent then
					local playerData = PlayerManager.get(player)
					if playerData and playerData.SpawnPoint then
						for i = 1, troopCount do
							local troopType = troopTypes[((i - 1) % #troopTypes) + 1]
							local angle = (math.pi * 2 * i) / troopCount
							local offset = Vector3.new(math.cos(angle) * 20, 0, math.sin(angle) * 20)
							local troopSpawnPos = playerData.SpawnPoint.Position + offset
							UnitManager.createUnit(troopType, player.UserId, troopSpawnPos, factionData.Name)
						end

						GameManagerDebug:info(`Peace time ended - spawned {troopCount} queued troops for {player.Name}`)

						-- Notify client
						GameEvent:FireClient(player, "PeaceTimeEnded", {
							message = "Peace time has ended - your troops have arrived!",
							troopsSpawned = troopCount,
						})
					end
				end
			end)

			GameManagerDebug:info(
				`{troopCount} troops queued for {player.Name} (will spawn after {peaceTimeMinutes} minutes)`
			)
		end
	end

	-- 4. Spawn resource nodes in distinct areas around the spawn
	-- Wooded area (northwest of spawn)
	local woodAreaCenter = spawnPoint.Position + Vector3.new(-80, 0, 80)
	ResourceNodeManager.spawnNodesNearPosition(woodAreaCenter, 60, "Wood", 25)

	-- Stone area (northeast of spawn)
	local stoneAreaCenter = spawnPoint.Position + Vector3.new(80, 0, 80)
	ResourceNodeManager.spawnNodesNearPosition(stoneAreaCenter, 50, "Stone", 20)

	-- Fertile land (southwest of spawn)
	local fertileAreaCenter = spawnPoint.Position + Vector3.new(-80, 0, -80)
	ResourceNodeManager.spawnNodesNearPosition(fertileAreaCenter, 50, "Food", 15)

	-- Iron area (southeast of spawn)
	local ironAreaCenter = spawnPoint.Position + Vector3.new(80, 0, -80)
	ResourceNodeManager.spawnNodesNearPosition(ironAreaCenter, 40, "Iron_Ore", 12)

	GameManagerDebug:info(
		`Spawned {factionData.StartingPeasants} peasants and resource nodes for {player.Name} in {factionData.Name}`
	)
end

-- AI-specific spawn function (doesn't require Player object)
local function spawnAIInitialSetup(ownerId: number, ownerName: string, factionData: any, spawnPoint: CFrame, lobbySettings: any)
	GameManagerDebug:info("AI " .. ownerName .. " spawning as " .. factionData.Name)

	-- 1. Spawn Keep at the spawn point (AI gets Keep at game start, same as players)
	local keep = BuildingManager.createBuilding(ownerId, "Keep", spawnPoint, nil, nil, true)
	if keep then
		GameManagerDebug:info("Spawned Keep for AI " .. ownerName)

		-- Spawn starting peasants using SpawnPointSystem (same as player implementation)
		local peasantCount = 3
		local spawnPositions = SpawnPointSystem.getSpawnPositions(keep, {
			pattern = "circle",
			radius = 12,
			count = peasantCount,
			offset = Vector3.new(0, 0, 0),
		})

		GameManagerDebug:info(`Got {#spawnPositions} spawn positions from SpawnPointSystem for AI {ownerName}`)

		if #spawnPositions > 0 then
			for i, position in ipairs(spawnPositions) do
				local peasant = UnitManager.createUnit("Peasant", ownerId, position, factionData.Name)
				if peasant then
					GameManagerDebug:info(`Spawned peasant {i}/{peasantCount} for AI {ownerName}`)
				else
					GameManagerDebug:warn(`Failed to spawn peasant {i} for AI {ownerName}`)
				end
			end
			GameManagerDebug:info(`Spawned {#spawnPositions} peasants around Keep for AI {ownerName}`)
		else
			-- Fallback: spawn at building position if no SpawnPoint found
			GameManagerDebug:warn(`No SpawnPoint found in Keep for AI {ownerName}, using fallback spawn`)
			local keepPos = keep.PrimaryPart.Position
			for i = 1, peasantCount do
				local angle = (math.pi * 2 * (i - 1)) / peasantCount
				local offset = Vector3.new(math.cos(angle) * 12, 0, math.sin(angle) * 12)
				local position = keepPos + offset
				UnitManager.createUnit("Peasant", ownerId, position, factionData.Name)
			end
			GameManagerDebug:info(`Spawned {peasantCount} peasants using fallback for AI {ownerName}`)
		end
	else
		GameManagerDebug:warn("Failed to spawn Keep for AI " .. ownerName)
	end

	-- Wait to ensure Keep is fully registered before spawning troops
	-- 2. No starting troops for AI - they will train units as needed
	-- Note: AI starts with only their Keep and will build/train units through normal gameplay

	-- 3. Spawn resource nodes in distinct areas around the spawn
	local woodAreaCenter = spawnPoint.Position + Vector3.new(-80, 0, 80)
	ResourceNodeManager.spawnNodesNearPosition(woodAreaCenter, 60, "Wood", 25)

	local stoneAreaCenter = spawnPoint.Position + Vector3.new(80, 0, 80)
	ResourceNodeManager.spawnNodesNearPosition(stoneAreaCenter, 50, "Stone", 20)

	local fertileAreaCenter = spawnPoint.Position + Vector3.new(-80, 0, -80)
	ResourceNodeManager.spawnNodesNearPosition(fertileAreaCenter, 50, "Food", 15)

	local ironAreaCenter = spawnPoint.Position + Vector3.new(80, 0, -80)
	ResourceNodeManager.spawnNodesNearPosition(ironAreaCenter, 40, "Iron_Ore", 12)

	GameManagerDebug:info(
		"Spawned Keep and resource nodes for AI " .. ownerName .. " in " .. factionData.Name
	)
end

-- Handle game events from client
GameEvent.OnServerEvent:Connect(function(player, action, data)
	GameManagerDebug:info(`Received event from {player.Name}: {action}`)

	local playerData = PlayerManager.get(player)
	if not playerData then
		GameManagerDebug:warn(`No player data for {player.Name}`)
		return
	end

	if action == "GetStats" then
		local economySnapshot = EconomyDashboardManager.getSnapshot(player)
		local combatUnits = CombatManager.getActiveCombatUnits()
		local combatStats = {
			totalUnits = 0,
			totalHealth = 0,
			toalMaxHealth = 0,
			totalDamage = 0,
			totalArmor = 0,
			totalMorale = 0,
		}

		for _, unit in pairs(combatUnits) do
			if unit.owner == player.UserId then
				combatStats.totalUnits = combatStats.totalUnits + 1
				combatStats.totalHealth = combatStats.totalHealth + unit.health
				combatStats.toalMaxHealth = combatStats.toalMaxHealth + unit.maxHealth
				combatStats.totalDamage = combatStats.totalDamage + unit.attackDamage
				combatStats.totalArmor = combatStats.totalArmor + unit.armor
				combatStats.totalMorale = combatStats.totalMorale + unit.morale
			end
		end

		GetStatsEvent:FireClient(player, {
			economy = economySnapshot,
			combat = combatStats,
		})
		return
	end

	if action == "StartGame" then
		-- Prevent multiple game starts
		if playerData.GameState == "InGame" then
			GameManagerDebug:warn(`{player.Name} already in game, ignoring duplicate StartGame event`)
			return
		end

		GameManagerDebug:info(`{player.Name} starting game...`)
		-- Get game settings from data
		local settings = typeof(data) == "table" and data or {}
		local vikingRaidsEnabled = settings.vikingRaids or false
		local peaceTimeStr = settings.peaceTime or "10 minutes"
		local selectedMap = settings.map or "ClassicPlains"
		local showTutorial = if settings.showTutorial ~= nil then settings.showTutorial else true
		local factionFromSettings = settings.faction -- From multiplayer lobby

		-- Set the active map and configure SpawnManager
		if not MapManager.setMap(selectedMap) then
			GameManagerDebug:warn(`Invalid map selected: {selectedMap}, using default`)
			selectedMap = "ClassicPlains"
			MapManager.setMap(selectedMap)
		end

		local mapConfig = MapManager.getCurrentMap()
		SpawnManager.setMapConfig(mapConfig)
		GameManagerDebug:info(`Map loaded: {mapConfig.Name} ({mapConfig.Size}x{mapConfig.Size})`)

		-- Generate the visual terrain for the map
		TerrainGenerator.generate(mapConfig)

		-- Parse peace time (format: "10 minutes")
		local peaceTimeMinutes = 0 -- default
		local minutes = peaceTimeStr:match("(%d+)")
		if minutes then
			peaceTimeMinutes = tonumber(minutes) or 10
		end

		GameManagerDebug:info(`Viking Raids: {vikingRaidsEnabled}, Peace Time: {peaceTimeMinutes} minutes`)

		if vikingRaidsEnabled then
			-- Enable Viking Raids for this player
			VikingRaidSystem.enableRaids(player.UserId, peaceTimeMinutes)
			GameManagerDebug:info(`Viking Raids enabled for {player.Name} (peace time: {peaceTimeMinutes} minutes)`)
		end

		-- Assign player to a spawn zone using SpawnManager
		local spawnZone = SpawnManager.assignPlayerToSpawn(player.UserId)

		-- Use faction from lobby if provided, otherwise map spawn zones to factions
		local factionName = factionFromSettings
		if not factionName then
			local spawnToFaction = {
				[1] = "Kingdom", -- Northwest
				[2] = "Empire", -- Northeast
				[3] = "Tribes", -- Southwest
				[4] = "IronLegion", -- Southeast
			}
			factionName = spawnToFaction[spawnZone] or "Kingdom"
		end

		local factionData = GameData.Factions[factionName]

		-- Override spawn point with zone-specific spawn
		local zoneSpawn = SpawnManager.getPlayerSpawnPoint(player.UserId)

		playerData.Faction = factionName
		playerData.SpawnPoint = zoneSpawn
		playerData.GameState = "InGame"

		GameManagerDebug:info(`Assigned {player.Name} to spawn zone {spawnZone} ({factionName})`)

		-- Set starting resources dynamically based on lobby settings
		playerData.Resources.Wood = calculateStartingResources(settings.startingResources or "Standard", "Wood")
		playerData.Resources.Stone = calculateStartingResources(settings.startingResources or "Standard", "Stone")
		playerData.Resources.Gold = calculateStartingResources(settings.startingGold or "Standard", "Gold")
		playerData.Resources.Food = calculateStartingResources(settings.startingFood or "Standard", "Food")
		playerData.Resources.Iron_Bars =
			calculateStartingResources(settings.startingResources or "Standard", "Iron_Bars")
		playerData.Resources.Weapons = calculateStartingResources(settings.startingResources or "Standard", "Weapons")

		-- Spawn initial setup with zone spawn point
		spawnInitialSetup(player, factionData, zoneSpawn, settings)

		-- Load character now (Players.CharacterAutoLoads is false)
		player:LoadCharacter()
		GameManagerDebug:info(`Loading character for {player.Name}`)

		-- Wait for character and teleport to spawn zone
		local character = player.Character or player.CharacterAdded:Wait()
		local humanoidRootPart = character:WaitForChild("HumanoidRootPart") :: BasePart
		humanoidRootPart.CFrame = zoneSpawn * CFrame.new(0, 3, 0)

		-- Tag the player's character as King (can't change name due to security restrictions)
		character:SetAttribute("OwnerId", player.UserId)
		character:SetAttribute("UnitType", "King")
		character:SetAttribute("IsKing", true)

		GameManagerDebug:info(`Character spawned and teleported {player.Name} to spawn zone {spawnZone} (tagged as King)`)

		-- Setup King health monitoring
		setupKingHealthMonitoring(player, character)

		-- Notify client
		GameEvent:FireClient(player, "GameStarted", {
			faction = factionName,
			resources = playerData.Resources,
			showTutorial = showTutorial,
		})

		-- Send immediate economy dashboard update
		task.wait(0.1) -- Brief delay to ensure all data is initialized
		EconomyDashboardManager.sendUpdate(player)

		GameManagerDebug:info(`{player.Name} spawned as {factionName}`)

		-- Spawn AI players if any from multiplayer lobby (check happens on first player only)
		local aiPlayers = LobbyManager.getAIPlayersForGame()
		if aiPlayers and #aiPlayers > 0 then
			GameManagerDebug:info(`Spawning {#aiPlayers} AI players for multiplayer game`)
			for _, aiData in ipairs(aiPlayers) do
				-- Assign spawn zone and get spawn point
				local aiSpawnZone = SpawnManager.assignPlayerToSpawn(aiData.UserId)
				local aiSpawnPoint = SpawnManager.getPlayerSpawnPoint(aiData.UserId)
				local aiFactionData = GameData.Factions[aiData.Faction]

				if not aiFactionData then
					GameManagerDebug:warn(`Unknown faction for AI: {aiData.Faction}`)
					continue
				end

				-- Spawn initial setup for AI (units, troops, resources)
				spawnAIInitialSetup(aiData.UserId, aiData.Name, aiFactionData, aiSpawnPoint, settings)

				-- Register AI with AIManager for autonomous behavior
				AIManager.registerAI(aiData.UserId, aiData.Name, aiData.Faction, aiSpawnPoint)

				GameManagerDebug:info(`Spawned AI player {aiData.Name} as {aiData.Faction} in spawn zone {aiSpawnZone}`)
			end

			-- Clear AI players after spawning (so they don't spawn again for other players)
			LobbyManager.clearAIPlayers()
			GameManagerDebug:info("AI players spawned and cleared from lobby")
		end
	elseif action == "StartPlacement" then
		GameManagerDebug:info(`{player.Name} wants to place: {data}`)

		-- Client wants to start placing a building
		if typeof(data) == "string" then
			local buildingInfo = GameData.Buildings[data]
			if not buildingInfo then
				GameManagerDebug:warn(`Unknown building: {data}`)
				return
			end

			-- Check if player has any buildings (Keep is required first)
			local hasBuildings = false
			local hasKeep = false
			for _, building in playerData.Buildings do
				if building and building.Parent then
					hasBuildings = true
					-- Check if building name starts with "Keep" (handles "Keep_12345" etc)
					if string.match(building.Name, "^Keep") then
						hasKeep = true
						break
					end
				end
			end

			-- Enforce Keep placement requirement
			if not hasKeep and data ~= "Keep" then
				GameManagerDebug:warn(`{player.Name} must place a Keep first`)
				GameEvent:FireClient(player, "Error", {
					message = "You must place your Keep before other buildings!",
				})
				return
			end

			-- First building (Keep) is always free
			local isFirstBuilding = not hasBuildings and data == "Keep"

			if isFirstBuilding or PlayerManager.hasEnoughResources(player, buildingInfo.cost) then
				if isFirstBuilding then
					GameManagerDebug:info(`Approving FREE Keep placement for {player.Name} (first building)`)
				else
					GameManagerDebug:info(`Approving placement for {player.Name}: {data}`)
				end
				-- Tell client to start placement mode
				GameEvent:FireClient(player, "StartPlacement", data)
			else
				GameManagerDebug:warn(`{player.Name} cannot afford {data}`)
				GameManagerDebug:info(`Current resources:`, playerData.Resources)
				GameManagerDebug:info(`Required:`, buildingInfo.cost)
				GameEvent:FireClient(player, "Error", {
					message = `Not enough resources to build {data}`,
				})
			end
		end
	elseif action == "PlacementEnded" then
		-- Client canceled placement mode - notify all client systems
		GameManagerDebug:info(`{player.Name} ended placement mode`)
		GameEvent:FireClient(player, "PlacementEnded")
	elseif action == "PlaceBuilding" then
		GameManagerDebug:info(`{player.Name} placing building:`, data)

		-- Client confirmed building placement
		if typeof(data) == "table" and data.buildingName and data.position then
			local buildingInfo = GameData.Buildings[data.buildingName]
			if not buildingInfo then
				GameManagerDebug:warn(`Unknown building: {data.buildingName}`)
				return
			end

			-- Check if this is the first building (Keep should be free)
			local hasBuildings = false
			for _, building in playerData.Buildings do
				if building and building.Parent then
					hasBuildings = true
					break
				end
			end

			local isFirstBuilding = not hasBuildings and data.buildingName == "Keep"

			if isFirstBuilding or PlayerManager.hasEnoughResources(player, buildingInfo.cost) then
				-- Deduct resources (unless it's the free first Keep)
				if not isFirstBuilding then
					PlayerManager.deductResources(player, buildingInfo.cost)
				else
					GameManagerDebug:info(`Placing FREE Keep for {player.Name} (first building)`)
				end

				-- Create the CFrame from data (use sent CFrame if available)
				local cframe = data.cframe
					or CFrame.new(data.position) * CFrame.Angles(0, math.rad(data.rotationY or 0), 0)

				-- Create the building (pass wall piece type and rotation for manual selection)
				local building = BuildingManager.createBuilding(
					player,
					data.buildingName,
					cframe,
					data.wallPieceType,
					data.manualRotation
				)

				if building then
					-- DEBUG: log final building position for ground alignment checks
					-- if building.PrimaryPart then
					-- 	print("[DEBUG] Building placed:", data.buildingName, "at", building.PrimaryPart.Position)
					-- end

					-- Special handling for Keep placement
					if data.buildingName == "Keep" then
						GameManagerDebug:info(`Keep placed by {player.Name}, spawning initial peasants`)

						-- Get player's faction
						local playerFaction = playerData.Faction or "Kingdom"

						-- Use SpawnPointSystem to get spawn positions from the Keep's SpawnPoint part
						local peasantCount = 3 -- Starting peasants
						local spawnPositions = SpawnPointSystem.getSpawnPositions(building, {
							pattern = "circle",
							radius = 12,
							count = peasantCount,
							offset = Vector3.new(0, 0, 0),
						})

						GameManagerDebug:info(`Got {#spawnPositions} spawn positions from SpawnPointSystem`)

						if #spawnPositions > 0 then
							for i, position in ipairs(spawnPositions) do
								local peasant = UnitManager.createUnit("Peasant", player.UserId, position, playerFaction)
								if peasant then
									GameManagerDebug:info(`Spawned peasant {i}/{peasantCount} at {position} for {player.Name}`)
									-- Add peasant to idle behavior
									IdlePeasantManager.addIdlePeasant(peasant, player.UserId)
								else
									GameManagerDebug:warn(`Failed to spawn peasant {i} for {player.Name}`)
								end
							end
							GameManagerDebug:info(`Spawned {#spawnPositions} peasants around Keep for {player.Name}`)
						else
							-- Fallback: spawn at building position if no SpawnPoint found
							GameManagerDebug:warn(`No SpawnPoint found in Keep, using fallback spawn`)
							local keepPos = building.PrimaryPart.Position
							for i = 1, peasantCount do
								local angle = (math.pi * 2 * (i - 1)) / peasantCount
								local offset = Vector3.new(math.cos(angle) * 12, 0, math.sin(angle) * 12)
								local position = keepPos + offset
								local peasant = UnitManager.createUnit("Peasant", player.UserId, position, playerFaction)
								if peasant then
									IdlePeasantManager.addIdlePeasant(peasant, player.UserId)
								end
							end
						end

						-- Notify client that Keep is placed (important for tutorial/UI)
						GameEvent:FireClient(player, "KeepPlaced", {
							position = building.PrimaryPart.Position,
							peasantsSpawned = peasantCount,
						})
					end

					-- Track achievements and quests
					AchievementManager.incrementStat(player, "BuildingsBuilt", 1)
					QuestManager.updateQuestProgress(player, "BuildBuilding", data.buildingName, 1)

					-- Track defensive buildings
					if buildingInfo and buildingInfo.category == "Defense" then
						AchievementManager.incrementStat(player, "DefensesBuilt", 1)
					end

					-- Notify client that building was placed (for tutorial progression)
					GameEvent:FireClient(player, "BuildingPlaced", {
						buildingType = data.buildingName,
					})
					-- If it's a production building, auto-assign a worker
					if buildingInfo.requires_worker then
						-- Find a free peasant
						for _, unit in playerData.Units do
							if unit and unit.Parent then
								local unitType = unit:GetAttribute("UnitType")
								local isWorking = unit:GetAttribute("IsWorking")

								-- CHECK: Don't assign Vikings as workers!
								local owner = unit:GetAttribute("OwnerId")
								if unitType == "Peasant" and not isWorking and owner == player.UserId then
									WorkerManager.assignWorkerToBuilding(unit, building, player.UserId)

									break
								end
							end
						end
					end

					-- Note: Haulers are automatically assigned by WorkerManager when buildings produce resources
					-- No need to manually assign haulers here

					-- Send updated resources to client
					GameEvent:FireClient(player, "UpdateResources", {
						resources = playerData.Resources,
					})

					GameManagerDebug:info(`{player.Name} successfully placed {data.buildingName}`)
				else
					-- Refund if building failed to create
					PlayerManager.addResources(player, buildingInfo.cost)
					GameManagerDebug:warn(`Failed to create building, refunded resources`)
				end
			else
				GameManagerDebug:warn(`{player.Name} cannot afford {data.buildingName} at placement time`)
			end
		end
	-- Old "PlaceWall" event removed - now handled by WallSystemServer with "PlaceWallPath" event
	elseif action == "MoveUnit" then
		-- Handle unit movement command
		if typeof(data) == "table" and data.unitId and data.targetPosition then
			GameManagerDebug:info(`{player.Name} moving unit {data.unitId} to {data.targetPosition}`)

			local unitToMove = findUnit(data.unitId)

			if unitToMove and unitToMove:GetAttribute("OwnerId") == player.UserId then
				-- Clear combat target and delegate movement to MovementSystem
				unitToMove:SetAttribute("CombatTarget", nil)
				unitToMove:SetAttribute("TargetPosition", data.targetPosition)
				unitToMove:SetAttribute("IsMoving", true)
				-- Clear pathfinding failure - player command overrides previous failures
				unitToMove:SetAttribute("PathfindingFailed", nil)
				GameManagerDebug:info(`Unit {data.unitId} target set to {data.targetPosition}`)
			end
		end
	elseif action == "MoveUnitsInFormation" then
		-- Handle formation movement command
		if typeof(data) == "table" and data.unitIds and data.targetPosition and data.formationType then
			GameManagerDebug:info(`{player.Name} moving {#data.unitIds} units in {data.formationType} formation`)

			-- Find all units
			local units = {}
			for _, unitId in ipairs(data.unitIds) do
				local unit = findUnit(unitId)
				if unit and unit:GetAttribute("OwnerId") == player.UserId then
					table.insert(units, unit)
				end
			end

			if #units >= 2 then
				-- Calculate facing direction based on current position to target
				local averagePosition = Vector3.new(0, 0, 0)
				for _, unit in ipairs(units) do
					if unit.PrimaryPart then
						averagePosition = averagePosition + unit.PrimaryPart.Position
					end
				end
				averagePosition = averagePosition / #units

				-- Calculate facing direction (from current avg position to target)
				local facingDirection = (data.targetPosition - averagePosition).Unit
				facingDirection = Vector3.new(facingDirection.X, 0, facingDirection.Z).Unit -- Keep it horizontal

				-- Create formation
				local formation =
					FormationManager.createFormation(data.formationType, units, data.targetPosition, facingDirection)

				if formation then
					-- Generate unique formation ID
					local formationId = `Formation_{player.UserId}_{tick()}`

					-- Register formation with FormationCohesion system
					FormationCohesion.registerFormation(formationId, units)

					-- Move units to their formation positions
					for unit, position in pairs(formation.positions) do
						unit:SetAttribute("CombatTarget", nil)
						unit:SetAttribute("TargetPosition", position)
						unit:SetAttribute("IsMoving", true)
						unit:SetAttribute("FormationId", formationId) -- Track formation membership
						-- Clear pathfinding failure - player command overrides previous failures
						unit:SetAttribute("PathfindingFailed", nil)
					end

					GameManagerDebug:info(`Formation {formationId} created with {#units} units`)
				end
			else
				-- Not enough units, move individually
				for _, unit in ipairs(units) do
					unit:SetAttribute("CombatTarget", nil)
					unit:SetAttribute("TargetPosition", data.targetPosition)
					unit:SetAttribute("IsMoving", true)
					-- Clear pathfinding failure - player command overrides previous failures
					unit:SetAttribute("PathfindingFailed", nil)
				end
			end
		end
	-- Removed MoveKing action - King movement is now handled by Roblox's built-in character controls
	elseif action == "StartTraining" then
		-- Handle unit training request
		if typeof(data) == "table" and data.buildingId and data.unitType then
			GameManagerDebug:info(`{player.Name} wants to train {data.unitType} at {data.buildingId}`)

			-- Find the building
			for _, building in playerData.Buildings do
				if building and building.Parent and building.Name == data.buildingId then
					-- Check if building belongs to player
					if building:GetAttribute("OwnerId") == player.UserId then
						local success = TrainingManager.startTraining(building, data.unitType, player.UserId)
						if success then
							GameManagerDebug:info(`Started training {data.unitType}`)
						else
							GameManagerDebug:warn(`Failed to start training {data.unitType}`)
						end
						break
					end
				end
			end
		end
	elseif action == "GetTrainingQueue" then
		-- Send training queue to client
		if typeof(data) == "table" and data.buildingId then
			for _, building in playerData.Buildings do
				if building and building.Parent and building.Name == data.buildingId then
					local queue = TrainingManager.getQueue(building)
					GameEvent:FireClient(player, "TrainingQueueUpdate", {
						buildingId = data.buildingId,
						queue = queue,
					})
					break
				end
			end
		end
	elseif action == "DeleteBuilding" then
		-- Handle building deletion request
		if typeof(data) == "table" and data.buildingId then
			GameManagerDebug:info(`{player.Name} wants to delete building: {data.buildingId}`)

			-- Find the building
			for i, building in playerData.Buildings do
				if building and building.Parent and building.Name == data.buildingId then
					-- Check if building belongs to player
					if building:GetAttribute("OwnerId") == player.UserId then
						local buildingType = building:GetAttribute("BuildingType")

						-- Protect critical buildings from deletion
						if buildingType == "Keep" then
							GameManagerDebug:warn(`{player.Name} tried to delete Keep - protected building!`)
							break
						end

						GameManagerDebug:info(
							`Deleting building {building.Name} (type: {buildingType}) for {player.Name}`
						)

						-- Calculate resource refund (50% of original cost)
						local buildingInfo = GameData.Buildings[buildingType]
						if buildingInfo and buildingInfo.cost then
							local refundAmount = {}
							for resourceType, cost in pairs(buildingInfo.cost) do
								local refund = math.floor(cost * 0.5) -- 50% refund
								if refund > 0 then
									refundAmount[resourceType] = refund
									-- Add resources back to player
									if playerData.Resources[resourceType] then
										playerData.Resources[resourceType] = playerData.Resources[resourceType] + refund
									end
								end
							end

							-- Notify player about refund
							if next(refundAmount) then
								local refundText = {}
								for resourceType, amount in pairs(refundAmount) do
									table.insert(refundText, `{amount} {resourceType}`)
								end
								GameManagerDebug:info(
									`Refunded 50% resources to {player.Name}: {table.concat(refundText, ", ")}`
								)

								-- Update client resources
								GameEvent:FireClient(player, "UpdateResources", playerData.Resources)
							end
						end

						-- Unassign any workers/haulers from this building
						WorkerManager.unassignWorkersFromBuilding(building)

						-- Remove from player's building list
						table.remove(playerData.Buildings, i)

						-- Destroy the building model
						building:Destroy()

						GameManagerDebug:info(`Successfully deleted building {data.buildingId}`)
						break
					else
						GameManagerDebug:warn(`{player.Name} tried to delete building they don't own`)
					end
				end
			end
		end
	elseif action == "UndoDeletion" then
		-- Handle undo building deletion
		if typeof(data) == "table" and data.buildingType and data.position then
			GameManagerDebug:info(`{player.Name} wants to undo deletion: {data.buildingType}`)

			local buildingInfo = GameData.Buildings[data.buildingType]
			if buildingInfo then
				-- Create building without charging resources (skipCost = true)
				local building = BuildingManager.createBuilding(
					player,
					data.buildingType,
					CFrame.new(data.position), -- Convert Vector3 to CFrame
					nil, -- wallPieceType
					nil, -- manualRotation
					true -- skipCost parameter
				)

				if building then
					-- Restore rotation if provided
					if data.rotation and building.PrimaryPart then
						building.PrimaryPart.Orientation = data.rotation
					end

					GameManagerDebug:info(`Successfully restored {data.buildingType} for {player.Name}`)

					-- Notify client
					GameEvent:FireClient(player, "BuildingRestored", {
						buildingType = data.buildingType,
					})
				else
					GameManagerDebug:warn(`Failed to restore {data.buildingType} for {player.Name}`)
				end
			end
		end
	elseif action == "AttackTarget" then
		-- Handle attack command
		if typeof(data) == "table" and data.unitId and data.targetId then
			GameManagerDebug:info(`{player.Name} ordering {data.unitId} to attack {data.targetId}`)

			-- Find the attacker unit
			for _, unit in playerData.Units do
				if unit and unit.Parent and unit.Name == data.unitId then
					-- Check if unit belongs to player
					if unit:GetAttribute("OwnerId") == player.UserId then
						-- Find the target
						local unitsFolder = workspace:FindFirstChild("Units")
						if unitsFolder then
							local target = unitsFolder:FindFirstChild(data.targetId)
							if target then
								CombatManager.setTarget(unit, target) -- Changed from attackTarget
								GameManagerDebug:info(`{data.unitId} attacking {data.targetId}`)
							else
								GameManagerDebug:warn(`Target {data.targetId} not found`)
							end
						end
						break
					end
				end
			end
		end
	elseif action == "SetStance" then
		-- Handle unit stance change
		if typeof(data) == "table" and data.UnitIDs and data.Stance then
			GameManagerDebug:info(`{player.Name} setting stance to {data.Stance} for {data.UnitIDs}`)

			for _, unitId in ipairs(data.UnitIDs) do
				local unitModel = findUnit(unitId)

				if unitModel and unitModel:GetAttribute("OwnerId") == player.UserId then
					-- Delegate to CombatManager
					CombatManager.setStance(unitModel, data.Stance)
				end
			end
		end
	elseif action == "UseAbility" then
		-- Handle hero ability usage
		if typeof(data) == "table" and data.abilityId then
			GameManagerDebug:info(`{player.Name} using ability: {data.abilityId}`)
			AbilityManager.useAbility(player, data.abilityId)
		end
	elseif action == "UpgradeBuilding" then
		-- Handle building upgrade
		if typeof(data) == "table" and data.buildingId then
			GameManagerDebug:info(`{player.Name} upgrading building: {data.buildingId}`)

			-- Find the building
			for _, building in playerData.Buildings do
				if building and building.Parent and building.Name == data.buildingId then
					UpgradeManager.upgradeBuilding(player, building)
					break
				end
			end
		end
	elseif action == "StartResearch" then
		-- Handle research start
		if typeof(data) == "table" and data.techId then
			GameManagerDebug:info(`{player.Name} starting research: {data.techId}`)
			ResearchManager.startResearch(player, data.techId)
		end
	elseif action == "GetAbilities" then
		-- Send abilities to client
		local abilities = AbilityManager.getAbilities()
		local cooldowns = AbilityManager.getAllCooldowns(player)
		GameEvent:FireClient(player, "AbilitiesData", {
			abilities = abilities,
			cooldowns = cooldowns,
		})
	elseif action == "GetQuests" then
		-- Send quests to client
		local activeQuests = QuestManager.getActiveQuests(player)
		local completedQuests = QuestManager.getCompletedQuests(player)
		GameEvent:FireClient(player, "QuestsData", {
			activeQuests = activeQuests,
			completedQuests = completedQuests,
		})
	elseif action == "GetAchievements" then
		-- Send achievements to client
		local unlocked = AchievementManager.getUnlockedAchievements(player)
		local locked = AchievementManager.getLockedAchievements(player)
		local stats = AchievementManager.getStats(player)
		GameEvent:FireClient(player, "AchievementsData", {
			unlocked = unlocked,
			locked = locked,
			stats = stats,
		})
	elseif action == "LeaveGame" then
		-- Handle player leaving game and returning to main menu
		GameManagerDebug:info(`{player.Name} leaving game and returning to main menu`)

		-- Clean up all player buildings
		for i = #playerData.Buildings, 1, -1 do
			local building = playerData.Buildings[i]
			if building and building.Parent then
				-- Unassign workers first
				WorkerManager.unassignWorkersFromBuilding(building)
				building:Destroy()
			end
			table.remove(playerData.Buildings, i)
		end

		-- Clean up all player units
		for i = #playerData.Units, 1, -1 do
			local unit = playerData.Units[i]
			if unit and unit.Parent then
				unit:Destroy()
			end
			table.remove(playerData.Units, i)
		end

		-- Disable Viking raids if active
		VikingRaidSystem.disableRaids(player.UserId)

		-- Reset player data
		playerData.GameState = "Menu"
		playerData.Faction = nil
		playerData.SpawnPoint = nil

		-- Reset resources to 0
		for resource, _ in pairs(playerData.Resources) do
			playerData.Resources[resource] = 0
		end

		GameManagerDebug:info(`{player.Name} successfully left game - all data cleaned up`)

		-- Notify client that cleanup is complete
		GameEvent:FireClient(player, "GameLeft", {})
	end
end)

-- Handle lobby events for multiplayer
LobbyEvent.OnServerEvent:Connect(function(player, action, ...)
	GameManagerDebug:info(`Lobby event from {player.Name}: {action}`)

	if action == "JoinLobby" then
		LobbyManager.addPlayer(player)
	elseif action == "LeaveLobby" then
		LobbyManager.removePlayer(player)
	elseif action == "AddAI" then
		LobbyManager.addAI(player)
	elseif action == "RemovePlayer" then
		local targetUserId = ...
		LobbyManager.removePlayerOrAI(player, targetUserId)
	elseif action == "VoteSetting" then
		local settingId, value = ...
		LobbyManager.voteSetting(player, settingId, value)
	elseif action == "SelectSpawn" then
		local spawnNumber = ...
		LobbyManager.selectSpawn(player, spawnNumber)
	elseif action == "SelectColor" then
		local color = ...
		LobbyManager.selectColor(player, color)
	elseif action == "SelectFaction" then
		local faction, targetUserId = ...
		LobbyManager.selectFaction(player, faction, targetUserId)
	elseif action == "ToggleReady" then
		LobbyManager.toggleReady(player)
	end
end)

-- Handle player disconnecting from lobby
Players.PlayerRemoving:Connect(function(player)
	-- Remove from lobby if they're in it
	LobbyManager.removePlayer(player)
end)

-- Handle map editor events
MapEditorEvent.OnServerEvent:Connect(function(player, action, ...)
	GameManagerDebug:info(`MapEditor event from {player.Name}: {action}`)

	if action == "EnterEditor" then
		local mapId = ...
		MapEditorManager.enterEditor(player, mapId)
	elseif action == "LeaveEditor" then
		MapEditorManager.leaveEditor(player)
	elseif action == "PaintTerrain" then
		local strokes = ...
		MapEditorManager.paintTerrain(player, strokes)
	elseif action == "SetBaseTerrain" then
		local data = ...
		MapEditorManager.setBaseTerrain(player, data)
	elseif action == "PlaceFeature" then
		local feature = ...
		MapEditorManager.placeFeature(player, feature)
	elseif action == "MoveFeature" then
		local data = ...
		MapEditorManager.moveFeature(player, data)
	elseif action == "DeleteFeature" then
		local data = ...
		MapEditorManager.deleteFeature(player, data)
	elseif action == "UpdateSpawnZone" then
		local data = ...
		MapEditorManager.updateSpawnZone(player, data)
	elseif action == "UpdateMapSettings" then
		local data = ...
		MapEditorManager.updateMapSettings(player, data)
	elseif action == "SaveMap" then
		MapEditorManager.saveMap(player)
	elseif action == "LoadMap" then
		local mapId = ...
		MapEditorManager.loadMap(player, mapId)
	elseif action == "ListMaps" then
		MapEditorManager.listMaps(player)
	elseif action == "ExportMap" then
		MapEditorManager.exportMap(player)
	end
end)

-- Clean up map editor session when player leaves
Players.PlayerRemoving:Connect(function(player)
	MapEditorManager.leaveEditor(player)
end)

GameManagerDebug:info("Server ready!")
