--!strict
-- GameManager: Main server-side game coordinator

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local StarterPlayer = game:GetService("StarterPlayer")

-- Require game data (safe - read-only configs)
local GameData = require(ReplicatedStorage.Shared.GameData)
local GameSettings = require(ReplicatedStorage.Shared.GameSettings)
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)
local MapData = require(ReplicatedStorage.Shared.GameData.MapData)
-- Hero combat tuning (CombatConfig.Hero) — the Lord's fighter stats and the
-- action names the client dispatches. See server/Combat/HeroCombat.luau.
local CombatConfig = require(ReplicatedStorage.Shared.GameData.CombatConfig)

local GameManagerDebug = DebugManager.createChannel("GameManager", false)

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
local GloryManager = require(Managers.GloryManager)
local UpgradeManager = require(Managers.UpgradeManager)
local ResearchManager = require(Managers.ResearchManager)
local QuestManager = require(Managers.QuestManager)
local AchievementManager = require(Managers.AchievementManager)
local GameplayEnhancementManager = require(Managers.GameplayEnhancementManager)
local LobbyManager = require(Managers.LobbyManager)
local MapEditorManager = require(Managers.MapEditorManager)
local EstateManager = require(Managers.EstateManager)
local MonetizationManager = require(Managers.MonetizationManager)
local EliminationManager = require(Managers.EliminationManager)

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
GloryManager.init()
UpgradeManager.init()
ResearchManager.init()
QuestManager.init()
AchievementManager.init()
GameplayEnhancementManager.init()
EstateManager.init()
MonetizationManager.init()
EliminationManager.init()

-- Require from Systems subfolder
local Systems = script.Parent.Systems
local PathfindingIntegration = require(Systems.PathfindingIntegration)
local MovementSystem = require(Systems.MovementSystem)
local FlowFieldManager = require(Systems.FlowFieldManager)
local VikingRaidSystem = require(Systems.VikingRaidSystem)
local PopulationSystem = require(Systems.PopulationSystem)
local RevoltSystem = require(Systems.RevoltSystem)
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
local SiegeTowerSystem = require(Systems.SiegeTowerSystem)
local ArenaMode = require(script.Parent.Combat.ArenaMode)
local WeaponVisuals = require(script.Parent.Combat.WeaponVisuals)

-- Initialize systems
PopulationSystem.init()
RevoltSystem.init()
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

-- Studio terrain: custom map data loaded once per game session so all players share
-- the same painted resource patches and keep spawn zones.
local studioCustomMapData: any? = nil
local studioResourcePatchesSpawned = false
local matchMapConfig: any? = nil
local mapWorldInitialized = false
local workerLoopStarted = false
-- Set once per match by the first StartGame to carry a teamOf map (see
-- LobbyManager.buildTeamOf) -- every player's server-authored settings carry
-- the same map, so only the first arrival needs to apply it.

-- Initialize systems that depend on RemoteEvents
WallSystemServer.initialize()
TestCommandManager.init()
ArenaMode.init()
FlowFieldManager.init()
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

-- Find the SpawnLocation instance inside a player's Keep model (the
-- Stone_Wall_Large_Keep asset ships with one). Returns nil when the player has
-- no Keep yet or the model is missing its SpawnLocation.
local function getKeepSpawnLocation(playerData: PlayerManager.PlayerData): BasePart?
	local keep = playerData.Keep
	if not keep or not keep.Parent then
		return nil
	end

	local spawnLocation = keep:FindFirstChildWhichIsA("SpawnLocation", true)
	if spawnLocation then
		return spawnLocation
	end

	-- Fallback: a plain part named "SpawnLocation" also counts
	local byName = keep:FindFirstChild("SpawnLocation", true)
	if byName and byName:IsA("BasePart") then
		return byName
	end

	GameManagerDebug:warn(`No SpawnLocation found inside Keep model {keep.Name} — falling back to zone spawn`)
	return nil
end

-- Where the Lord (player character) should spawn/respawn: the SpawnLocation
-- inside their own Keep when it exists, otherwise their assigned zone spawn.
local function getLordSpawnCFrame(playerData: PlayerManager.PlayerData): CFrame?
	local spawnLocation = getKeepSpawnLocation(playerData)
	if spawnLocation then
		return spawnLocation.CFrame * CFrame.new(0, 4, 0)
	end
	if playerData.SpawnPoint then
		return playerData.SpawnPoint * CFrame.new(0, 3, 0)
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

		-- A Lord fighting in hero mode leaves the combat roster on death (the
		-- client drops back to RTS on its own Died watcher). The hero ACTION state
		-- has to go with it: leaving it behind would leak the per-player table and
		-- let a respawned Lord inherit the corpse's combo index, block posture and
		-- dodge cooldown.
		CombatManager.unregisterHero(player)
		CombatManager.unregisterPlayerFighter(character)
		character:SetAttribute("PlayerFighter", nil)

		-- Military victory modes (Conquest/Regicide): the Lord's death is FINAL.
		-- EliminationManager consumes the death as a Direct Slay elimination and
		-- we skip the respawn entirely. In Score mode it returns false and the
		-- classic 10s respawn below still runs.
		if EliminationManager.onLordSlain(player) then
			GameManagerDebug:warn(`{player.Name}'s Lord has been slain — ELIMINATED (no respawn)`)
			return
		end

		-- Respawn the King after 10 seconds
		task.delay(10, function()
			if player and player.Parent then
				local playerData = PlayerManager.get(player)
				if playerData and (playerData.Keep or playerData.SpawnPoint) then
					GameManagerDebug:info(`Respawning King for {player.Name}`)

					-- Respawn character at the Keep's SpawnLocation (falls back
					-- to the assigned zone spawn if the Keep/SpawnLocation is missing)
					player:LoadCharacter()
					local newCharacter = player.Character or player.CharacterAdded:Wait()
					local humanoidRootPart = newCharacter:WaitForChild("HumanoidRootPart") :: BasePart
					local respawnCFrame = getLordSpawnCFrame(playerData)
					if respawnCFrame then
						humanoidRootPart.CFrame = respawnCFrame
					else
						GameManagerDebug:warn(`No respawn point available for {player.Name}`)
					end

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

			-- Every respawn path places the Lord at their Keep's SpawnLocation
			-- (zone spawn until the Keep is placed). Covers Reset/auto respawns
			-- in addition to the explicit death-respawn handler.
			task.defer(function()
				local rootPart = character:WaitForChild("HumanoidRootPart", 10)
				local spawnCFrame = getLordSpawnCFrame(playerData)
				if rootPart and rootPart:IsA("BasePart") and spawnCFrame then
					local rootBase = rootPart :: BasePart
					rootBase.CFrame = spawnCFrame
				end
			end)

			-- Setup health monitoring for respawned character
			setupKingHealthMonitoring(player, character)
			GameManagerDebug:info(`{player.Name} character respawned and re-tagged as King`)
		end
	end)
end)

-- Player left - clean up (single handler, ordered cleanup)
Players.PlayerRemoving:Connect(function(player)
	MapEditorManager.leaveEditor(player)
	LobbyManager.removePlayer(player)
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
	local troopTypes = { "Archer", "Knight", "Light_Cavalry", "Pikeman" }

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

	-- 4. Spawn resource nodes — skip in Studio terrain mode because nodes are spawned
	-- once globally from painted ResourcePatches (or the fallback patch list) in the StartGame handler.
	local isStudioMode = (function()
		local flag = workspace:FindFirstChild("UseStudioTerrain")
		if flag ~= nil and flag:IsA("BoolValue") and flag.Value == true then return true end
		-- Also skip when a BuiltinMapData module was loaded (studioResourcePatchesSpawned tracks this)
		if studioResourcePatchesSpawned then return true end
		return false
	end)()

	if not isStudioMode then
		local densityMultipliers = { Scarce = 0.5, Standard = 1.0, Abundant = 1.75 }
		local dm = densityMultipliers[lobbySettings.resourceDensity] or 1.0

		-- Wooded area (northwest of spawn)
		local woodAreaCenter = spawnPoint.Position + Vector3.new(-80, 0, 80)
		ResourceNodeManager.spawnNodesNearPosition(woodAreaCenter, 60, "Wood", math.floor(25 * dm))

		-- Stone area (northeast of spawn)
		local stoneAreaCenter = spawnPoint.Position + Vector3.new(80, 0, 80)
		ResourceNodeManager.spawnNodesNearPosition(stoneAreaCenter, 50, "Stone", math.floor(20 * dm))

		-- Fertile land (southwest of spawn)
		local fertileAreaCenter = spawnPoint.Position + Vector3.new(-80, 0, -80)
		ResourceNodeManager.spawnNodesNearPosition(fertileAreaCenter, 50, "Food", math.floor(15 * dm))

		-- Iron area (southeast of spawn)
		local ironAreaCenter = spawnPoint.Position + Vector3.new(80, 0, -80)
		ResourceNodeManager.spawnNodesNearPosition(ironAreaCenter, 40, "Iron_Ore", math.floor(12 * dm))
	end

	-- 5. Peasants are spawned when the player places their Keep (see PlaceBuilding → "Keep" handler).
	-- Do NOT spawn them here — the Keep hasn't been placed yet, so any peasants
	-- spawned at the spawn point will be trapped inside the Keep's pathfinding
	-- obstacle once the player places it on top of them.

	GameManagerDebug:info(
		`Initial setup complete for {player.Name} in {factionData.Name} (peasants will spawn with Keep)`
	)
end

-- AI-specific spawn function (doesn't require Player object). Returns the AI's
-- Keep instance (or nil if it failed to spawn) so the caller can register the
-- kingdom with EliminationManager for Keep Capture/Keep Destroyed tracking.
local function spawnAIInitialSetup(ownerId: number, ownerName: string, factionData: any, spawnPoint: CFrame, lobbySettings: any): Instance?
	GameManagerDebug:info("AI " .. ownerName .. " spawning as " .. factionData.Name)

	-- 1. Spawn Keep at the spawn point (AI gets Keep at game start, same as players)
	local keep = BuildingManager.createBuilding(ownerId, "Keep", spawnPoint, nil, nil, true)
	if keep then
		GameManagerDebug:info("Spawned Keep for AI " .. ownerName)

		-- Deterministic banner color per AI kingdom (AI has no lobby color pick)
		local aiBannerPalette = {
			Color3.fromRGB(170, 40, 40), -- crimson
			Color3.fromRGB(60, 90, 170), -- royal blue
			Color3.fromRGB(70, 130, 60), -- forest green
			Color3.fromRGB(150, 110, 40), -- gold ochre
		}
		local aiColor = aiBannerPalette[(math.abs(ownerId) - 1) % #aiBannerPalette + 1]
		BuildingManager.applyBannerColor(keep, aiColor)

		-- Spawn starting peasants using SpawnPointSystem (same as player implementation).
		-- Spawn radius must clear the pathfinding obstacle (model bbox + padding).
		local peasantCount = 3
		local _, aiKeepSize = keep:GetBoundingBox()
		local aiSafeSpawnRadius = math.max(aiKeepSize.X, aiKeepSize.Z) / 2 + 10
		local spawnPositions = SpawnPointSystem.getSpawnPositions(keep, {
			pattern = "circle",
			radius = aiSafeSpawnRadius,
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
				local offset = Vector3.new(math.cos(angle) * aiSafeSpawnRadius, 0, math.sin(angle) * aiSafeSpawnRadius)
				local position = keepPos + offset
				UnitManager.createUnit("Peasant", ownerId, position, factionData.Name)
			end
			GameManagerDebug:info(`Spawned {peasantCount} peasants using fallback for AI {ownerName}`)
		end
		-- Spawn a King (Lord) unit for AI Direct Slay: a plain NPC combat unit
		-- (UnitManager.createUnit — the same data-driven path every other AI
		-- unit above uses; no Player character, so none of the camera/
		-- first-person hooks that key off IsKing/CanFirstPerson ever run for
		-- it). Its death is caught by EliminationManager's CombatManager.
		-- onUnitKilled hook (unitType == "King") for the Direct Slay path,
		-- mirroring the human Lord's permadeath in Conquest/Regicide modes.
		local kingSpawnPos = spawnPoint.Position + Vector3.new(0, 10, -aiSafeSpawnRadius - 10)
		local aiKing = UnitManager.createUnit("King", ownerId, kingSpawnPos, factionData.Name)
		if aiKing then
			GameManagerDebug:info(`Spawned King (Lord) for AI {ownerName}`)
		else
			GameManagerDebug:warn(`Failed to spawn King for AI {ownerName} — Direct Slay unavailable, Keep Capture still applies`)
		end
	else
		GameManagerDebug:warn("Failed to spawn Keep for AI " .. ownerName)
	end

	-- Wait to ensure Keep is fully registered before spawning troops
	-- 2. No starting troops for AI - they will train units as needed
	-- Note: AI starts with only their Keep and will build/train units through normal gameplay

	-- 3. Spawn resource nodes — skip in Studio terrain mode (patches spawned globally once)
	local isStudioModeAI = (function()
		local flag = workspace:FindFirstChild("UseStudioTerrain")
		return flag ~= nil and flag:IsA("BoolValue") and flag.Value == true
	end)()

	if not isStudioModeAI then
		local woodAreaCenter = spawnPoint.Position + Vector3.new(-80, 0, 80)
		ResourceNodeManager.spawnNodesNearPosition(woodAreaCenter, 60, "Wood", 25)

		local stoneAreaCenter = spawnPoint.Position + Vector3.new(80, 0, 80)
		ResourceNodeManager.spawnNodesNearPosition(stoneAreaCenter, 50, "Stone", 20)

		local fertileAreaCenter = spawnPoint.Position + Vector3.new(-80, 0, -80)
		ResourceNodeManager.spawnNodesNearPosition(fertileAreaCenter, 50, "Food", 15)

		local ironAreaCenter = spawnPoint.Position + Vector3.new(80, 0, -80)
		ResourceNodeManager.spawnNodesNearPosition(ironAreaCenter, 40, "Iron_Ore", 12)
	end

	GameManagerDebug:info(
		"Spawned Keep and resource nodes for AI " .. ownerName .. " in " .. factionData.Name
	)

	return keep
end

-- ── Hero combat (the Lord, third person, normal game) ───────────────────────
-- The Battle Arena registers its hero fighter on spawn (ArenaMode); in a normal
-- game the Lord only joins the combat roster while the player is actually in
-- hero mode (V toggle), so RTS mode leaves him a plain character.
--
-- Combat itself lives in server/Combat/HeroCombat.luau (state machine, combo
-- chain, block/parry, dodge i-frames) with all tuning in CombatConfig.Hero.
-- GameManager's only jobs here are: register/unregister on the mode toggle,
-- swap the weapon visuals, and forward validated remote actions.
--
-- LORD_FIGHTER derives from CombatConfig.Hero.fighter rather than restating it,
-- so the Lord and the arena hero cannot drift apart.
local LORD_FIGHTER = {
	baseType = CombatConfig.Hero.fighter.baseType, -- seeds the damage-type profile only
	maxHealth = CombatConfig.Hero.fighter.maxHealth,
	attackDamage = CombatConfig.Hero.fighter.attackDamage,
	armor = CombatConfig.Hero.fighter.armor,
}

-- Show or hide the Lord's sword + shield. WeaponVisuals builds them from the
-- "King" combat profile and welds them to the avatar's hands; there's no detach
-- API, so removal is by the names the builders use ("Weapon", "Shield").
local function setLordWeaponVisible(character: Model?, visible: boolean)
	if not character then
		return
	end
	for _, child in character:GetChildren() do
		if child:IsA("Model") and (child.Name == "Weapon" or child.Name == "Shield") then
			child:Destroy()
		end
	end
	character:SetAttribute("WeaponKind", nil)
	if visible then
		WeaponVisuals.attach(character, "King", "Hero")
	end
end

-- ── Hero action dispatch ────────────────────────────────────────────────────
--
-- Every hero action arrives as GameEvent("<Action>", payload) from
-- client/Combat/HeroCombatController. This layer does NOTHING but shape
-- validation and forwarding — HeroCombat owns legality, cooldowns, combo state,
-- damage and i-frames, because the client is assumed hostile and a client-side
-- guard is a convenience, never a control.
--
--   "HeroLight"   { aim = Vector3 }
--   "HeroHeavy"   { aim = Vector3 }
--   "HeroRanged"  { aim = Vector3 }
--   "HeroBlock"   { blocking = boolean, aim = Vector3 }
--   "HeroDodge"   { direction = Vector3 }   -- omit/zero for "roll backwards"
--
-- Legacy aliases "PlayerMeleeAttack" / "PlayerRangedAttack" map onto HeroLight /
-- HeroRanged so older clients and saved Studio test scripts keep working.
--
-- Arena players are handled by ArenaMode's own dispatch (gated on isArenaPlayer),
-- which forwards into the SAME HeroCombat — so the two modes share one
-- implementation. Guard here to avoid double-firing an action.
local function heroPayloadAim(data: any): Vector3?
	if typeof(data) ~= "table" then
		return nil
	end
	local aim = (data :: any).aim
	if typeof(aim) ~= "Vector3" then
		return nil
	end
	return aim :: Vector3
end

local function handleHeroAction(player: Player, action: string, data: any)
	if ArenaMode.isArenaPlayer(player) then
		return -- ArenaMode already routed this
	end

	if action == "HeroBlock" then
		-- `blocking` must be a real boolean; a truthy string from a hacked client
		-- would otherwise raise a shield that could never be lowered.
		local blocking = typeof(data) == "table" and (data :: any).blocking or nil
		if typeof(blocking) ~= "boolean" then
			return
		end
		CombatManager.heroBlock(player, blocking, heroPayloadAim(data))
		return
	end

	if action == "HeroDodge" then
		-- Direction is optional (nil = roll backwards, resolved client-side against
		-- the character's facing). HeroCombat rejects malformed non-nil vectors.
		local direction = typeof(data) == "table" and (data :: any).direction or nil
		CombatManager.heroDodge(player, direction)
		return
	end

	local aim = heroPayloadAim(data)
	if not aim then
		return
	end
	if action == "HeroLight" then
		CombatManager.heroLight(player, aim)
	elseif action == "HeroHeavy" then
		CombatManager.heroHeavy(player, aim)
	elseif action == "HeroRanged" then
		CombatManager.heroRanged(player, aim)
	end
end

-- Actions that issue orders (unit/worker movement, building/training/research,
-- combat, policy). An eliminated kingdom (Conquest/Regicide military modes)
-- keeps its RTS camera and can spectate, but stale client UI must not be able
-- to keep giving orders after the loss — every handler below is rejected.
-- Read-only queries (GetStats, GetGlory, GetQuests, ...), camera toggling and
-- LeaveGame stay available so a defeated player can still watch the match end.
local ELIMINATION_GATED_ACTIONS: { [string]: boolean } = {
	StartPlacement = true,
	PlaceBuilding = true,
	MoveUnit = true,
	MoveUnitsInFormation = true,
	MoveWorkers = true,
	ReturnToKeep = true,
	UnassignWorkers = true,
	StartTraining = true,
	DeleteBuilding = true,
	UndoDeletion = true,
	AttackTarget = true,
	SetStance = true,
	UseAbility = true,
	UpgradeBuilding = true,
	AssignWorker = true,
	UnassignWorker = true,
	StartResearch = true,
	-- Hero combat. A fallen kingdom's Lord must not be able to keep swinging;
	-- HeroBlock/HeroDodge are gated too, not just the attacks, so an eliminated
	-- player cannot sit invulnerable behind a raised shield mid-spectate.
	HeroLight = true,
	HeroHeavy = true,
	HeroRanged = true,
	HeroBlock = true,
	HeroDodge = true,
	PlayerMeleeAttack = true, -- legacy alias of HeroLight
	PlayerRangedAttack = true, -- legacy alias of HeroRanged
	SetPolicy = true,
}

-- Handle game events from client
GameEvent.OnServerEvent:Connect(function(player, action, data)
	local playerData = PlayerManager.get(player)
	if not playerData then
		GameManagerDebug:warn(`No player data for {player.Name}`)
		return
	end

	if ELIMINATION_GATED_ACTIONS[action] and EliminationManager.isEliminated(player) then
		GameEvent:FireClient(player, "Error", {
			message = "Your kingdom has fallen — you can only spectate.",
		})
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

		-- A multiplayer lobby sends a client notification for navigation, but the
		-- settings that begin the match must come from the server-created payload.
		-- A player still in a lobby cannot bypass the countdown with a handcrafted
		-- StartGame RemoteEvent.
		local wasInLobby = LobbyManager.isPlayerInLobby(player)
		local lobbySettings = LobbyManager.consumePendingStartSettings(player)
		if wasInLobby and not lobbySettings then
			GameManagerDebug:warn(`Rejected premature StartGame request from {player.Name}`)
			GameEvent:FireClient(player, "Error", { message = "Wait for the lobby countdown to finish." })
			return
		end

		local settings = lobbySettings or (if typeof(data) == "table" then data else {})
		local vikingRaidsEnabled = settings.vikingRaids or false
		local peaceTimeStr = settings.peaceTime or "10 minutes"
		local selectedMap = if typeof(settings.map) == "string" then settings.map else MapData.DefaultMap
		local showTutorial = if settings.showTutorial ~= nil then settings.showTutorial else true
		local factionFromSettings = settings.faction -- From multiplayer lobby

		if not MapData.getMap(selectedMap) then
			GameManagerDebug:warn(`Invalid map requested by {player.Name}: {selectedMap}; using default`)
			selectedMap = MapData.DefaultMap
		end

		-- The Workspace is shared by every player in a Roblox server. Lock the
		-- selected map before any terrain, pathfinding, or spawn state is created.
		if not MapManager.lockMatchMap(selectedMap) then
			local lockedMap = MapManager.getCurrentMapName()
			GameManagerDebug:warn(`Rejected map {selectedMap} for {player.Name}; match is locked to {lockedMap}`)
			GameEvent:FireClient(player, "Error", {
				message = `This server is already running {MapManager.getCurrentMap().Name}.`,
			})
			return
		end
		selectedMap = MapManager.getCurrentMapName()

		-- Battle Arena mode: no terrain, no Keep, no economy. ArenaMode handles
		-- the whole session (arena build, army spawning, GameStarted event).
		if selectedMap == "BattleArena" then
			ArenaMode.startForPlayer(player, playerData, settings)
			return
		end

		-- The first player initializes shared map state. Later players consume the
		-- cached configuration, avoiding terrain clears and pathfinding resets.
		local mapConfig = matchMapConfig or MapManager.getCurrentMap()
		SpawnManager.setMapConfig(mapConfig)
		GameManagerDebug:info(`Map loaded: {mapConfig.Name} ({mapConfig.Size}x{mapConfig.Size})`)

		-- Determine whether to use studio/editor terrain or generate procedurally.
		-- Builtin maps with a BuiltinMapData module, __custom__ maps, and UseStudioTerrain
		-- all skip terrain generation and use painted stroke data instead.
		local studioTerrainFlag = workspace:FindFirstChild("UseStudioTerrain")
		local useStudioTerrain = (studioTerrainFlag ~= nil and studioTerrainFlag:IsA("BoolValue") and studioTerrainFlag.Value == true)
			or (selectedMap == "__custom__")

		-- Check if there is a shipped BuiltinMapData module for this map key.
		-- These are created by copy-pasting the data module from the editor Export.
		local builtinDataFolder = ReplicatedStorage:FindFirstChild("Shared")
			and ReplicatedStorage.Shared:FindFirstChild("GameData")
			and ReplicatedStorage.Shared.GameData:FindFirstChild("BuiltinMapData")
		local builtinDataModule = builtinDataFolder and builtinDataFolder:FindFirstChild(selectedMap)
		if builtinDataModule then
			useStudioTerrain = true
			if not studioCustomMapData then
				local ok, data = pcall(require, builtinDataModule)
				if ok and data then
					studioCustomMapData = data
					GameManagerDebug:info("Loaded builtin map data for: " .. selectedMap)
				else
					GameManagerDebug:warn("Failed to load BuiltinMapData module for: " .. selectedMap)
				end
			end
		end

		if not useStudioTerrain then
			if not mapWorldInitialized then
				TerrainGenerator.generate(mapConfig)
			end
		elseif not mapWorldInitialized then
			GameManagerDebug:info("Studio/custom terrain mode — skipping procedural terrain generation")

			-- Load painted custom map data from DataStore if not already loaded from a builtin module.
			-- customMapId/customMapAuthorId come from lobby SelectCustomMap or editor ActivateCustomMap.
			if not studioCustomMapData and settings.customMapId and settings.customMapAuthorId then
				studioCustomMapData = MapEditorManager.loadCustomMapData(
					settings.customMapAuthorId, settings.customMapId
				)
				-- If the custom map has a Size field, patch mapConfig so systems use the right scale
				if studioCustomMapData and studioCustomMapData.Size then
					mapConfig = {}
					for k, v in pairs(MapManager.getCurrentMap()) do mapConfig[k] = v end
				mapConfig.Size = studioCustomMapData.Size
				mapConfig.Name = studioCustomMapData.Name or mapConfig.Name
				SpawnManager.setMapConfig(mapConfig)
			end
				-- Replay sculpt strokes and placed features onto the terrain
				if studioCustomMapData then
					local terrain = workspace:FindFirstChildOfClass("Terrain")
					if terrain then
						MapEditorManager.replaySculptStrokes(terrain, studioCustomMapData)
						MapEditorManager.replayFeatures(terrain, studioCustomMapData)
						GameManagerDebug:info("Replayed sculpt strokes and features for custom map")
					end
				end
			end

			-- Merge painted KeepSpawnZones into mapConfig so SpawnManager uses them.
			if studioCustomMapData and studioCustomMapData.KeepSpawnZones and #studioCustomMapData.KeepSpawnZones > 0 then
				mapConfig = {}
				for k, v in pairs(MapManager.getCurrentMap()) do mapConfig[k] = v end
				mapConfig.KeepSpawnZones = studioCustomMapData.KeepSpawnZones
				SpawnManager.setMapConfig(mapConfig)
				GameManagerDebug:info("Merged painted KeepSpawnZones into mapConfig")
			end

			-- Spawn resource nodes from painted patches once (shared across all players).
			if studioCustomMapData and not studioResourcePatchesSpawned then
				local patches = studioCustomMapData.ResourcePatches or {}
				if #patches > 0 then
					ResourceNodeManager.spawnNodesFromPatches(patches)
					studioResourcePatchesSpawned = true
					GameManagerDebug:info("Spawned resource nodes from " .. #patches .. " painted patches")
				else
					-- No painted patches: fall back to spawning resources near each keep spawn zone
					local keepZones = mapConfig.KeepSpawnZones
					if keepZones and #keepZones > 0 then
						for _, zone in ipairs(keepZones) do
							local cx, cz = zone.X, zone.Z
							ResourceNodeManager.spawnNodesFromPatches({
								{ ResourceType = "Wood",     Position = { X = cx - 80, Z = cz + 80 }, Radius = 60, Density = 5 },
								{ ResourceType = "Stone",    Position = { X = cx + 80, Z = cz + 80 }, Radius = 50, Density = 5 },
								{ ResourceType = "Food",     Position = { X = cx - 80, Z = cz - 80 }, Radius = 50, Density = 5 },
								{ ResourceType = "Iron_Ore", Position = { X = cx + 80, Z = cz - 80 }, Radius = 40, Density = 5 },
							})
						end
						studioResourcePatchesSpawned = true
						GameManagerDebug:info("No painted patches — spawned fallback resources near " .. #keepZones .. " keep zones")
					end
				end
			end
		end

		if not mapWorldInitialized then
			-- Configure pathfinding only after a custom map has applied its real
			-- dimensions and keep zones. Reinitializing this per joining player
			-- discards shared navigation state in an RTS match.
			SpawnManager.setMapConfig(mapConfig)
			PathfindingIntegration.initialize(mapConfig.Size)
			matchMapConfig = mapConfig
			mapWorldInitialized = true
			GameManagerDebug:info(`Shared world initialized for {mapConfig.Name}`)
		end

		-- Parse peace time (format: "10 minutes")
		local peaceTimeMinutes = 0 -- default
		local minutes = peaceTimeStr:match("(%d+)")
		if minutes then
			peaceTimeMinutes = tonumber(minutes) or 10
		end

		-- Apply lobby settings to global systems
		GameSettings.setGameSpeed(settings.gameSpeed or "Normal")
		CaravanManager.setTradeEnabled(settings.abilityToTrade ~= false)
		CombatManager.setMoraleEnabled(settings.unitMorale ~= false)

		GameManagerDebug:info(`Viking Raids: {vikingRaidsEnabled}, Peace Time: {peaceTimeMinutes} minutes, Game Speed: {settings.gameSpeed or "Normal"}`)

		if vikingRaidsEnabled then
			-- Enable Viking Raids for this player
			VikingRaidSystem.enableRaids(player.UserId, peaceTimeMinutes)
			GameManagerDebug:info(`Viking Raids enabled for {player.Name} (peace time: {peaceTimeMinutes} minutes)`)
		end

		-- Assign player to their lobby-selected spawn zone, or auto-assign if none selected
		local spawnZone = if settings.quadrant and type(settings.quadrant) == "number"
			then SpawnManager.assignPlayerToExplicitSpawn(player.UserId, settings.quadrant)
			else SpawnManager.assignPlayerToSpawn(player.UserId)

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

		-- Store the lobby-selected kingdom color; applied to the Keep's
		-- Banner/Flag meshes when the player places their Keep.
		local playerColor = settings.playerColor
		if typeof(playerColor) == "table" and #playerColor == 3
			and typeof(playerColor[1]) == "number"
			and typeof(playerColor[2]) == "number"
			and typeof(playerColor[3]) == "number" then
			playerData.BannerColor = Color3.fromRGB(
				math.clamp(playerColor[1], 0, 255),
				math.clamp(playerColor[2], 0, 255),
				math.clamp(playerColor[3], 0, 255)
			)
			GameManagerDebug:info(`Stored banner color for {player.Name}`)
		end

		-- Wire up team alliances BEFORE any kingdom is registered or victory
		-- checks begin: EliminationManager.checkForWinner requires survivors to
		-- be mutually non-hostile, so a 2v2's shared victory only works if
		-- FactionManager already knows the two allied factions aren't enemies
		-- by the time the first kingdom (human or AI) is registered below.
		-- Only a multiplayer lobby start carries a teamOf map; a solo game has
		-- no layout to apply and keeps the plain FFA relationships from
		-- FactionManager.init().
		--
		-- Applied unconditionally, NOT once-per-match behind a flag. A flag would
		-- have to be reset on every path out of a match, and the reset currently
		-- lives only in the LeaveGame handler's "nobody left in game" branch --
		-- so a lobby that starts a second match without everyone first returning
		-- to the menu would silently inherit the PREVIOUS match's alliances, which
		-- is a wrong-teams bug that would look like a combat or victory bug.
		--
		-- applyTeamLayout rewrites relationships wholesale and is idempotent, and
		-- with at most four factions it is a handful of table writes, so repeating
		-- it per joining player is cheaper than owning that invalidation problem.
		if typeof(settings.teamOf) == "table" then
			FactionManager.applyTeamLayout(settings.teamOf)
		end

		-- Tell VictoryConditionManager when the game started and how long peace time is
		VictoryConditionManager.setGameStarted(player, peaceTimeMinutes * 60)
		-- Apply victory mode from lobby settings
		VictoryConditionManager.setVictoryMode(settings.victoryCondition or "Score")
		-- Military elimination (Direct Slay + Keep Capture) for Conquest/Regicide
		EliminationManager.setup(settings.victoryCondition or "Score", peaceTimeMinutes * 60)
		EliminationManager.registerPlayer(player)

		GameManagerDebug:info(`Assigned {player.Name} to spawn zone {spawnZone} ({factionName})`)

		-- Set starting resources dynamically based on lobby settings
		playerData.Resources.Wood = calculateStartingResources(settings.startingResources or "Standard", "Wood")
		playerData.Resources.Stone = calculateStartingResources(settings.startingResources or "Standard", "Stone")
		playerData.Resources.Gold = calculateStartingResources(settings.startingGold or "Standard", "Gold")
		playerData.Resources.Food = calculateStartingResources(settings.startingFood or "Standard", "Food")
		playerData.Resources.Iron_Bars =
			calculateStartingResources(settings.startingResources or "Standard", "Iron_Bars")
		-- Weapons use their own lobby setting (None/Bronze/Iron/Steel)
		local weaponAmounts = { None = 0, Bronze = 8, Iron = 20, Steel = 40 }
		playerData.Resources.Weapons = weaponAmounts[settings.startingWeapons] or 8

		-- Spawn initial setup with zone spawn point
		spawnInitialSetup(player, factionData, zoneSpawn, settings)

		-- Load character now (Players.CharacterAutoLoads is false)
		player:LoadCharacter()
		GameManagerDebug:info(`Loading character for {player.Name}`)

		-- Wait for character and teleport to the Lord spawn point: the Keep's
		-- SpawnLocation when a Keep already exists (e.g. restart mid-match),
		-- otherwise the assigned zone spawn.
		local character = player.Character or player.CharacterAdded:Wait()
		local humanoidRootPart = character:WaitForChild("HumanoidRootPart") :: BasePart
		humanoidRootPart.CFrame = getLordSpawnCFrame(playerData) or (zoneSpawn * CFrame.new(0, 3, 0))

		-- Tag the player's character as King (can't change name due to security restrictions)
		character:SetAttribute("OwnerId", player.UserId)
		character:SetAttribute("UnitType", "King")
		character:SetAttribute("IsKing", true)

		GameManagerDebug:info(`Character spawned and teleported {player.Name} to spawn zone {spawnZone} (tagged as King)`)

		-- Setup King health monitoring
		setupKingHealthMonitoring(player, character)

		-- Build zone bounds for client (used to colour placement ghosts)
		local zoneCenter: Vector3? = nil
		local zoneRadius: number? = nil
		local keepCenter = SpawnManager.getKeepSpawnCenter(spawnZone)
		if keepCenter then
			zoneCenter = keepCenter
			zoneRadius = SpawnManager.getKeepSpawnRadius(spawnZone)
		end

		-- Notify client
		GameEvent:FireClient(player, "GameStarted", {
			faction = factionName,
			resources = playerData.Resources,
			showTutorial = showTutorial,
			zoneCenter = zoneCenter,
			zoneRadius = zoneRadius,
			spawnZone = spawnZone,
			peaceTimeSeconds = peaceTimeMinutes * 60,
			victoryCondition = settings.victoryCondition or "Score",
		})

		-- Start game-loop systems on the first game start (not during lobby).
		-- Staggered so systems that need player buildings/units aren't burning
		-- cycles before anything exists in the world.
		if not workerLoopStarted then
			workerLoopStarted = true

			-- Immediate: needed from the very first frame
			MovementSystem.startLoop()
			CombatManager.startLoop()
			FogOfWarManager.startUpdates()
			WorkerManager.startLoop()
			VikingRaidSystem.startLoop()
			SiegeTowerSystem.startLoop()
			EliminationManager.startLoop()

			-- Environment: cheap, start early so first ticks happen naturally
			SeasonSystem.startLoop()
			WeatherSystem.startLoop()
			EventSystem.startLoop()
			TradeSystem.startLoop()

			-- Deferred 30s: players need time to place their Keep before
			-- population, training, happiness and economy systems matter
			task.delay(30, function()
				TrainingManager.startLoop()
				PopulationManager.startLoop()
				PopulationSystem.startLoop()
				HappinessManager.startLoop()
				ConsumptionSystem.startLoop()
				CaravanSystem.startLoop()
				EstateManager.startLoop()
			end)

			-- Deferred 60s: maintenance and taxes need buildings to exist;
			-- victory checks are meaningless in the opening minute
			task.delay(60, function()
				MaintenanceSystem.startLoop()
				TaxManager.startLoop()
				VictorySystem.startLoop()
				-- Starts with taxes, not before them: revolt risk is driven by
				-- tax pressure and food, so evaluating it while the player has
				-- neither would just spam risk warnings during setup.
				RevoltSystem.startLoop()
			end)
		end

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
				local aiKeep = spawnAIInitialSetup(aiData.UserId, aiData.Name, aiFactionData, aiSpawnPoint, settings)

				-- Register AI with AIManager for autonomous behavior
				AIManager.registerAI(aiData.UserId, aiData.Name, aiData.Faction, aiSpawnPoint)

				-- Register the AI kingdom for elimination tracking (Keep Capture +
				-- Direct Slay via its King unit's death — see EliminationManager).
				EliminationManager.registerAIKingdom(aiData.UserId, aiData.Name, aiKeep)

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

			-- Prestige structures (Hero Hubs) unlock at lifetime Glory thresholds
			if not GloryManager.canUnlockBuilding(player, data.buildingName) then
				local required = GloryManager.getBuildingGloryRequirement(data.buildingName)
				local earned = GloryManager.getLifetimeGlory(player)
				GameEvent:FireClient(player, "Error", {
					message = `{data.buildingName} requires {required} Glory (earned: {earned}). Win renown in melee combat!`,
				})
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

						-- Register the Keep's SpawnLocation as this Lord's spawn point.
						-- All future (re)spawns route through getLordSpawnCFrame, which
						-- prefers this SpawnLocation over the zone spawn.
						local keepSpawnLocation = getKeepSpawnLocation(playerData)
						if keepSpawnLocation then
							-- Disable engine auto-spawning here: spawns are per-owner and
							-- handled explicitly, so other players never hijack this pad.
							if keepSpawnLocation:IsA("SpawnLocation") then
								keepSpawnLocation.Enabled = false
							end
							playerData.SpawnPoint = keepSpawnLocation.CFrame
							GameManagerDebug:info(`Registered Keep SpawnLocation for {player.Name}`)
						else
							GameManagerDebug:warn(
								`Keep for {player.Name} has no SpawnLocation — Lord will respawn at zone spawn`
							)
						end

						-- Apply the lobby-selected kingdom color to the Keep's
						-- Banner/Flag meshes (warns internally if meshes are missing).
						if playerData.BannerColor then
							BuildingManager.applyBannerColor(building, playerData.BannerColor)
						end

						-- Get player's faction
						local playerFaction = playerData.Faction or "Kingdom"

						-- Use SpawnPointSystem to get spawn positions from the Keep's SpawnPoint part.
						-- Spawn radius must clear the pathfinding obstacle (model bbox + padding).
						-- All peasants spawn here (not in spawnInitialSetup) to avoid being
						-- trapped under the Keep obstacle.
						local peasantCount = 5
						local _, keepSize = building:GetBoundingBox()
						local safeSpawnRadius = math.max(keepSize.X, keepSize.Z) / 2 + 10
						local spawnPositions = SpawnPointSystem.getSpawnPositions(building, {
							pattern = "circle",
							radius = safeSpawnRadius,
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
								local offset = Vector3.new(math.cos(angle) * safeSpawnRadius, 0, math.sin(angle) * safeSpawnRadius)
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
					-- If it's a production building, auto-assign the NEAREST idle peasant
					-- (manual add/remove is handled by the AssignWorker/UnassignWorker
					-- actions below and the WorkerAssignmentPanel).
					if buildingInfo.requires_worker then
						WorkerManager.assignNearestIdlePeasant(building, player.UserId)
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
				-- A manual move order releases a working peasant/worker so it obeys
				-- the player instead of being re-tasked to its building each frame.
				WorkerManager.releaseFromWork(unitToMove)
				-- A direct move order takes priority over idle roaming: drop it from
				-- the idle pool so IdlePeasantManager stops steering it back home.
				IdlePeasantManager.removeIdlePeasant(unitToMove)
				-- Clear combat target and delegate movement to MovementSystem
				unitToMove:SetAttribute("CombatTarget", nil)
				unitToMove:SetAttribute("TargetPosition", data.targetPosition)
				unitToMove:SetAttribute("IsMoving", true)
				-- Clear pathfinding failure - player command overrides previous failures
				unitToMove:SetAttribute("PathfindingFailed", nil)
				-- A move order is a March: passive stance, don't auto-engage
				CombatManager.applyGroupMarch({ unitToMove })
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
					-- Manual formation move also releases any working civilians.
					WorkerManager.releaseFromWork(unit)
					IdlePeasantManager.removeIdlePeasant(unit)
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
						-- Tight arrival tolerance so units actually reach their
						-- slots (default 5-stud tolerance clumped tight formations)
						unit:SetAttribute("ArrivalDistance", 2.5)
						-- On arrival, MovementSystem snaps to the exact slot and
						-- faces the whole formation the same way (clean ranks)
						unit:SetAttribute("FormationFacing", facingDirection)
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
					unit:SetAttribute("ArrivalDistance", nil) -- default tolerance
					unit:SetAttribute("FormationFacing", nil)
					-- Clear pathfinding failure - player command overrides previous failures
					unit:SetAttribute("PathfindingFailed", nil)
				end
			end

			-- A travel order (not an in-place formation change) is a March:
			-- passive stance + everyone capped to the slowest member's speed so
			-- the formation arrives together.
			if data.isMove and #units >= 1 then
				CombatManager.applyGroupMarch(units)
			end
		end
	elseif action == "MoveWorkers" then
		-- Loose group move for selected peasants/workers (distinct from military
		-- formations). Releases them from work so they obey the player.
		if typeof(data) == "table" and data.unitIds and data.targetPosition then
			local units = {}
			for _, unitId in ipairs(data.unitIds) do
				local unit = findUnit(unitId)
				if unit and unit:GetAttribute("OwnerId") == player.UserId then
					WorkerManager.releaseFromWork(unit)
					-- A direct move order takes priority over idle roaming: drop the
					-- peasant from the idle pool so IdlePeasantManager stops steering it.
					IdlePeasantManager.removeIdlePeasant(unit)
					table.insert(units, unit)
				end
			end
			if #units > 0 then
				MovementSystem.moveGroup(units, data.targetPosition)
			end
		end
	elseif action == "ReturnToKeep" then
		-- Send selected peasants/workers back to the Keep (releases from work).
		if typeof(data) == "table" and data.unitIds then
			local keep = playerData.Keep
			if keep and keep.Parent then
				local dest = PathfindingIntegration.getApproachPosition(keep)
					or (keep.PrimaryPart and keep.PrimaryPart.Position)
				if dest then
					local units = {}
					for _, unitId in ipairs(data.unitIds) do
						local unit = findUnit(unitId)
						if unit and unit:GetAttribute("OwnerId") == player.UserId then
							WorkerManager.releaseFromWork(unit)
							IdlePeasantManager.removeIdlePeasant(unit)
							-- Returning home also deassigns: revert the job rig/label
							-- back to a plain Peasant. Use the returned (possibly new) model.
							unit = WorkerManager.revertToBaseUnit(unit)
							-- Called home: run, don't stroll. MovementSystem clears
							-- this on arrival. See the Gait contract in
							-- GameData/UnitAnimationsData.
							unit:SetAttribute("Gait", "hurry")
							table.insert(units, unit)
						end
					end
					if #units > 0 then
						MovementSystem.moveGroup(units, dest)
					end
				end
			end
		end
	elseif action == "UnassignWorkers" then
		-- Pull selected workers off their jobs and return them to the idle pool.
		if typeof(data) == "table" and data.unitIds then
			for _, unitId in ipairs(data.unitIds) do
				local unit = findUnit(unitId)
				if unit and unit:GetAttribute("OwnerId") == player.UserId then
					WorkerManager.releaseFromWork(unit)
					-- Revert the job rig + overhead label back to a plain Peasant, then
					-- idle the (possibly new) model.
					unit = WorkerManager.revertToBaseUnit(unit)
					IdlePeasantManager.addIdlePeasant(unit, player.UserId)
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
	elseif action == "GloryReduceCooldown" then
		-- Spend Glory to reset a hero ability's remaining cooldown
		if typeof(data) == "table" and data.abilityId then
			GameManagerDebug:info(`{player.Name} buying cooldown reset: {data.abilityId}`)
			AbilityManager.reduceCooldownWithGlory(player, data.abilityId)
		end
	elseif action == "GetGlory" then
		-- Send current Glory state to client (HUD initial fetch)
		GameEvent:FireClient(player, "GloryUpdate", {
			glory = GloryManager.getGlory(player),
			lifetime = GloryManager.getLifetimeGlory(player),
		})
	elseif action == "GetAbilityTree" then
		-- Hero ability tree UI: current node ranks + spendable Glory
		GameEvent:FireClient(player, "AbilityTreeData", {
			ranks = MonetizationManager.getAbilityRanks(player),
			glory = GloryManager.getGlory(player),
		})
	elseif action == "PurchaseAbilityNode" then
		-- Spend Glory to unlock/upgrade a hero ability tree node (MonetizationConfig)
		if typeof(data) == "table" and typeof(data.nodeId) == "string" then
			local ok, reason = MonetizationManager.purchaseAbilityNode(player, data.nodeId)
			GameManagerDebug:info(`{player.Name} ability node purchase {data.nodeId}: {ok} ({reason})`)
			GameEvent:FireClient(player, "AbilityNodeResult", {
				nodeId = data.nodeId,
				success = ok,
				reason = reason,
				ranks = MonetizationManager.getAbilityRanks(player),
				glory = GloryManager.getGlory(player),
			})
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
	elseif action == "AssignWorker" then
		-- Manual "add worker": staff the nearest idle peasant to a building
		-- (respects worker_slots inside WorkerManager).
		if typeof(data) == "table" and data.buildingId then
			for _, building in playerData.Buildings do
				if building and building.Parent and building.Name == data.buildingId then
					if building:GetAttribute("OwnerId") == player.UserId then
						local ok = WorkerManager.assignNearestIdlePeasant(building, player.UserId)
						if not ok then
							GameEvent:FireClient(player, "Error", {
								message = "No idle peasant available, or the building is fully staffed.",
							})
						end
					end
					break
				end
			end
		end
	elseif action == "UnassignWorker" then
		-- Manual "remove worker": release one worker back to idle.
		if typeof(data) == "table" and data.buildingId then
			for _, building in playerData.Buildings do
				if building and building.Parent and building.Name == data.buildingId then
					if building:GetAttribute("OwnerId") == player.UserId then
						WorkerManager.unassignWorker(building, 1)
					end
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
	elseif action == "CameraModeChanged" then
		-- Client toggled between the RTS overhead view and THIRD-PERSON hero mode
		-- (V). Echo the value back so the HUD (which listens on OnClientEvent) can
		-- swap layouts, then manage the Lord's combat registration for normal games.
		--
		-- "Hero" is the current name; "King" is the legacy spelling that older HUD
		-- builds and saved Studio test scripts still send. Both are accepted and
		-- NORMALIZED to "Hero" before anything downstream sees them, and the echo
		-- sends the normalized value — so a client that spoke legacy on the way in
		-- gets told the modern name and converges. Mirrors ViewMode.normalize on
		-- the client (which the server must not require: it is client-only state).
		local mode: string? = if data == "RTS"
			then "RTS"
			elseif data == "Hero" or data == "King" then "Hero"
			else nil
		if not mode then
			return
		end
		GameEvent:FireClient(player, "CameraModeChanged", mode)

		-- The Battle Arena registers its hero on spawn; don't double-register.
		if ArenaMode.isArenaPlayer(player) then
			return
		end

		local character = player.Character
		if mode == "Hero" then
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if
				character
				and character:GetAttribute("IsKing")
				and humanoid
				and humanoid.Health > 0
				and not character:GetAttribute("PlayerFighter")
			then
				-- Preserve the current health fraction across the stat swap so the
				-- V toggle can't be used as a free full heal (the combat loop
				-- mirrors playerControlled health from the Humanoid every tick).
				local healthFraction = humanoid.Health / math.max(humanoid.MaxHealth, 1)
				CombatManager.registerPlayerFighter(character, playerData.Faction or "Kingdom", player.UserId, {
					baseType = LORD_FIGHTER.baseType,
					maxHealth = LORD_FIGHTER.maxHealth,
					attackDamage = LORD_FIGHTER.attackDamage,
					armor = LORD_FIGHTER.armor,
				})
				humanoid.Health = math.max(1, LORD_FIGHTER.maxHealth * healthFraction)
				-- Hero action state (combo chain, block/parry, dodge) lives alongside
				-- the fighter registration and must be created and torn down with it,
				-- or a re-entry would resume mid-combo with a stale cooldown.
				CombatManager.registerHero(player, character, { maxHealth = LORD_FIGHTER.maxHealth })
				-- Draw the Lord's sword and shield. The "King" CombatConfig profile
				-- already specifies weapon = "Sword", shield = true, so this is the
				-- same cosmetic path every unit uses — and WeaponVisuals finds the
				-- R15 avatar's RightHand/LeftHand grips without any special casing.
				setLordWeaponVisible(character, true)
				GameManagerDebug:info(`{player.Name}'s Lord entered hero combat`)
			end
		else
			-- Always tear the hero state down, even if the character is already gone
			-- (dying while in hero mode fires RTS on the way out): dropping the
			-- per-player table is what prevents the leak.
			CombatManager.unregisterHero(player)
			if character then
				CombatManager.unregisterPlayerFighter(character)
				character:SetAttribute("PlayerFighter", nil)
				-- Sheathe: the RTS camera shouldn't leave a sword stuck to the avatar.
				setLordWeaponVisible(character, false)
			end
			GameManagerDebug:info(`{player.Name}'s Lord returned to RTS mode`)
		end
	elseif
		action == "HeroLight"
		or action == "HeroHeavy"
		or action == "HeroRanged"
		or action == "HeroBlock"
		or action == "HeroDodge"
	then
		handleHeroAction(player, action, data)
	elseif action == "PlayerMeleeAttack" or action == "PlayerRangedAttack" then
		-- Legacy aliases, kept working so anything still sending the old action
		-- names (older client builds, saved Studio test scripts) routes into the
		-- same hero state machine instead of silently doing nothing.
		handleHeroAction(player, if action == "PlayerMeleeAttack" then "HeroLight" else "HeroRanged", data)
	elseif action == "GetAbilities" then
		-- Send abilities to client (with current Glory so the panel can render costs)
		local abilities = AbilityManager.getAbilities()
		local cooldowns = AbilityManager.getAllCooldowns(player)
		GameEvent:FireClient(player, "AbilitiesData", {
			abilities = abilities,
			cooldowns = cooldowns,
			glory = GloryManager.getGlory(player),
			lifetimeGlory = GloryManager.getLifetimeGlory(player),
		})
	elseif action == "SetPolicy" then
		-- Kingdom Policies UI: data = { category = "Taxation"|"Food Rations", policy = <name> }
		-- Policy names/values live in EconomyConfig (TaxPolicies / RationsPolicies).
		if typeof(data) == "table" and typeof(data.category) == "string" and typeof(data.policy) == "string" then
			local applied = false
			if data.category == "Taxation" then
				applied = TaxManager.setTaxPolicy(player, data.policy)
			elseif data.category == "Food Rations" then
				applied = ConsumptionManager.setRationsPolicy(player, data.policy)
			end

			if applied then
				GameManagerDebug:info(`{player.Name} set policy {data.category} -> {data.policy}`)
				GameEvent:FireClient(player, "PolicyUpdated", {
					category = data.category,
					policy = data.policy,
				})
				-- Policies move happiness/taxes: refresh the dashboard right away
				EconomyDashboardManager.sendUpdate(player)
			else
				GameManagerDebug:warn(`{player.Name} sent invalid policy {data.category}/{data.policy}`)
			end
		end
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
		playerData.Keep = nil
		playerData.Happiness = 50

		-- Reset resources to 0
		for resource, _ in pairs(playerData.Resources) do
			playerData.Resources[resource] = 0
		end

		-- ── Match-lifecycle teardown for THIS player ────────────────────────
		-- Single teardown point: every manager that accumulates per-match
		-- state for a real player gets a clean slate here so a new match can
		-- start without a server restart. AI kingdoms never fire LeaveGame (no
		-- Player instance) — they're cleared in the bulk branch below instead.
		EliminationManager.cleanupPlayer(player.UserId)
		EstateManager.releaseEstatesForOwner(player.UserId)
		VictoryConditionManager.create(player) -- fresh victory/loss state
		AchievementManager.resetMatchStats(player) -- unlocked achievements persist
		GloryManager.resetPlayer(player)
		SpawnManager.removePlayer(player.UserId)

		GameManagerDebug:info(`{player.Name} successfully left game - all data cleaned up`)

		-- If no one is left in-game, reset the shared map state AND every
		-- manager's global/AI-owned match state so the next match starts
		-- clean. Lifecycle: lobby → StartGame → match → elimination/victory
		-- → this teardown → lobby.
		local anyoneInGame = false
		for _, otherPlayer in ipairs(Players:GetPlayers()) do
			local otherData = PlayerManager.get(otherPlayer)
			if otherData and otherData.GameState == "InGame" then
				anyoneInGame = true
				break
			end
		end
		if not anyoneInGame then
			ResourceNodeManager.clearAllNodes()
			studioResourcePatchesSpawned = false
			studioCustomMapData = nil
			matchMapConfig = nil
			mapWorldInitialized = false
			MapManager.unlockMatchMap()

			-- AI kingdoms have no leave event of their own — tear them all
			-- down here (destroys their remaining buildings/units too).
			AIManager.resetMatch()
			EliminationManager.resetMatch()
			EstateManager.resetMatch()
			GloryManager.resetMatch()
			SpawnManager.resetMatch()

			GameManagerDebug:info("Last player left game — cleared match state for next match")
		end

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
	elseif action == "RenamePlayer" then
		-- Players may rename the AI kingdoms they are about to fight, and their
		-- own entry. LobbyManager refuses renaming another human.
		local targetUserId, newName = ...
		LobbyManager.renamePlayer(player, targetUserId, newName)
	elseif action == "ToggleReady" then
		LobbyManager.toggleReady(player)
	elseif action == "ListUserMaps" then
		-- Return the player's saved editor maps so the lobby can show them
		local maps = MapEditorManager.getUserMaps(player)
		LobbyEvent:FireClient(player, "UserMapsList", maps)
	elseif action == "SelectCustomMap" then
		-- Player picked one of their saved maps; store as lobby custom map
		local mapId = ...
		LobbyManager.voteSetting(player, "selectedMap", "__custom__")
		LobbyManager.voteSetting(player, "customMapId", mapId)
		LobbyManager.voteSetting(player, "customMapAuthorId", player.UserId)
	end
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
	elseif action == "SculptTerrain" then
		local strokes = ...
		MapEditorManager.sculptTerrain(player, strokes)
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
	elseif action == "UndoStroke" then
		MapEditorManager.undoStroke(player)
	elseif action == "RedoStroke" then
		MapEditorManager.redoStroke(player)
	elseif action == "RenameMap" then
		local data = ...
		MapEditorManager.renameMap(player, data)
	elseif action == "DeleteMap" then
		local mapId = ...
		MapEditorManager.deleteMap(player, mapId)
	elseif action == "PlaceResourcePatch" then
		local patches = ...
		MapEditorManager.placeResourcePatch(player, patches)
	elseif action == "DeleteResourcePatch" then
		local patchId = ...
		MapEditorManager.deleteResourcePatch(player, patchId)
	elseif action == "PaintZone" then
		local strokes = ...
		MapEditorManager.paintZone(player, strokes)
	elseif action == "PaintZonePolygon" then
		local data = ...
		MapEditorManager.paintZonePolygon(player, data)
	elseif action == "ShowZoneOverlay" then
		MapEditorManager.showZoneOverlay(player)
	elseif action == "HideZoneOverlay" then
		MapEditorManager.hideZoneOverlay(player)
	elseif action == "ShowResourceOverlay" then
		MapEditorManager.showResourceOverlay(player)
	elseif action == "HideResourceOverlay" then
		MapEditorManager.hideResourceOverlay(player)
	elseif action == "UpdateKeepSpawn" then
		local data = ...
		MapEditorManager.updateKeepSpawn(player, data)
	elseif action == "ActivateCustomMap" then
		-- Set this player's saved map as the lobby's custom map
		local session = MapEditorManager.getSession(player)
		if session then
			LobbyManager.voteSetting(player, "customMapId", session.MapId)
			LobbyManager.voteSetting(player, "customMapAuthorId", player.UserId)
			local ev = ReplicatedStorage:FindFirstChild("RemoteEvents")
				and ReplicatedStorage.RemoteEvents:FindFirstChild("MapEditorEvent")
			if ev then
				ev:FireClient(player, "CustomMapActivated", { mapId = session.MapId })
			end
			GameManagerDebug:info(player.Name .. " activated custom map: " .. session.MapId)
		end
	end
end)

-- Clean up map editor session when player leaves
GameManagerDebug:info("Server ready!")
