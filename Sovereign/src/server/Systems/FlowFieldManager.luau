--!strict
-- FlowFieldManager: Caches shared flow fields for group movement.
--
-- When many units are ordered to the same place (a formation move, an AI army
-- march, a worker rally), they follow ONE integration field instead of each
-- running its own A*. Fields are keyed by rounded goal cell, reused across
-- units, and invalidated when the pathfinding grid changes (buildings placed
-- or removed).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Pathfinding = require(ReplicatedStorage.Shared.Pathfinding)
local FlowField = require(ReplicatedStorage.Shared.Pathfinding.FlowField)
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)
local PathfindingIntegration = require(script.Parent.PathfindingIntegration)

local FlowDebug = DebugManager.createChannel("FlowField", false)

local FlowFieldManager = {}

-- Snap goals to a coarse grid so nearby group orders share one field
local GOAL_QUANTIZE = 8 -- studs
local FIELD_TTL = 20 -- seconds a field lives without use
local MAX_FIELDS = 24

type Entry = {
	id: number,
	field: FlowField.FlowField,
	goal: Vector3,
	gridVersion: number,
	lastUsed: number,
}

local fieldsById: { [number]: Entry } = {}
local fieldsByKey: { [string]: Entry } = {}
local nextId = 1

local function goalKey(goalWorld: Vector3): string
	local qx = math.round(goalWorld.X / GOAL_QUANTIZE)
	local qz = math.round(goalWorld.Z / GOAL_QUANTIZE)
	return `{qx}_{qz}`
end

local function evictIfNeeded()
	local count = 0
	for _ in fieldsById do
		count += 1
	end
	if count <= MAX_FIELDS then
		return
	end
	-- Drop the least-recently-used field
	local oldestId: number? = nil
	local oldestTime = math.huge
	for id, entry in fieldsById do
		if entry.lastUsed < oldestTime then
			oldestTime = entry.lastUsed
			oldestId = id
		end
	end
	if oldestId then
		local entry = fieldsById[oldestId]
		if entry then
			fieldsByKey[goalKey(entry.goal)] = nil
		end
		fieldsById[oldestId] = nil
	end
end

-- Get (or build) a shared flow field toward `goalWorld`. Returns a field ID to
-- store on units, or nil if pathfinding isn't active or the goal is unreachable
-- (caller falls back to per-unit A*).
function FlowFieldManager.acquire(goalWorld: Vector3): number?
	if not PathfindingIntegration.isInitialized() then
		return nil
	end
	local grid = PathfindingIntegration.getGrid()
	if not grid then
		return nil
	end

	local version = PathfindingIntegration.getGridVersion()
	local key = goalKey(goalWorld)
	local existing = fieldsByKey[key]
	if existing and existing.gridVersion == version then
		existing.lastUsed = os.clock()
		return existing.id
	end

	local field = FlowField.compute(grid, goalWorld.X, goalWorld.Z)
	if not field then
		return nil
	end

	local id = nextId
	nextId += 1
	local entry: Entry = {
		id = id,
		field = field,
		goal = goalWorld,
		gridVersion = version,
		lastUsed = os.clock(),
	}
	fieldsById[id] = entry
	fieldsByKey[key] = entry
	evictIfNeeded()

	FlowDebug:info("Built flow field", { id = id, goal = tostring(goalWorld) })
	return id
end

-- Desired horizontal direction for a unit following field `id`. Returns
-- Vector3.zero if the field is gone/stale (caller should stop or re-path).
function FlowFieldManager.sample(id: number, worldPos: Vector3): Vector3
	local entry = fieldsById[id]
	if not entry then
		return Vector3.zero
	end
	-- Stale grid (a building changed): drop it so callers re-path
	if entry.gridVersion ~= PathfindingIntegration.getGridVersion() then
		fieldsByKey[goalKey(entry.goal)] = nil
		fieldsById[id] = nil
		return Vector3.zero
	end
	entry.lastUsed = os.clock()
	return FlowField.sampleDirection(entry.field, worldPos.X, worldPos.Z)
end

function FlowFieldManager.getGoal(id: number): Vector3?
	local entry = fieldsById[id]
	return entry and entry.goal or nil
end

function FlowFieldManager.isValid(id: number): boolean
	local entry = fieldsById[id]
	return entry ~= nil and entry.gridVersion == PathfindingIntegration.getGridVersion()
end

-- Periodic cleanup of unused fields
function FlowFieldManager.init()
	task.spawn(function()
		while true do
			task.wait(5)
			local now = os.clock()
			for id, entry in fieldsById do
				if now - entry.lastUsed > FIELD_TTL then
					fieldsByKey[goalKey(entry.goal)] = nil
					fieldsById[id] = nil
				end
			end
		end
	end)
end

return FlowFieldManager
