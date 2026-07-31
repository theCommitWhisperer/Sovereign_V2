--!strict
-- FogOfWarManager: decides what each player can see, and does it fast enough to
-- run every tick rather than only when an admin flips fog on.
--
-- The old implementation answered every visibility question by looping over
-- every unit and every building the player owned and distance-testing each one
-- -- O(N) per query, with no index. That was survivable only because fog is off
-- by default, which meant isPositionVisible() returned true on its first line
-- and never actually ran. Turning fog on in production would have been
-- quadratic.
--
-- Now vision sources are indexed into a coarse spatial hash once per tick and
-- queried in O(1). The index is what BlipReplicator consumes to build minimap
-- snapshots, so it has to be cheap whether or not fog is enabled.
--
-- Note the asymmetry: fog data is keyed by Player because only real players have
-- a client to hide things from. AI kingdoms own units and buildings but never
-- ask what they can see.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DebugManager = require(ReplicatedStorage.Shared.DebugManager)
local FogDebug = DebugManager.createChannel("FogOfWar", false)

local FogOfWarManager = {}

-- Vision radius in studs, by unit/building type.
local VISION_RANGES = {
	Unit = 100,
	Building = 150,
	Keep = 300,
}

-- Spatial hash cell size. A 3x3 cell scan around a query point is guaranteed to
-- find any source within CELL studs of it, so every source with a range at or
-- below this goes in the grid and is answered by a 9-cell lookup. Sources with a
-- longer reach (Keeps, at 300) fall back to a linear list -- there are at most a
-- handful per player, so that is cheaper than inflating the grid.
local VISION_CELL = 160

-- How stale a cached vision index may get before it is rebuilt. Matches the
-- BlipReplicator tick so the two stay in step.
local INDEX_TTL = 0.25

export type VisionIndex = {
	-- cellKey -> flat {x1, z1, rangeSq1, x2, z2, rangeSq2, ...}
	grid: { [number]: { number } },
	-- flat {x, z, rangeSq, ...} for sources with range > VISION_CELL
	longRange: { number },
	builtAt: number,
}

type FogOfWarData = {
	enabled: boolean,
	index: VisionIndex?,
}

local playerFogData: { [Player]: FogOfWarData } = {}
local updatesStarted = false

--- Tell a client whether fog applies to it. Without this the client had no way
--- to know, so FogOfWarClient ran its full hide/reveal sweep (and darkened
--- Lighting) even though fog is off by default and every answer was "visible".
local function pushFogState(player: Player, enabled: boolean)
	local remotes = ReplicatedStorage:FindFirstChild("RemoteEvents")
	local gameEvent = remotes and remotes:FindFirstChild("GameEvent")
	if gameEvent and gameEvent:IsA("RemoteEvent") then
		gameEvent:FireClient(player, "FogState", { enabled = enabled })
	end
end

local function cellKey(cx: number, cz: number): number
	-- Offset keeps the key positive for negative world coordinates. Supports
	-- |cell| < 512, i.e. +/-81920 studs at VISION_CELL = 160.
	return (cx + 512) * 1024 + (cz + 512)
end

-- ---------------------------------------------------------------------------
-- LIFECYCLE
-- ---------------------------------------------------------------------------

function FogOfWarManager.init(player: Player)
	playerFogData[player] = {
		enabled = false, -- fog is OFF by default; TestCommandManager toggles it
		index = nil,
	}
	FogDebug:info(`Initialized fog of war for {player.Name}`)
end

function FogOfWarManager.cleanup(player: Player)
	playerFogData[player] = nil
	FogDebug:info(`Cleaned up fog of war for {player.Name}`)
end

function FogOfWarManager.toggle(player: Player, enabled: boolean)
	local data = playerFogData[player]
	if not data then
		return
	end

	data.enabled = enabled
	data.index = nil -- force a rebuild on the next query
	pushFogState(player, enabled)
	FogDebug:info(`Fog of war {enabled and "enabled" or "disabled"} for {player.Name}`)
end

function FogOfWarManager.isEnabled(player: Player): boolean
	local data = playerFogData[player]
	return data ~= nil and data.enabled
end

-- ---------------------------------------------------------------------------
-- VISION INDEX
-- ---------------------------------------------------------------------------

local function addSource(index: VisionIndex, position: Vector3, range: number)
	local rangeSq = range * range

	if range > VISION_CELL then
		local longRange = index.longRange
		longRange[#longRange + 1] = position.X
		longRange[#longRange + 1] = position.Z
		longRange[#longRange + 1] = rangeSq
		return
	end

	local key = cellKey(math.floor(position.X / VISION_CELL), math.floor(position.Z / VISION_CELL))
	local bucket = index.grid[key]
	if not bucket then
		bucket = {}
		index.grid[key] = bucket
	end
	bucket[#bucket + 1] = position.X
	bucket[#bucket + 1] = position.Z
	bucket[#bucket + 1] = rangeSq
end

--- Rebuild the spatial index of everything granting `userId` vision.
--- Public because BlipReplicator drives the rebuild on its own tick rather than
--- letting each query rebuild lazily.
function FogOfWarManager.buildVisionIndex(userId: number): VisionIndex
	local index: VisionIndex = {
		grid = {},
		longRange = {},
		builtAt = os.clock(),
	}

	local unitsFolder = workspace:FindFirstChild("Units")
	if unitsFolder then
		for _, unit in unitsFolder:GetChildren() do
			if unit:IsA("Model") and unit.PrimaryPart and unit:GetAttribute("OwnerId") == userId then
				local unitType = unit:GetAttribute("UnitType")
				local range = (typeof(unitType) == "string" and VISION_RANGES[unitType]) or VISION_RANGES.Unit
				addSource(index, unit.PrimaryPart.Position, range)
			end
		end
	end

	local buildingsFolder = workspace:FindFirstChild("Buildings")
	if buildingsFolder then
		for _, building in buildingsFolder:GetChildren() do
			if building:IsA("Model") and building.PrimaryPart and building:GetAttribute("OwnerId") == userId then
				local buildingType = building:GetAttribute("BuildingType")
				local range = (typeof(buildingType) == "string" and VISION_RANGES[buildingType])
					or VISION_RANGES.Building
				addSource(index, building.PrimaryPart.Position, range)
			end
		end
	end

	return index
end

local function queryIndex(index: VisionIndex, x: number, z: number): boolean
	local cx = math.floor(x / VISION_CELL)
	local cz = math.floor(z / VISION_CELL)
	local grid = index.grid

	for dx = -1, 1 do
		for dz = -1, 1 do
			local bucket = grid[cellKey(cx + dx, cz + dz)]
			if bucket then
				for i = 1, #bucket, 3 do
					local ox, oz = x - bucket[i], z - bucket[i + 1]
					if ox * ox + oz * oz <= bucket[i + 2] then
						return true
					end
				end
			end
		end
	end

	local longRange = index.longRange
	for i = 1, #longRange, 3 do
		local ox, oz = x - longRange[i], z - longRange[i + 1]
		if ox * ox + oz * oz <= longRange[i + 2] then
			return true
		end
	end

	return false
end

--- Get a fresh-enough vision index for a player, rebuilding if stale.
--- Returns nil when fog is disabled for that player (everything is visible, so
--- callers can skip the query entirely).
function FogOfWarManager.getVisionIndex(player: Player): VisionIndex?
	local data = playerFogData[player]
	if not data or not data.enabled then
		return nil
	end

	local index = data.index
	if not index or (os.clock() - index.builtAt) > INDEX_TTL then
		index = FogOfWarManager.buildVisionIndex(player.UserId)
		data.index = index
	end

	return index
end

-- ---------------------------------------------------------------------------
-- QUERIES
-- ---------------------------------------------------------------------------

--- Is a world position visible to a player? O(1) against the cached index.
function FogOfWarManager.isPositionVisible(player: Player, position: Vector3): boolean
	local index = FogOfWarManager.getVisionIndex(player)
	if not index then
		return true -- fog disabled: everything is visible
	end
	return queryIndex(index, position.X, position.Z)
end

--- Variant for callers that already hold an index (BlipReplicator's inner loop),
--- avoiding a per-blip staleness check.
function FogOfWarManager.isPositionVisibleWithIndex(index: VisionIndex?, x: number, z: number): boolean
	if not index then
		return true
	end
	return queryIndex(index, x, z)
end

function FogOfWarManager.isUnitVisible(player: Player, unit: Model): boolean
	if not unit or not unit.PrimaryPart then
		return false
	end

	if unit:GetAttribute("OwnerId") == player.UserId then
		return true -- always see your own
	end

	return FogOfWarManager.isPositionVisible(player, unit.PrimaryPart.Position)
end

function FogOfWarManager.isBuildingVisible(player: Player, building: Model): boolean
	if not building or not building.PrimaryPart then
		return false
	end

	if building:GetAttribute("OwnerId") == player.UserId then
		return true
	end

	return FogOfWarManager.isPositionVisible(player, building.PrimaryPart.Position)
end

-- ---------------------------------------------------------------------------
-- REFRESH LOOP
-- ---------------------------------------------------------------------------

--- Keeps every enabled player's index warm so queries never pay a rebuild
--- inline. Idempotent: GameManager calls this both at boot and again on first
--- StartGame, and previously that spawned two competing loops.
function FogOfWarManager.startUpdates()
	if updatesStarted then
		return
	end
	updatesStarted = true

	task.spawn(function()
		while true do
			task.wait(INDEX_TTL)
			for player, data in playerFogData do
				if data.enabled and player.Parent ~= nil then
					data.index = FogOfWarManager.buildVisionIndex(player.UserId)
				end
			end
		end
	end)

	FogDebug:info("Started fog of war vision index updates")
end

--- Drop every cached index. Call between matches.
function FogOfWarManager.resetMatch()
	for _, data in playerFogData do
		data.index = nil
	end
end

Players.PlayerRemoving:Connect(function(player)
	playerFogData[player] = nil
end)

FogDebug:info("FogOfWarManager loaded")

return FogOfWarManager
