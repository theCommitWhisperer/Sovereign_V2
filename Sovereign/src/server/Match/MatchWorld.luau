--!strict
-- MatchWorld: owns the shared, once-per-match state of the physical world --
-- terrain, map config, painted map data, pathfinding bounds, resource patches.
--
-- This used to be four mutable upvalues in GameManager.server.luau
-- (studioCustomMapData, studioResourcePatchesSpawned, matchMapConfig,
-- mapWorldInitialized) written from the middle of a 400-line StartGame handler
-- and reset from an unrelated branch of the LeaveGame handler. That split made
-- it impossible to answer "is the world ready?" from anywhere else, which is a
-- problem the moment a second entry point exists -- e.g. a teleport bootstrap in
-- a dedicated map place, which is the direction docs/MAP_AND_MINIMAP_ARCHITECTURE.md
-- is heading.
--
-- One rule: the Workspace is shared by every player in a Roblox server, so the
-- first player to arrive builds the world and everyone after them consumes it.
-- ensureInitialized() is therefore idempotent and safe to call per joining
-- player.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DebugManager = require(ReplicatedStorage.Shared.DebugManager)

local Managers = script.Parent.Parent.Managers
local Systems = script.Parent.Parent.Systems

local MapEditorManager = require(Managers.MapEditorManager)
local MapManager = require(Managers.MapManager)
local ResourceNodeManager = require(Managers.ResourceNodeManager)
local SpawnManager = require(Managers.SpawnManager)
local PathfindingIntegration = require(Systems.PathfindingIntegration)
local TerrainGenerator = require(Systems.TerrainGenerator)

local WorldDebug = DebugManager.createChannel("MatchWorld", false)

local MatchWorld = {}

-- Painted/sculpted map data, loaded once per match from either a shipped
-- BuiltinMapData module or the map editor's DataStore.
local customMapData: any? = nil
-- Resource nodes are spawned once for the whole server, not per player.
local resourcePatchesSpawned = false
-- The map config the match actually settled on, after custom-map size and
-- KeepSpawnZones overrides have been merged in.
local mapConfig: any? = nil
local initialized = false

function MatchWorld.isInitialized(): boolean
	return initialized
end

function MatchWorld.getMapConfig(): any?
	return mapConfig
end

function MatchWorld.getCustomMapData(): any?
	return customMapData
end

--- True once resource nodes have been placed from painted patches. spawnInitialSetup
--- checks this to avoid scattering a second, procedural set of nodes on top of a
--- hand-authored map.
function MatchWorld.hasSpawnedResourcePatches(): boolean
	return resourcePatchesSpawned
end

--- Load the shipped BuiltinMapData module for a map key, if one exists.
--- These are produced by the map editor's Export and committed to
--- src/shared/GameData/BuiltinMapData/<MapKey>.luau.
local function loadBuiltinData(selectedMap: string): boolean
	local sharedFolder = ReplicatedStorage:FindFirstChild("Shared")
	local gameDataFolder = sharedFolder and sharedFolder:FindFirstChild("GameData")
	local builtinFolder = gameDataFolder and gameDataFolder:FindFirstChild("BuiltinMapData")
	local module = builtinFolder and builtinFolder:FindFirstChild(selectedMap)
	if not module then
		return false
	end

	if not customMapData then
		local ok, data = pcall(require, module)
		if ok and data then
			customMapData = data
			WorldDebug:info(`Loaded builtin map data for: {selectedMap}`)
		else
			WorldDebug:warn(`Failed to load BuiltinMapData module for: {selectedMap}`)
		end
	end

	-- A builtin data module always implies hand-authored terrain, even when the
	-- UseStudioTerrain flag is missing from Workspace.
	return true
end

--- Copy the live map config so per-match overrides never mutate MapData's table.
local function cloneCurrentMapConfig(): any
	local clone = {}
	for key, value in pairs(MapManager.getCurrentMap()) do
		clone[key] = value
	end
	return clone
end

local function spawnFallbackResources(config: any)
	local keepZones = config.KeepSpawnZones
	if not keepZones or #keepZones == 0 then
		return
	end

	for _, zone in ipairs(keepZones) do
		local cx, cz = zone.X, zone.Z
		ResourceNodeManager.spawnNodesFromPatches({
			{ ResourceType = "Wood", Position = { X = cx - 80, Z = cz + 80 }, Radius = 60, Density = 5 },
			{ ResourceType = "Stone", Position = { X = cx + 80, Z = cz + 80 }, Radius = 50, Density = 5 },
			{ ResourceType = "Food", Position = { X = cx - 80, Z = cz - 80 }, Radius = 50, Density = 5 },
			{ ResourceType = "Iron_Ore", Position = { X = cx + 80, Z = cz - 80 }, Radius = 40, Density = 5 },
		})
	end
	resourcePatchesSpawned = true
	WorldDebug:info(`No painted patches -- spawned fallback resources near {#keepZones} keep zones`)
end

--- Build the world for `selectedMap`, or return the already-built config.
--- Idempotent: safe to call for every joining player.
function MatchWorld.ensureInitialized(selectedMap: string, settings: any): any
	if initialized and mapConfig then
		SpawnManager.setMapConfig(mapConfig)
		return mapConfig
	end

	local config = mapConfig or cloneCurrentMapConfig()
	SpawnManager.setMapConfig(config)
	WorldDebug:info(`Map loaded: {config.Name} ({config.Size}x{config.Size})`)

	-- Hand-authored terrain is used when the Workspace flag is set, when the map
	-- is a player-made custom map, or when a shipped BuiltinMapData module exists
	-- for this key.
	local studioFlag = workspace:FindFirstChild("UseStudioTerrain")
	local useStudioTerrain = (studioFlag ~= nil and studioFlag:IsA("BoolValue") and studioFlag.Value == true)
		or (selectedMap == "__custom__")

	if loadBuiltinData(selectedMap) then
		useStudioTerrain = true
	end

	if not useStudioTerrain then
		TerrainGenerator.generate(config)
	else
		WorldDebug:info("Studio/custom terrain mode -- skipping procedural terrain generation")

		-- Player-made maps live in the map editor's DataStore rather than in a
		-- committed module. customMapId/customMapAuthorId arrive from the lobby's
		-- SelectCustomMap or the editor's ActivateCustomMap.
		if not customMapData and settings.customMapId and settings.customMapAuthorId then
			customMapData = MapEditorManager.loadCustomMapData(settings.customMapAuthorId, settings.customMapId)

			if customMapData and customMapData.Size then
				config = cloneCurrentMapConfig()
				config.Size = customMapData.Size
				config.Name = customMapData.Name or config.Name
				SpawnManager.setMapConfig(config)
			end

			if customMapData then
				local terrain = workspace:FindFirstChildOfClass("Terrain")
				if terrain then
					MapEditorManager.replaySculptStrokes(terrain, customMapData)
					MapEditorManager.replayFeatures(terrain, customMapData)
					WorldDebug:info("Replayed sculpt strokes and features for custom map")
				end
			end
		end

		if customMapData and customMapData.KeepSpawnZones and #customMapData.KeepSpawnZones > 0 then
			-- Preserve any Size/Name override applied just above rather than
			-- re-cloning from MapData, which would discard it.
			local merged = {}
			for key, value in pairs(config) do
				merged[key] = value
			end
			merged.KeepSpawnZones = customMapData.KeepSpawnZones
			config = merged
			SpawnManager.setMapConfig(config)
			WorldDebug:info("Merged painted KeepSpawnZones into mapConfig")
		end

		if customMapData and not resourcePatchesSpawned then
			local patches = customMapData.ResourcePatches or {}
			if #patches > 0 then
				ResourceNodeManager.spawnNodesFromPatches(patches)
				resourcePatchesSpawned = true
				WorldDebug:info(`Spawned resource nodes from {#patches} painted patches`)
			else
				spawnFallbackResources(config)
			end
		end
	end

	-- Pathfinding is configured only after a custom map has applied its real
	-- dimensions and keep zones. Reinitializing this per joining player would
	-- discard shared navigation state mid-match.
	SpawnManager.setMapConfig(config)
	PathfindingIntegration.initialize(config.Size)

	mapConfig = config
	initialized = true
	WorldDebug:info(`Shared world initialized for {config.Name}`)

	return config
end

--- Tear down match-world state. Call only once the last player has left, from
--- the same place that calls MapManager.unlockMatchMap.
function MatchWorld.reset()
	customMapData = nil
	resourcePatchesSpawned = false
	mapConfig = nil
	initialized = false
	WorldDebug:info("Match world reset")
end

return MatchWorld
