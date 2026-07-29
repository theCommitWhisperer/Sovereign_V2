--!strict
-- BuildingSpec: the canonical, normalized view of a building definition.
--
-- WHY THIS EXISTS
-- ---------------
-- BuildingsData accumulated three pairs of overlapping fields describing the
-- same thing:
--
--     produces_resource + production_rate    vs   production_time + production_output
--     worker_job_type                        vs   worker_type      (never set by anything)
--     requires_worker                        vs   worker_slots
--
-- ...and then a load-time loop OVERWROTE production_output / production_time /
-- worker_slots / production_rate for every producing building from a central
-- RESOURCE_TIERS table. So the numbers authored per building were dead on
-- arrival: you could edit `production_rate = 1.5` on the Bakery and nothing
-- would change, because the tier loop clobbered it before any system read it.
--
-- Rather than rewrite 52 building entries and every consumer in one commit,
-- every system now asks BuildingSpec instead of touching BuildingsData fields
-- directly. This gives one place to:
--
--   * resolve old field names to one shape
--   * apply tier values as DEFAULTS that a building may override (the correct
--     precedence -- the old loop had it backwards)
--   * attach the worker role/behaviour from WorkerRoles
--
-- Buildings can then be migrated to the new `work = {...}` block a few at a
-- time, and the day the last one moves the legacy branches here get deleted.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BuildingsData = require(ReplicatedStorage.Shared.GameData.BuildingsData)
local WorkerRoles = require(ReplicatedStorage.Shared.GameData.WorkerRoles)

local BuildingSpec = {}

export type WorkSpec = {
	role: string, -- key into WorkerRoles
	behaviour: WorkerRoles.Behaviour, -- Gatherer | Producer | Hauler | Server
	slots: number, -- how many workers this building employs
	cycle: number, -- seconds per production cycle
	inputs: { [string]: number }, -- consumed per cycle
	outputs: { [string]: number }, -- produced per cycle
	gathersFromNodes: boolean, -- Gatherer: walks to world ResourceNodes
	-- WHICH resource a gatherer harvests from world nodes. Must be explicit:
	-- the engine previously picked it with next(outputs), and Lua gives no
	-- iteration-order guarantee, so a two-output building's behaviour came down
	-- to hash order. A building that produced Food and Grain would, depending on
	-- the run, either gather Food from nodes and never make Grain, or find no
	-- Grain nodes and fall back to producing both -- and the whole
	-- Grain -> Flour -> Bread chain lived or died on that coin flip.
	gathers: string?,
}

export type Spec = {
	name: string,
	modelAssetName: string?,
	iconAssetId: string?,
	category: string, -- subtype, used for UI grouping
	description: string,
	cost: { [string]: number },
	buildTime: number,
	size: Vector3?,
	storage: { [string]: number },
	housing: number,
	upkeep: { [string]: number },
	popularityImpact: number,
	gloryRequired: number,
	work: WorkSpec?, -- nil = building employs nobody
	trains: { string }?, -- unit types this building can train
	defenseValue: number,
	raw: any, -- escape hatch to the original table
}

-- Tier defaults, keyed by the resource produced. These are now DEFAULTS: a
-- building that states its own cycle/slots/output wins over the tier.
local RESOURCE_TIERS: { [string]: { output: number, interval: number, slots: number } } = {
	-- Raw -- abundant, drives the early game
	Wood = { output = 2, interval = 4, slots = 3 },
	Stone = { output = 2, interval = 5, slots = 3 },
	Food = { output = 2, interval = 4, slots = 3 },
	Grain = { output = 3, interval = 4, slots = 3 },
	Hide = { output = 1, interval = 6, slots = 2 },
	Fish = { output = 2, interval = 5, slots = 2 },
	Iron_Ore = { output = 1, interval = 5, slots = 3 },
	Coal = { output = 1, interval = 5, slots = 3 },
	-- Refined -- mid game, consumes a raw input
	Flour = { output = 2, interval = 5, slots = 2 },
	Leather = { output = 1, interval = 6, slots = 2 },
	Vellum = { output = 1, interval = 7, slots = 1 },
	Iron_Bars = { output = 1, interval = 5, slots = 2 },
	-- Finished -- slow, valuable, the money makers
	Bread = { output = 2, interval = 5, slots = 2 },
	Ale = { output = 2, interval = 6, slots = 2 },
	Furniture = { output = 1, interval = 6, slots = 2 },
	Weapons = { output = 1, interval = 8, slots = 2 },
	Siege_Equipment = { output = 1, interval = 12, slots = 1 },
	Manuscripts = { output = 1, interval = 8, slots = 1 },
}

local DEFAULT_TIER = { output = 1, interval = 6, slots = 2 }

-- Buildings whose workers physically walk out to world ResourceNodes.
local GATHERER_BUILDINGS: { [string]: boolean } = {
	["Lumberjack"] = true,
	["Stone Quarry"] = true,
	["Iron Mine"] = true,
	["Coal Mine"] = true,
	["Potato Farm"] = true,
	["Sheep Farm"] = true,
	["Cow Farm"] = true,
	["Fishermans Hut"] = true,
}

-- Legacy worker_job_type values -> WorkerRoles keys, where they differ.
local ROLE_ALIASES: { [string]: string } = {
	Smelter = "Smelter",
	Blacksmith = "Blacksmith",
	Woodcutter = "Woodcutter",
	Stonemason = "Stonemason",
	Miner = "Miner",
	Farmer = "Farmer",
	Fisherman = "Fisherman",
	Miller = "Miller",
	Baker = "Baker",
	Brewer = "Brewer",
	Tanner = "Tanner",
	Carpenter = "Carpenter",
	Innkeeper = "Innkeeper",
	Monk = "Monk",
	Priest = "Priest",
	Administrator = "Administrator",
	Scribe = "Scribe",
	Merchant = "Merchant",
	Trader = "Trader",
	Archer = "Archer",
}

local cache: { [string]: Spec } = {}

-- Resolves which resource a gatherer harvests. Explicit `gathers` wins; failing
-- that, a single output is unambiguous. Two outputs with no explicit choice is
-- a config error, so say so rather than silently coin-flipping.
local function resolveGathers(name: string, work: any, outputs: { [string]: number }): string?
	if work and work.gathers then
		return work.gathers
	end
	local only: string? = nil
	local count = 0
	for resource in outputs do
		only = resource
		count += 1
	end
	if count == 1 then
		return only
	end
	if count > 1 then
		warn(
			("[BuildingSpec] %s gathers from nodes but has %d outputs and no explicit `gathers` field; node harvesting disabled")
				:format(name, count)
		)
	end
	return nil
end

local function normalizeWork(name: string, data: any): WorkSpec?
	-- New shape wins if present.
	local work = data.work
	if type(work) == "table" then
		local role = work.role or "Peasant"
		local outputs = work.outputs or {}
		-- `gathersFromNodes` must be explicitly false-able, so test for nil
		-- rather than falling back with `or` (which would turn false into the
		-- role default and send every farm walking off to look for nodes).
		local gathersFromNodes = work.gathersFromNodes
		if gathersFromNodes == nil then
			gathersFromNodes = WorkerRoles.getBehaviour(role) == "Gatherer"
		end
		return {
			role = role,
			behaviour = WorkerRoles.getBehaviour(role),
			slots = work.slots or 1,
			cycle = work.cycle or DEFAULT_TIER.interval,
			inputs = work.inputs or {},
			outputs = outputs,
			gathersFromNodes = gathersFromNodes,
			gathers = gathersFromNodes and resolveGathers(name, work, outputs) or nil,
		}
	end

	-- Legacy shape.
	if not data.requires_worker then
		return nil
	end

	local produces = data.produces_resource
	local tier = (produces and RESOURCE_TIERS[produces]) or DEFAULT_TIER

	local rawRole = data.worker_job_type or data.worker_type or "Peasant"
	local role = ROLE_ALIASES[rawRole] or rawRole

	local outputs: { [string]: number } = {}
	if produces then
		-- production_output was clobbered by the old tier loop, so prefer the
		-- tier value but let an explicit new-style override through.
		outputs[produces] = data.production_output or tier.output
	end

	local inputs: { [string]: number } = {}
	if data.consumes_resource then
		inputs[data.consumes_resource] = data.consumption_rate or 1
	end

	local behaviour = WorkerRoles.getBehaviour(role)
	-- A building that produces nothing and consumes nothing is a Server
	-- (Market, Church, Town Hall...) regardless of what its role implies.
	if not produces and not data.consumes_resource then
		behaviour = "Server"
	end

	local gathersFromNodes = data.worker_gathers_from_nodes or GATHERER_BUILDINGS[name] or false

	return {
		role = role,
		behaviour = behaviour,
		slots = data.worker_slots or tier.slots,
		cycle = data.production_time or tier.interval,
		inputs = inputs,
		outputs = outputs,
		gathersFromNodes = gathersFromNodes,
		gathers = gathersFromNodes and produces or nil,
	}
end

local function build(name: string): Spec?
	local data = (BuildingsData :: any)[name]
	if type(data) ~= "table" or not data.type then
		return nil
	end

	local construction = data.construction or {}

	return {
		name = name,
		modelAssetName = data.model_asset_name,
		iconAssetId = data.icon_asset_id,
		category = data.subtype or "Misc",
		description = data.description or "",
		cost = data.cost or {},
		buildTime = construction.build_time_seconds or 0,
		size = data.size,
		storage = data.storage_capacity or {},
		housing = data.housing_capacity or 0,
		upkeep = data.maintenance_cost or {},
		popularityImpact = data.popularity_impact or 0,
		gloryRequired = data.glory_required or 0,
		work = normalizeWork(name, data),
		trains = data.can_train_units,
		defenseValue = data.defense_value or 0,
		raw = data,
	}
end

-- Returns the canonical spec for a building, or nil if the name is unknown.
function BuildingSpec.get(name: string): Spec?
	local hit = cache[name]
	if hit then
		return hit
	end
	local spec = build(name)
	if spec then
		cache[name] = spec
	end
	return spec
end

-- Convenience: the work block, or nil if this building employs nobody.
function BuildingSpec.getWork(name: string): WorkSpec?
	local spec = BuildingSpec.get(name)
	return spec and spec.work
end

function BuildingSpec.employsWorkers(name: string): boolean
	local work = BuildingSpec.getWork(name)
	return work ~= nil and work.slots > 0
end

function BuildingSpec.getWorkerSlots(name: string): number
	local work = BuildingSpec.getWork(name)
	return work and work.slots or 0
end

function BuildingSpec.getBehaviour(name: string): WorkerRoles.Behaviour?
	local work = BuildingSpec.getWork(name)
	return work and work.behaviour
end

-- Every building name, sorted -- for UI menus and validation passes.
function BuildingSpec.getAllNames(): { string }
	local names: { string } = {}
	for key, value in BuildingsData do
		if type(value) == "table" and value.type then
			table.insert(names, key)
		end
	end
	table.sort(names)
	return names
end

-- All specs whose work.outputs contain `resource`. Used by the UI to answer
-- "what makes bread?" and by validation to find orphaned chain links.
function BuildingSpec.getProducersOf(resource: string): { string }
	local out: { string } = {}
	for _, name in BuildingSpec.getAllNames() do
		local work = BuildingSpec.getWork(name)
		if work and work.outputs[resource] then
			table.insert(out, name)
		end
	end
	return out
end

function BuildingSpec.getConsumersOf(resource: string): { string }
	local out: { string } = {}
	for _, name in BuildingSpec.getAllNames() do
		local work = BuildingSpec.getWork(name)
		if work and work.inputs[resource] then
			table.insert(out, name)
		end
	end
	return out
end

-- Clears the memo. Only needed if BuildingsData is hot-reloaded in Studio.
function BuildingSpec.invalidate()
	cache = {}
end

return BuildingSpec
