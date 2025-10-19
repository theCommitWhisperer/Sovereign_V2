--!strict
-- GameManager: Main server-side game coordinator

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Require game data (safe - read-only configs)
local GameData = require(ReplicatedStorage.Shared.GameData)

print("[GameManager] Loading server-side managers...")

-- Require from Managers subfolder (secure - server-only logic)
local Managers = script.Parent.Managers
local PlayerManager = require(Managers.PlayerManager)
local BuildingManager = require(Managers.BuildingManager)
local UnitManager = require(Managers.UnitManager)
local ResourceNodeManager = require(Managers.ResourceNodeManager)
local WorkerManager = require(Managers.WorkerManager)

print("[GameManager] Managers loaded successfully")
print("[GameManager] Server starting...")

-- Create RemoteEvent for game actions
local RemoteEvents = Instance.new("Folder")
RemoteEvents.Name = "RemoteEvents"
RemoteEvents.Parent = ReplicatedStorage

local GameEvent = Instance.new("RemoteEvent")
GameEvent.Name = "GameEvent"
GameEvent.Parent = RemoteEvents

print("[GameManager] RemoteEvents created")

-- Player joined - create their data
Players.PlayerAdded:Connect(function(player)
	PlayerManager.create(player)
end)

-- Player left - clean up
Players.PlayerRemoving:Connect(function(player)
	PlayerManager.remove(player)
end)

-- Spawn initial structures and units for a player
local function spawnInitialSetup(player: Player, factionData: any)
	local spawnPoint = factionData.SpawnPoint

	-- 1. Spawn the Keep
	local keep = BuildingManager.createBuilding(player, "Keep", spawnPoint)
	if not keep then
		warn(`[GameManager] Failed to create Keep for {player.Name}`)
		return
	end

	-- 2. Spawn the King near the Keep
	local kingSpawnPos = spawnPoint.Position + Vector3.new(5, 0, 5)
	UnitManager.createUnit("King", player, kingSpawnPos)

	-- 3. Spawn peasants around the Keep
	for i = 1, factionData.StartingPeasants do
		local angle = (math.pi * 2 * i) / factionData.StartingPeasants
		local offset = Vector3.new(math.cos(angle) * 10, 0, math.sin(angle) * 10)
		local peasantSpawnPos = spawnPoint.Position + offset
		UnitManager.createUnit("Peasant", player, peasantSpawnPos)
	end

	-- 4. Spawn resource nodes around the spawn
	ResourceNodeManager.spawnNodesNearPosition(spawnPoint.Position, 150, "Wood", 20)
	ResourceNodeManager.spawnNodesNearPosition(spawnPoint.Position, 150, "Stone", 15)
	ResourceNodeManager.spawnNodesNearPosition(spawnPoint.Position, 100, "Food", 10)

	print(
		`[GameManager] Spawned Keep, King, {factionData.StartingPeasants} peasants, and resource nodes for {player.Name}`
	)
end

-- Handle game events from client
GameEvent.OnServerEvent:Connect(function(player, action, data)
	print(`[GameManager] Received event from {player.Name}: {action}`)

	local playerData = PlayerManager.get(player)
	if not playerData then
		warn(`[GameManager] No player data for {player.Name}`)
		return
	end

	if action == "StartGame" then
		print(`[GameManager] {player.Name} starting game...`)

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

		print(`[GameManager] {player.Name} spawned as Kingdom`)
	elseif action == "StartPlacement" then
		print(`[GameManager] {player.Name} wants to place: {data}`)

		-- Client wants to start placing a building
		if typeof(data) == "string" then
			local buildingInfo = GameData.Buildings[data]
			if not buildingInfo then
				warn(`[GameManager] Unknown building: {data}`)
				return
			end

			if PlayerManager.hasEnoughResources(player, buildingInfo.cost) then
				print(`[GameManager] Approving placement for {player.Name}: {data}`)
				-- Tell client to start placement mode
				GameEvent:FireClient(player, "StartPlacement", data)
			else
				warn(`[GameManager] {player.Name} cannot afford {data}`)
				print(`[GameManager] Current resources:`, playerData.Resources)
				print(`[GameManager] Required:`, buildingInfo.cost)
			end
		end
	elseif action == "PlaceBuilding" then
		print(`[GameManager] {player.Name} placing building:`, data)

		-- Client confirmed building placement
		if typeof(data) == "table" and data.buildingName and data.cframe then
			local buildingInfo = GameData.Buildings[data.buildingName]
			if not buildingInfo then
				warn(`[GameManager] Unknown building: {data.buildingName}`)
				return
			end

			if PlayerManager.hasEnoughResources(player, buildingInfo.cost) then
				-- Deduct resources
				PlayerManager.deductResources(player, buildingInfo.cost)

				-- Create the building
				local building = BuildingManager.createBuilding(player, data.buildingName, data.cframe)

				if building then
					-- If it's a production building, auto-assign a worker
					if buildingInfo.requires_worker and buildingInfo.produces_resource then
						-- Find an idle peasant
						for _, unit in playerData.Units do
							if
								unit
								and unit.Parent
								and unit:GetAttribute("UnitType") == "Peasant"
								and not unit:GetAttribute("IsWorking")
								and not unit:GetAttribute("IsHauling")
							then
								WorkerManager.assignWorkerToBuilding(unit, building, player.UserId)
								print(`[GameManager] Auto-assigned worker to {data.buildingName}`)
								break
							end
						end
					end

					-- Auto-assign a hauler if we have idle peasants
					for _, unit in playerData.Units do
						if
							unit
							and unit.Parent
							and (unit:GetAttribute("UnitType") == "Peasant" or unit:GetAttribute("UnitType") == "Ox")
							and not unit:GetAttribute("IsWorking")
							and not unit:GetAttribute("IsHauling")
						then
							WorkerManager.assignHauler(unit, player.UserId)
							print(`[GameManager] Auto-assigned hauler`)
							break
						end
					end

					-- Send updated resources to client
					GameEvent:FireClient(player, "UpdateResources", {
						resources = playerData.Resources,
					})

					print(`[GameManager] {player.Name} successfully placed {data.buildingName}`)
				else
					-- Refund if building failed to create
					PlayerManager.addResources(player, buildingInfo.cost)
					warn(`[GameManager] Failed to create building, refunded resources`)
				end
			else
				warn(`[GameManager] {player.Name} cannot afford {data.buildingName} at placement time`)
			end
		end
	end
end)

print("[GameManager] Server ready!")
