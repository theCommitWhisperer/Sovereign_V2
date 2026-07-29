--!strict
-- BuildingIndex: a per-owner, incrementally-maintained index of buildings.
--
-- WHY THIS EXISTS
-- ---------------
-- WorkerManager used to answer "which storage building can take this
-- resource?" and "which storage building already has it?" by scanning
-- Workspace.Buildings:GetChildren() FRESH, per hauler, per frame, while the
-- hauler was walking. With N haulers and M buildings that's an O(N*M) cost
-- paid every Heartbeat for no reason -- the set of buildings barely changes
-- frame to frame.
--
-- This module keeps a live index instead: it listens to the Buildings folder
-- once, and updates incrementally on ChildAdded/ChildRemoved. Lookups become
-- O(buildings of that owner that can store that resource), typically tiny.
--
-- This module requires BuildingManager BEFORE touching Workspace.Buildings,
-- so its own top-level scan is guaranteed to run after BuildingManager's
-- module body has already created the folder (Luau's require() fully
-- executes a module before returning it to the caller) -- no WaitForChild,
-- no race, no risk of two competing folder-creations.

local Workspace = game:GetService("Workspace")

local BuildingManager = require(script.Parent.Parent.Managers.BuildingManager)
local BuildingSpec = require(game:GetService("ReplicatedStorage").Shared.GameData.BuildingSpec)

local BuildingIndex = {}

type BuildingSet = { [Instance]: true }

-- ownerId -> every building that owner has (live instances only, checked at
-- read time since GetChildren() removal timing and our ChildRemoved handler
-- are both async relative to combat destroying a model this same frame).
local byOwner: { [number]: BuildingSet } = {}

-- ownerId -> resourceType -> every building of that owner that CAN store
-- that resource (i.e. resourceType is a key in BuildingSpec.storage).
local storageCapable: { [number]: { [string]: BuildingSet } } = {}

local function ownerSet(ownerId: number): BuildingSet
	local set = byOwner[ownerId]
	if not set then
		set = {}
		byOwner[ownerId] = set
	end
	return set
end

local function add(building: Instance)
	if not building:IsA("Model") then
		return
	end
	local ownerId = building:GetAttribute("OwnerId")
	if typeof(ownerId) ~= "number" then
		return
	end

	ownerSet(ownerId)[building] = true

	local buildingType = building:GetAttribute("BuildingType")
	local spec = buildingType and BuildingSpec.get(buildingType :: string)
	if spec and next(spec.storage) then
		local byResource = storageCapable[ownerId]
		if not byResource then
			byResource = {}
			storageCapable[ownerId] = byResource
		end
		for resource in spec.storage do
			local set = byResource[resource]
			if not set then
				set = {}
				byResource[resource] = set
			end
			set[building] = true
		end
	end
end

local function remove(building: Instance)
	local ownerId = building:GetAttribute("OwnerId")
	if typeof(ownerId) ~= "number" then
		return
	end
	local set = byOwner[ownerId]
	if set then
		set[building] = nil
	end
	local byResource = storageCapable[ownerId]
	if byResource then
		for _, resourceSet in byResource do
			resourceSet[building] = nil
		end
	end
end

-- Every existing building at module load, then keep it live.
local BuildingsFolder = Workspace:FindFirstChild("Buildings")
if BuildingsFolder then
	for _, existing in BuildingsFolder:GetChildren() do
		add(existing)
	end
	BuildingsFolder.ChildAdded:Connect(add)
	BuildingsFolder.ChildRemoved:Connect(remove)
end

-- Exposed for WorkerService, which owns the per-building Destroying
-- subscription (worker release) and may see a building come/go before this
-- module's own ChildAdded/ChildRemoved fires; calling these directly keeps
-- the index in step rather than waiting on signal ordering.
function BuildingIndex.register(building: Instance)
	add(building)
end

function BuildingIndex.unregister(building: Instance)
	remove(building)
end

function BuildingIndex.getOwnerBuildings(ownerId: number): { Instance }
	local out: { Instance } = {}
	local set = byOwner[ownerId]
	if set then
		for building in set do
			if building.Parent then
				table.insert(out, building)
			end
		end
	end
	return out
end

function BuildingIndex.getAllOwnerIds(): { number }
	local out: { number } = {}
	for ownerId in byOwner do
		table.insert(out, ownerId)
	end
	return out
end

-- The best storage building of `ownerId` that can receive `resourceType`,
-- i.e. has the most free space, excluding `exclude` (so a producer's own
-- output never gets hauled back into itself).
function BuildingIndex.findStorageFor(ownerId: number, resourceType: string, exclude: Instance?): Instance?
	local byResource = storageCapable[ownerId]
	local candidates = byResource and byResource[resourceType]
	if not candidates then
		return nil
	end

	local best: Instance? = nil
	local bestSpace = 0
	for building in candidates do
		if building.Parent and building ~= exclude then
			local buildingType = building:GetAttribute("BuildingType")
			local spec = buildingType and BuildingSpec.get(buildingType :: string)
			local capacity = (spec and spec.storage[resourceType]) or 0
			local current = BuildingManager.getStorageAmount(building, resourceType)
			local space = capacity - current
			if space > bestSpace then
				best = building
				bestSpace = space
			end
		end
	end
	return best
end

-- A storage building of `ownerId` already holding at least `minAmount` of
-- `resourceType`. Only dedicated storage / the Keep count -- never another
-- producer's own working stock (mirrors the old requires_worker exclusion).
function BuildingIndex.findStorageWithResource(ownerId: number, resourceType: string, minAmount: number): Instance?
	local byResource = storageCapable[ownerId]
	local candidates = byResource and byResource[resourceType]
	if not candidates then
		return nil
	end

	for building in candidates do
		if building.Parent then
			local buildingType = building:GetAttribute("BuildingType")
			local spec = buildingType and BuildingSpec.get(buildingType :: string)
			local employsWorkers = spec and spec.work and spec.work.slots > 0
			if spec and not employsWorkers then
				if BuildingManager.getStorageAmount(building, resourceType) >= minAmount then
					return building
				end
			end
		end
	end
	return nil
end

return BuildingIndex
