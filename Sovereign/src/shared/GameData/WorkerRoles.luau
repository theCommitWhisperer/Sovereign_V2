--!strict
-- WorkerRoles: every trade in the kingdom, as data.
--
-- THE POINT OF THIS FILE
-- ----------------------
-- The kingdom should feel alive, so it keeps two dozen distinct trades -- a
-- Baker looks and behaves differently from a Miner, and the player should see
-- that. But before this, "job type" was a string that code branched on in a
-- dozen places, so every new trade meant new branches in WorkerManager.
--
-- Here, a trade is purely descriptive. Every one of them resolves to exactly
-- one of four BEHAVIOURS, and the worker engine only ever implements four:
--
--   Gatherer  walks to a world ResourceNode, harvests, carries the load home
--   Producer  stands at a station and converts inputs -> outputs on a cycle
--   Hauler    moves goods between buildings and storage
--   Server    provides a non-material effect (popularity, faith, tax uplift)
--
-- Adding a trade is one entry here. It requires no engine change at all.

local WorkerRoles = {}

export type Behaviour = "Gatherer" | "Producer" | "Hauler" | "Server"

export type RoleData = {
	displayName: string, -- shown on the unit's overhead label
	behaviour: Behaviour,
	rigSet: string, -- folder under Assets/Units, resolved by getUnitModel
	animSet: string, -- drives UnitAnimator (custom rigs ignore stock R6/R15)
	carryCapacity: number?, -- Gatherer/Hauler only; defaults per behaviour
	description: string,
}

local roles: { [string]: RoleData } = {}

local function define(key: string, data: RoleData)
	roles[key] = data
end

-- ============================================================
-- GATHERERS -- the raw-material front line
-- ============================================================
define("Woodcutter", {
	displayName = "Woodcutter",
	behaviour = "Gatherer",
	rigSet = "Woodcutter",
	animSet = "Chop",
	carryCapacity = 10,
	description = "Fells trees and carries logs back to the lumber camp.",
})

define("Stonemason", {
	displayName = "Stonemason",
	behaviour = "Gatherer",
	rigSet = "Stonemason",
	animSet = "Mine",
	carryCapacity = 8,
	description = "Cuts stone from the quarry face.",
})

define("Miner", {
	displayName = "Miner",
	behaviour = "Gatherer",
	rigSet = "Miner",
	animSet = "Mine",
	carryCapacity = 8,
	description = "Digs ore and coal from the seam.",
})

define("Farmer", {
	displayName = "Farmer",
	behaviour = "Gatherer",
	rigSet = "Farmer",
	animSet = "Harvest",
	carryCapacity = 12,
	description = "Works the fields and brings in the harvest.",
})

define("Shepherd", {
	displayName = "Shepherd",
	behaviour = "Gatherer",
	rigSet = "Farmer",
	animSet = "Harvest",
	carryCapacity = 10,
	description = "Tends the flock for hides and meat.",
})

define("Fisherman", {
	displayName = "Fisherman",
	behaviour = "Gatherer",
	rigSet = "Fisherman",
	animSet = "Fish",
	carryCapacity = 12,
	description = "Nets fish from the coast.",
})

define("Hunter", {
	displayName = "Hunter",
	behaviour = "Gatherer",
	rigSet = "Hunter",
	animSet = "Hunt",
	carryCapacity = 10,
	description = "Hunts game for meat and hides.",
})

-- ============================================================
-- PRODUCERS -- the chains, where raw goods become valuable
-- ============================================================
define("Miller", {
	displayName = "Miller",
	behaviour = "Producer",
	rigSet = "Miller",
	animSet = "Craft",
	description = "Grinds grain into flour.",
})

define("Baker", {
	displayName = "Baker",
	behaviour = "Producer",
	rigSet = "Baker",
	animSet = "Craft",
	description = "Bakes flour into bread, the staple of the kingdom.",
})

define("Brewer", {
	displayName = "Brewer",
	behaviour = "Producer",
	rigSet = "Brewer",
	animSet = "Craft",
	description = "Brews ale. Ale keeps the people cheerful under heavy tax.",
})

define("Smelter", {
	displayName = "Smelter",
	behaviour = "Producer",
	rigSet = "Smelter",
	animSet = "Smith",
	description = "Smelts iron ore into bars.",
})

define("Blacksmith", {
	displayName = "Blacksmith",
	behaviour = "Producer",
	rigSet = "Blacksmith",
	animSet = "Smith",
	description = "Forges iron bars into weapons -- the richest chain in the game.",
})

define("Tanner", {
	displayName = "Tanner",
	behaviour = "Producer",
	rigSet = "Tanner",
	animSet = "Craft",
	description = "Cures hides into leather.",
})

define("Carpenter", {
	displayName = "Carpenter",
	behaviour = "Producer",
	rigSet = "Carpenter",
	animSet = "Craft",
	description = "Works wood and leather into furniture.",
})

define("Fletcher", {
	displayName = "Fletcher",
	behaviour = "Producer",
	rigSet = "Fletcher",
	animSet = "Craft",
	description = "Makes bows and siege parts.",
})

define("Scribe", {
	displayName = "Scribe",
	behaviour = "Producer",
	rigSet = "Scribe",
	animSet = "Write",
	description = "Copies manuscripts. Slow, worker-hungry, and very profitable.",
})

define("Parchmenter", {
	displayName = "Parchmenter",
	behaviour = "Producer",
	rigSet = "Tanner",
	animSet = "Craft",
	description = "Prepares hides into vellum for the scriptorium.",
})

define("Engineer", {
	displayName = "Engineer",
	behaviour = "Producer",
	rigSet = "Engineer",
	animSet = "Craft",
	description = "Assembles siege equipment.",
})

-- ============================================================
-- HAULERS -- the circulatory system
-- ============================================================
define("Hauler", {
	displayName = "Hauler",
	behaviour = "Hauler",
	rigSet = "Peasant",
	animSet = "Carry",
	carryCapacity = 15,
	description = "Moves goods between producers and storage.",
})

define("Oxdriver", {
	displayName = "Ox Driver",
	behaviour = "Hauler",
	rigSet = "Oxdriver",
	animSet = "Carry",
	carryCapacity = 40,
	description = "Drives an ox cart. Slow, but moves a great deal at once.",
})

-- ============================================================
-- SERVERS -- no goods produced, but they hold the kingdom together
-- ============================================================
define("Innkeeper", {
	displayName = "Innkeeper",
	behaviour = "Server",
	rigSet = "Innkeeper",
	animSet = "Serve",
	description = "Serves ale. Converts stock into popularity.",
})

define("Priest", {
	displayName = "Priest",
	behaviour = "Server",
	rigSet = "Priest",
	animSet = "Bless",
	description = "Tends souls. Faith is the cheapest popularity, but it is capped.",
})

define("Monk", {
	displayName = "Monk",
	behaviour = "Server",
	rigSet = "Monk",
	animSet = "Bless",
	description = "Keeps the monastery and its scriptorium.",
})

define("Administrator", {
	displayName = "Administrator",
	behaviour = "Server",
	rigSet = "Administrator",
	animSet = "Write",
	description = "Runs the town hall. Improves tax collection efficiency.",
})

define("Merchant", {
	displayName = "Merchant",
	behaviour = "Server",
	rigSet = "Merchant",
	animSet = "Serve",
	description = "Runs the market. Reduces the fee taken on every sale.",
})

define("Trader", {
	displayName = "Trader",
	behaviour = "Server",
	rigSet = "Merchant",
	animSet = "Serve",
	description = "Runs caravan routes to distant towns.",
})

define("Archer", {
	displayName = "Archer",
	behaviour = "Server",
	rigSet = "Archer",
	animSet = "Bow",
	description = "Mans a tower. Garrison, not economy.",
})

-- ============================================================
-- THE DEFAULT -- an unassigned peasant
-- ============================================================
define("Peasant", {
	displayName = "Peasant",
	behaviour = "Server",
	rigSet = "Peasant",
	animSet = "Idle",
	description = "Unemployed, waiting at the campfire for work.",
})

-- ============================================================
-- LOOKUP
-- ============================================================

local DEFAULT_CARRY: { [string]: number } = {
	Gatherer = 10,
	Hauler = 15,
	Producer = 0,
	Server = 0,
}

function WorkerRoles.get(role: string): RoleData?
	return roles[role]
end

-- Never returns nil: an unknown role falls back to Peasant so a typo in
-- BuildingsData degrades to "an idle-looking villager" rather than an error.
function WorkerRoles.getOrDefault(role: string?): RoleData
	if role and roles[role] then
		return roles[role]
	end
	if role then
		warn(("[WorkerRoles] unknown role %q, falling back to Peasant"):format(role))
	end
	return roles.Peasant
end

function WorkerRoles.getBehaviour(role: string?): Behaviour
	return WorkerRoles.getOrDefault(role).behaviour
end

function WorkerRoles.getCarryCapacity(role: string?): number
	local data = WorkerRoles.getOrDefault(role)
	return data.carryCapacity or DEFAULT_CARRY[data.behaviour] or 0
end

function WorkerRoles.getAll(): { [string]: RoleData }
	return roles
end

function WorkerRoles.getRolesWithBehaviour(behaviour: Behaviour): { string }
	local out: { string } = {}
	for key, data in roles do
		if data.behaviour == behaviour then
			table.insert(out, key)
		end
	end
	table.sort(out)
	return out
end

return WorkerRoles
