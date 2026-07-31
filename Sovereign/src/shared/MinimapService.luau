--!strict
-- MinimapService: the client's decoded view of the server's blip stream.
--
-- Lives in Shared rather than under StarterPlayerScripts.Client because both
-- script trees need it and neither can require the other by a relative path (see
-- the note in HUDStore around the SelectionManager require). It is still
-- client-only at runtime: start() no-ops on the server.
--
-- Deliberately not a React store. The minimap updates 4x/second with up to a few
-- hundred blips; pushing that through setState would re-run reconciliation on
-- every dot, which is what the old minimap did and why it cost what it did.
-- Instead this holds a decoded buffer that the minimap component reads directly
-- and paints onto a pool of reused Frames.
--
-- Consumers that only need "can I see this thing" (FogOfWarClient,
-- HealthBarManager) can subscribe to onSnapshot rather than running their own
-- CheckVisibility:InvokeServer loop.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MinimapBlips = require(script.Parent.MinimapBlips)

local MinimapService = {}

export type MapConfig = {
	Name: string?,
	Size: number,
	PreviewImage: string?,
	KeepSpawnZones: { { Zone: number, X: number, Y: number, Z: number, Radius: number } }?,
}

-- Fallback only. The real value arrives with GameStarted; if it somehow does
-- not, 1000 at least matches the old hardcoded behaviour rather than dividing by
-- nil.
local DEFAULT_MAP_SIZE = 1000

local currentBuffer: buffer? = nil
local currentCount = 0
local mapConfig: MapConfig = { Size = DEFAULT_MAP_SIZE }
local listeners: { (buffer, number) -> () } = {}
local started = false
local connection: RBXScriptConnection? = nil

--- Latest snapshot. Returns nil when nothing has arrived yet. The buffer is
--- owned by this module and replaced wholesale on the next snapshot -- read it,
--- do not retain it.
function MinimapService.getBlips(): (buffer?, number)
	return currentBuffer, currentCount
end

function MinimapService.getMapConfig(): MapConfig
	return mapConfig
end

function MinimapService.getMapSize(): number
	return mapConfig.Size or DEFAULT_MAP_SIZE
end

--- Called by HUDStore when GameStarted lands, so the minimap knows the world
--- extent it is projecting into.
function MinimapService.setMapConfig(config: any?)
	if typeof(config) ~= "table" then
		return
	end
	local size = tonumber(config.Size)
	mapConfig = {
		Name = config.Name,
		Size = if size and size > 0 then size else DEFAULT_MAP_SIZE,
		PreviewImage = config.PreviewImage,
		KeepSpawnZones = config.KeepSpawnZones,
	}
end

--- Subscribe to snapshots. Returns an unsubscribe function.
function MinimapService.onSnapshot(callback: (buffer, number) -> ()): () -> ()
	table.insert(listeners, callback)
	return function()
		local index = table.find(listeners, callback)
		if index then
			table.remove(listeners, index)
		end
	end
end

--- World position -> 0..1 minimap space. Shared by the renderer and by
--- click-to-move so the two can never disagree about the projection.
function MinimapService.worldToMinimap(x: number, z: number): (number, number)
	local size = MinimapService.getMapSize()
	return math.clamp((x + size / 2) / size, 0, 1), math.clamp((z + size / 2) / size, 0, 1)
end

--- 0..1 minimap space -> world position.
function MinimapService.minimapToWorld(u: number, v: number): (number, number)
	local size = MinimapService.getMapSize()
	return (u * size) - (size / 2), (v * size) - (size / 2)
end

function MinimapService.start()
	if started or not RunService:IsClient() then
		return
	end
	started = true

	task.spawn(function()
		local remotes = ReplicatedStorage:WaitForChild("RemoteEvents")
		local remote = remotes:WaitForChild("BlipSnapshot") :: RemoteEvent

		connection = remote.OnClientEvent:Connect(function(packet: buffer)
			if typeof(packet) ~= "buffer" then
				return
			end

			currentBuffer = packet
			currentCount = MinimapBlips.count(packet)

			for _, listener in listeners do
				task.spawn(listener, packet, currentCount)
			end
		end)
	end)
end

function MinimapService.stop()
	if connection then
		connection:Disconnect()
		connection = nil
	end
	started = false
	currentBuffer = nil
	currentCount = 0
end

return MinimapService
