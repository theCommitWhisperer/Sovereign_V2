--!strict
-- MapManager: Handles map selection and active map state

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MapData = require(ReplicatedStorage.Shared.GameData.MapData)
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)

local MapManagerDebug = DebugManager.createChannel("MapManager", false)

local MapManager = {}

-- Current active map (can be changed between games)
local currentMap: string = MapData.DefaultMap

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
	local mapConfig = MapData.getMap(mapName)
	if not mapConfig then
		MapManagerDebug:warn(`Attempted to set invalid map: {mapName}`)
		return false
	end

	currentMap = mapName
	MapManagerDebug:info(`Map set to: {mapName}`)
	return true
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
