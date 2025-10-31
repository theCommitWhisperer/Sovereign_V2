--!strict
-- GameManager: Main server-side game coordinator

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local StarterPlayer = game:GetService("StarterPlayer")

-- Require game data (safe - read-only configs)
local GameData = require(ReplicatedStorage.Shared.GameData)
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)

local GameManagerDebug = DebugManager.createChannel("GameManager", true) -- Corrected to be off by default

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
local CombatManager = require(Managers.CombatManager) -- Updated CombatManager
local HappinessManager = require(Managers.HappinessManager)
local TaxManager = require(Managers.TaxManager)
local RevoltManager = require(Managers.RevoltManager)
local FactionManager = require(Managers.FactionManager)
local PopulationManager = require(Managers.PopulationManager)
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

CombatManager.init()
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

-- Require from Systems subfolder
local Systems = script.Parent.Systems
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

GameManagerDebug:info("RemoteEvents created")

-- Initialize TestCommandManager after RemoteEvents are created
TestCommandManager.init()
GameManagerDebug:info("TestCommandManager initialized")

-- Helper function to find a unit model by its UnitId (which is the Model.Name in V2)
local function findUnit(unitId: string): Model?
	local unitsFolder = Workspace:FindFirstChild("Units")
	if unitsFolder then
		return unitsFolder:FindFirstChild(unitId)
	end
	return nil
end

-- Player joined - create their data
Players.PlayerAdded:Connect(function(player)
	PlayerManager.create(player)
	GameManagerDebug:info(`{player.Name} joined - character will spawn when game starts`)
end)

-- Player left - clean up
Players.PlayerRemoving:Connect(function(player)
	SpawnManager.removePlayer(player.UserId)
	PlayerManager.remove(player)
end)

local function spawnInitialSetup(player: Player, factionData: any, spawnPointOverride: CFrame?)
	local spawnPoint = spawnPointOverride or factionData.SpawnPoint

	-- 1. Spawn the Keep
	local keep = BuildingManager.createBuilding(player, "Keep", spawnPoint)
	if not keep then
		GameManagerDebug:warn(`Failed to create Keep for {player.Name}`)
		return
	end

	-- 2. Spawn the King near the Keep
	local kingSpawnPos = spawnPoint.Position + Vector3.new(5, 0, 5)
	UnitManager.createUnit("King", player.UserId, kingSpawnPos, factionData.Name) -- Pass faction

	-- 3. Spawn peasants around the Keep
	for i = 1, factionData.StartingPeasants do
		local angle = (math.pi * 2 * i) / factionData.StartingPeasants
		local offset = Vector3.new(math.cos(angle) * 10, 0, math.sin(angle) * 10)
		local peasantSpawnPos = spawnPoint.Position + offset
		UnitManager.createUnit("Peasant", player.UserId, peasantSpawnPos, factionData.Name) -- Pass faction
	end
	-- 4. Spawn resource nodes around the spawn
	ResourceNodeManager.spawnNodesNearPosition(spawnPoint.Position, 150, "Wood", 20)
	ResourceNodeManager.spawnNodesNearPosition(spawnPoint.Position, 150, "Stone", 15)
	ResourceNodeManager.spawnNodesNearPosition(spawnPoint.Position, 100, "Food", 10)
	ResourceNodeManager.spawnNodesNearPosition(spawnPoint.Position, 120, "Iron_Ore", 8)

	GameManagerDebug:info(
		`Spawned Keep, King, {factionData.StartingPeasants} peasants, and resource nodes for {player.Name} + factionData {factionData.Name}`
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

		-- Set the active map and configure SpawnManager
		if not MapManager.setMap(selectedMap) then
			GameManagerDebug:warn(`Invalid map selected: {selectedMap}, using default`)
			selectedMap = "ClassicPlains"
			MapManager.setMap(selectedMap)
		end

		local mapConfig = MapManager.getCurrentMap()
		SpawnManager.setMapConfig(mapConfig)
		GameManagerDebug:info(`Map loaded: {mapConfig.Name} ({mapConfig.Size}x{mapConfig.Size})`)

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

		-- Assign player to a quadrant using SpawnManager
		local quadrant = SpawnManager.assignPlayerToQuadrant(player.UserId)

		-- Map quadrants to factions
		local quadrantToFaction = {
			[1] = "Kingdom", -- Northwest
			[2] = "Empire", -- Northeast
			[3] = "Tribes", -- Southwest
			[4] = "IronLegion", -- Southeast
		}

		local factionName = quadrantToFaction[quadrant] or "Kingdom"
		local factionData = GameData.Factions[factionName]

		-- Override spawn point with quadrant-specific spawn
		local quadrantSpawn = SpawnManager.getPlayerSpawnPoint(player.UserId)

		playerData.Faction = factionName
		playerData.SpawnPoint = quadrantSpawn
		playerData.GameState = "InGame"

		GameManagerDebug:info(`Assigned {player.Name} to Quadrant {quadrant} ({factionName})`)

		-- Set starting resources
		for resource, amount in pairs(factionData.StartingResources) do
			playerData.Resources[resource] = amount
		end

		-- Spawn initial setup with quadrant spawn point
		spawnInitialSetup(player, factionData, quadrantSpawn)

		-- Load character now (Players.CharacterAutoLoads is false)
		player:LoadCharacter()
		GameManagerDebug:info(`Loading character for {player.Name}`)

		-- Wait for character and teleport to quadrant spawn
		local character = player.Character or player.CharacterAdded:Wait()
		local humanoidRootPart = character:WaitForChild("HumanoidRootPart") :: BasePart
		humanoidRootPart.CFrame = quadrantSpawn * CFrame.new(0, 3, 0)
		GameManagerDebug:info(`Character spawned and teleported {player.Name} to quadrant {quadrant}`)

		-- Notify client
		GameEvent:FireClient(player, "GameStarted", {
			faction = factionName,
			resources = playerData.Resources,
		})

		-- Send immediate economy dashboard update
		task.wait(0.1) -- Brief delay to ensure all data is initialized
		EconomyDashboardManager.sendUpdate(player)

		GameManagerDebug:info(`{player.Name} spawned as Kingdom`)
	elseif action == "StartPlacement" then
		GameManagerDebug:info(`{player.Name} wants to place: {data}`)

		-- Client wants to start placing a building
		if typeof(data) == "string" then
			local buildingInfo = GameData.Buildings[data]
			if not buildingInfo then
				GameManagerDebug:warn(`Unknown building: {data}`)
				return
			end

			if PlayerManager.hasEnoughResources(player, buildingInfo.cost) then
				GameManagerDebug:info(`Approving placement for {player.Name}: {data}`)
				-- Tell client to start placement mode
				GameEvent:FireClient(player, "StartPlacement", data)
			else
				GameManagerDebug:warn(`{player.Name} cannot afford {data}`)
				GameManagerDebug:info(`Current resources:`, playerData.Resources)
				GameManagerDebug:info(`Required:`, buildingInfo.cost)
			end
		end
	elseif action == "PlaceBuilding" then
		GameManagerDebug:info(`{player.Name} placing building:`, data)

		-- Client confirmed building placement
		if typeof(data) == "table" and data.buildingName and data.cframe then
			local buildingInfo = GameData.Buildings[data.buildingName]
			if not buildingInfo then
				GameManagerDebug:warn(`Unknown building: {data.buildingName}`)
				return
			end

			if PlayerManager.hasEnoughResources(player, buildingInfo.cost) then
				-- Deduct resources
				PlayerManager.deductResources(player, buildingInfo.cost)

				-- Create the building
				local building = BuildingManager.createBuilding(player, data.buildingName, data.cframe)

				if building then
					-- If it's a production building, auto-assign a worker
					if buildingInfo.requires_worker then
						-- Find a free peasant
						for _, unit in playerData.Units do
							if unit and unit.Parent then
								local unitType = unit:GetAttribute("UnitType")
								local isWorking = unit:GetAttribute("IsWorking")

								-- CHECK: Don't assign Vikings as workers!
								local owner = unit:GetAttribute("Owner")
								if unitType == "Peasant" and not isWorking and owner == player.UserId then
									WorkerManager.assignWorkerToBuilding(unit, building, player.UserId)
									print(`[GameManager] Auto-assigned worker to {buildingInfo.type}`)
									break
								end
							end
						end
					end

					-- Auto-assign a hauler if we have available peasants
					for _, unit in playerData.Units do
						if unit and unit.Parent then
							local unitType = unit:GetAttribute("UnitType")
							local isHauling = unit:GetAttribute("IsHauling")
							local isWorking = unit:GetAttribute("IsWorking")

							-- CHECK: Don't assign Vikings as haulers!
							local owner = unit:GetAttribute("Owner")
							if
								unitType == "Peasant"
								or unitType == "Ox" and not isHauling and not isWorking and owner == player.UserId
							then
								WorkerManager.assignHauler(unit, player.UserId)
								print(`[GameManager] Auto-assigned hauler`)
								break
							end
						end
					end

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
	elseif action == "MoveUnit" then
		-- Handle unit movement command
		if typeof(data) == "table" and data.unitId and data.targetPosition then
			GameManagerDebug:info(`{player.Name} moving unit {data.unitId} to {data.targetPosition}`)

			local unitToMove = findUnit(data.unitId)

			if unitToMove and unitToMove:GetAttribute("Owner") == player.UserId then
				-- Clear combat target and delegate movement to MovementSystem
				unitToMove:SetAttribute("CombatTarget", nil)
				unitToMove:SetAttribute("TargetPosition", data.targetPosition)
				unitToMove:SetAttribute("IsMoving", true)
				GameManagerDebug:info(`Unit {data.unitId} target set to {data.targetPosition}`)
			end
		end
	elseif action == "StartTraining" then
		-- Handle unit training request
		if typeof(data) == "table" and data.buildingId and data.unitType then
			GameManagerDebug:info(`{player.Name} wants to train {data.unitType} at {data.buildingId}`)

			-- Find the building
			for _, building in playerData.Buildings do
				if building and building.Parent and building.Name == data.buildingId then
					-- Check if building belongs to player
					if building:GetAttribute("Owner") == player.UserId then
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
					if building:GetAttribute("Owner") == player.UserId then
						local buildingType = building:GetAttribute("BuildingType")

						-- Protect critical buildings from deletion
						if buildingType == "Keep" then
							GameManagerDebug:warn(`{player.Name} tried to delete Keep - protected building!`)
							break
						end

						GameManagerDebug:info(
							`Deleting building {building.Name} (type: {buildingType}) for {player.Name}`
						)

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
	elseif action == "AttackTarget" then
		-- Handle attack command
		if typeof(data) == "table" and data.unitId and data.targetId then
			GameManagerDebug:info(`{player.Name} ordering {data.unitId} to attack {data.targetId}`)

			-- Find the attacker unit
			for _, unit in playerData.Units do
				if unit and unit.Parent and unit.Name == data.unitId then
					-- Check if unit belongs to player
					if unit:GetAttribute("Owner") == player.UserId then
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

				if unitModel and unitModel:GetAttribute("Owner") == player.UserId then
					-- Delegate to CombatManager
					CombatManager.setStance(unitModel, data.Stance)
				end
			end
		end
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

GameManagerDebug:info("Server ready!")
