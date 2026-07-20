--!strict
-- MapManager: Handles map selection and active map state

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MapData = require(ReplicatedStorage.Shared.GameData.MapData)
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)

local MapManagerDebug = DebugManager.createChannel("MapManager", false)

local MapManager = {}

-- A Roblox server has one shared Workspace. Once a match starts, every player
-- must therefore use the same map until the match has fully ended.
local currentMap: string = MapData.DefaultMap
local matchMapLocked = false

-- Get the currently active map configuration
function MapManager.getCurrentMap(): any
	local mapConfig = MapData.getMap(currentMap)
	if not mapConfig then
		MapManagerDebug:warn(`Invalid map "{currentMap}", falling back to default`)
		currentMap = MapData.DefaultMap
		mapConfig = MapData.getMap(currentMap)
	end
	return mapConfig
end

-- Set the active map (call before starting a game)
function MapManager.setMap(mapName: string): boolean
	if matchMapLocked and mapName ~= currentMap then
		MapManagerDebug:warn(`Attempted to change locked match map from "{currentMap}" to "{mapName}"`)
		return false
	end

	local mapConfig = MapData.getMap(mapName)
	if not mapConfig then
		MapManagerDebug:warn(`Attempted to set invalid map: {mapName}`)
		return false
	end

	currentMap = mapName
	MapManagerDebug:info(`Map set to: {mapName}`)
	return true
end

-- Select the one map that this server will use for the active match.
-- Subsequent calls are only accepted when they request the already locked map.
function MapManager.lockMatchMap(mapName: string): boolean
	if matchMapLocked then
		return mapName == currentMap
	end

	if not MapManager.setMap(mapName) then
		return false
	end

	matchMapLocked = true
	MapManagerDebug:info(`Match map locked: {currentMap}`)
	return true
end

function MapManager.isMatchMapLocked(): boolean
	return matchMapLocked
end

-- Call only after the final player has left the match and all shared
-- match-owned world objects have been cleaned up.
function MapManager.unlockMatchMap()
	matchMapLocked = false
	currentMap = MapData.DefaultMap
	MapManagerDebug:info(`Match map unlocked; restored default: {currentMap}`)
end

-- Get current map name
function MapManager.getCurrentMapName(): string
	return currentMap
end

-- Get all available maps
function MapManager.getAvailableMaps(): { string }
	return MapData.getMapList()
end

-- Get map configuration by name (without setting it as current)
function MapManager.getMapConfig(mapName: string): any?
	return MapData.getMap(mapName)
end

MapManagerDebug:info(`MapManager loaded - Default map: {currentMap}`)

return MapManager
