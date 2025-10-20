--!strict
-- GameManager: Main server-side game coordinator

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Require game data (safe - read-only configs)
local GameData = require(ReplicatedStorage.Shared.GameData)
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)

local GameManagerDebug = DebugManager.createChannel("GameManager", false) -- Corrected to be off by default

GameManagerDebug:info("Loading server-side managers...")

-- Require from Managers subfolder (secure - server-only logic)
local Managers = script.Parent.Managers
local PlayerManager = require(Managers.PlayerManager)
local BuildingManager = require(Managers.BuildingManager)
local UnitManager = require(Managers.UnitManager)
local ResourceNodeManager = require(Managers.ResourceNodeManager)
local WorkerManager = require(Managers.WorkerManager)
local TrainingManager = require(Managers.TrainingManager)
local CombatManager = require(Managers.CombatManager)

-- Require from Systems subfolder
local Systems = script.Parent.Systems
local MovementSystem = require(Systems.MovementSystem)
local VikingRaidSystem = require(Systems.VikingRaidSystem)

GameManagerDebug:info("Managers loaded successfully")
GameManagerDebug:info("Server starting...")

-- Create RemoteEvent for game actions
local RemoteEvents = Instance.new("Folder")
RemoteEvents.Name = "RemoteEvents"
RemoteEvents.Parent = ReplicatedStorage

local GameEvent = Instance.new("RemoteEvent")
GameEvent.Name = "GameEvent"
GameEvent.Parent = RemoteEvents

GameManagerDebug:info("RemoteEvents created")

-- Player joined - create their data
Players.PlayerAdded:Connect(function(player)
	PlayerManager.create(player)
end)

-- Player left - clean up
Players.PlayerRemoving:Connect(function(player)
	PlayerManager.remove(player)
end)

local function spawnInitialSetup(player: Player, factionData: any)
	local spawnPoint = factionData.SpawnPoint

	-- 1. Spawn the Keep
	local keep = BuildingManager.createBuilding(player, "Keep", spawnPoint)
	if not keep then
		GameManagerDebug:warn(`Failed to create Keep for {player.Name}`)
		return
	end

	-- 2. Spawn the King near the Keep
	local kingSpawnPos = spawnPoint.Position + Vector3.new(5, 0, 5)
	UnitManager.createUnit("King", player.UserId, kingSpawnPos) -- CHANGED: player.UserId instead of player

	-- 3. Spawn peasants around the Keep
	for i = 1, factionData.StartingPeasants do
		local angle = (math.pi * 2 * i) / factionData.StartingPeasants
		local offset = Vector3.new(math.cos(angle) * 10, 0, math.sin(angle) * 10)
		local peasantSpawnPos = spawnPoint.Position + offset
		UnitManager.createUnit("Peasant", player.UserId, peasantSpawnPos) -- CHANGED: player.UserId instead of player
	end

	-- 4. Spawn resource nodes around the spawn
	ResourceNodeManager.spawnNodesNearPosition(spawnPoint.Position, 150, "Wood", 20)
	ResourceNodeManager.spawnNodesNearPosition(spawnPoint.Position, 150, "Stone", 15)
	ResourceNodeManager.spawnNodesNearPosition(spawnPoint.Position, 100, "Food", 10)

	GameManagerDebug:info(
		`Spawned Keep, King, {factionData.StartingPeasants} peasants, and resource nodes for {player.Name}`
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

	if action == "StartGame" then
		GameManagerDebug:info(`{player.Name} starting game...`)
		-- Get game settings from data
		local settings = typeof(data) == "table" and data or {}
		local vikingRaidsEnabled = settings.vikingRaids or false
		local peaceTimeStr = settings.peaceTime or "10 minutes"

		-- Parse peace time (format: "10 minutes")
		local peaceTimeMinutes = 0 -- default
		local minutes = peaceTimeStr:match("(%d+)")
		if minutes then
			peaceTimeMinutes = tonumber(minutes) or 10
		end

		GameManagerDebug:info(`Viking Raids: {vikingRaidsEnabled}, Peace Time: {peaceTimeMinutes} minutes`)

		if vikingRaidsEnabled then
			VikingRaidSystem.enableRaids(player.UserId, peaceTimeMinutes)
			GameManagerDebug:info(`Viking Raids enabled for {player.Name}`)
		end

		-- Assign faction (for now, just use Kingdom)
		local factionName = "Kingdom"
		local factionData = GameData.Factions[factionName]
		playerData.Faction = factionName
		playerData.SpawnPoint = factionData.SpawnPoint
		playerData.GameState = "InGame"

		-- Set starting resources
		for resource, amount in factionData.StartingResources do
			playerData.Resources[resource] = amount
		end

		-- Spawn initial setup
		spawnInitialSetup(player, factionData)

		-- Teleport existing character instead of loading a new one
		if player.Character and player.Character.PrimaryPart then
			player.Character:SetPrimaryPartCFrame(factionData.SpawnPoint * CFrame.new(0, 3, 0))
		end

		-- Notify client
		GameEvent:FireClient(player, "GameStarted", {
			faction = factionName,
			resources = playerData.Resources,
		})

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
									WorkerManager.assignWorkerToBuilding(unit, newBuilding, player.UserId)
									print(`[GameManager] Auto-assigned worker to {buildingType}`)
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

			-- Find the unit
			for _, unit in playerData.Units do
				if unit and unit.Parent and unit.Name == data.unitId then
					-- Check if unit belongs to player
					if unit:GetAttribute("Owner") == player.UserId then
						-- Set target position
						unit:SetAttribute("TargetPosition", data.targetPosition)
						unit:SetAttribute("IsMoving", true)
						GameManagerDebug:info(`Unit {data.unitId} target set to {data.targetPosition}`)
						break
					end
				end
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
								CombatManager.setTarget(unit, target)
								GameManagerDebug:info(`{data.unitId} attacking {data.targetId}`)
							end
						end
						break
					end
				end
			end
		end
	end
end)

GameManagerDebug:info("Server ready!")
