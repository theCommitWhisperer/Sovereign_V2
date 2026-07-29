--!strict
-- BuildingCatalog: everything the build UI needs to describe a building.
--
-- WHY
-- ---
-- The old build menu showed an icon and nothing else, so you had to already
-- know what a Clachan or a Sidhe Mound did before you could choose it. The
-- rebuilt drawer shows cost, staffing and output on every card, which means
-- somebody has to turn the raw config into display strings.
--
-- All of it is DERIVED from BuildingSpec rather than re-typed here, so a
-- balance change in BuildingsData shows up in the UI automatically and cannot
-- drift. That is the whole point of having normalized the config earlier:
-- "3 bread / 5s" is computed from work.outputs and work.cycle, not authored.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BuildingSpec = require(ReplicatedStorage.Shared.GameData.BuildingSpec)
local ResourcesData = require(ReplicatedStorage.Shared.GameData.ResourcesData)
local WorkerRoles = require(ReplicatedStorage.Shared.GameData.WorkerRoles)

local BuildingCatalog = {}

export type CostChip = {
	resource: string,
	amount: number,
	label: string,
}

export type Entry = {
	name: string,
	category: string,
	description: string,
	cost: { CostChip },
	-- "3 bread / 5s", "+5 population", "100 defence", or nil when a building
	-- has no legible headline effect.
	output: string?,
	-- "2 workers", or nil for buildings that employ nobody.
	staffing: string?,
	role: string?,
	gloryRequired: number,
}

-- Category membership. Kept as an explicit list rather than derived from
-- `subtype` because the categories are a UI grouping decision (the Smelter is
-- Industry by function but sits under Military because that is where players
-- look for the weapons chain), not a property of the building.
local CATEGORY_ORDER = { "Food", "Industry", "Military", "Defense", "Housing", "Prestige" }

local CATEGORIES: { [string]: { string } } = {
	Food = {
		"Potato Farm", "Sheep Farm", "Cow Farm", "Fishermans Hut",
		"Windmill", "Water Mill", "Bakery", "Brewery", "Granary",
	},
	Industry = {
		"Lumberjack", "Stone Quarry", "Iron Mine", "Coal Mine",
		"Tannery", "Carpenter", "Storehouse", "Market", "Trading Post",
	},
	Military = {
		"Barracks", "Archery Range", "Stables", "Training Ground",
		"Guard House", "Smelter", "Weaponsmith", "Armory", "Siege Workshop",
	},
	-- "Defense", not "Defence": HUDStore's default selectedCategory and every
	-- other reference in the codebase use the American spelling. A silent
	-- mismatch here made the lookup return an empty list, so the build bar
	-- opened on a category containing zero buildings.
	Defense = {
		"Stone Wall", "Short Tower", "Round Tower", "Wall Gatehouse",
		"Wall Ladder", "Wooden Palisade", "Arrow Tower", "Moat", "Fire Pit",
	},
	Housing = {
		"Hovel", "Clachan", "Inn", "Tavern", "Mead Hall",
		"Church", "Chapel", "Monastery", "Town Hall", "Scriptorium",
	},
	Prestige = {
		"Siege Tent", "Royal Assembly Hall", "Sidhe Mound",
		"Coastal Long-Port", "Celtic Cross",
	},
}

-- Icon per category. Drawn as glyphs rather than the old PNG set: the images
-- are fixed-proportion and were a large part of why the bar could not reflow.
local CATEGORY_ICON: { [string]: string } = {
	Food = "🌾",
	Industry = "⛏",
	Military = "⚔",
	Defense = "🛡",
	Housing = "🏠",
	Prestige = "👑",
}

local function displayName(resource: string): string
	local data = ResourcesData.get(resource)
	return data and data.display_name or (resource:gsub("_", " "))
end

--- Formats the headline effect. Order matters: production is the most useful
--- thing to know, then housing, then storage, then raw defence.
local function describeOutput(name: string): string?
	local spec = BuildingSpec.get(name)
	if not spec then
		return nil
	end

	local work = spec.work
	if work then
		-- Pick the highest-value output as the headline; a farm making both
		-- food and grain should lead with whichever is scarcer to produce, and
		-- amount is a good enough proxy without another config field.
		local bestResource, bestAmount = nil, 0
		for resource, amount in work.outputs do
			if amount > bestAmount then
				bestResource, bestAmount = resource, amount
			end
		end
		if bestResource then
			local extra = 0
			for _ in work.outputs do
				extra += 1
			end
			local suffix = extra > 1 and (" +%d more"):format(extra - 1) or ""
			return ("%d %s / %ds%s"):format(bestAmount, displayName(bestResource):lower(), work.cycle, suffix)
		end
	end

	if spec.housing > 0 then
		return ("+%d population"):format(spec.housing)
	end

	local storageTotal = 0
	for _, amount in spec.storage do
		storageTotal += amount
	end
	if storageTotal > 0 then
		return ("+%d storage"):format(storageTotal)
	end

	if spec.defenseValue > 0 then
		return ("%d defence"):format(spec.defenseValue)
	end

	if spec.trains and #spec.trains > 0 then
		return ("trains %s"):format(spec.trains[1])
	end

	return nil
end

local function describeStaffing(name: string): (string?, string?)
	local work = BuildingSpec.getWork(name)
	if not work or work.slots <= 0 then
		return nil, nil
	end
	local role = WorkerRoles.getOrDefault(work.role)
	local plural = work.slots == 1 and "worker" or "workers"
	return ("%d %s"):format(work.slots, plural), role.displayName
end

local cache: { [string]: Entry } = {}

function BuildingCatalog.get(name: string): Entry?
	if cache[name] then
		return cache[name]
	end

	local spec = BuildingSpec.get(name)
	if not spec then
		return nil
	end

	local cost: { CostChip } = {}
	for resource, amount in spec.cost do
		if amount > 0 then
			table.insert(cost, {
				resource = resource,
				amount = amount,
				label = ("%s %d"):format(displayName(resource), amount),
			})
		end
	end
	-- Stable order so a card's chips don't reshuffle between renders.
	table.sort(cost, function(a, b)
		return a.resource < b.resource
	end)

	local staffing, role = describeStaffing(name)

	local entry: Entry = {
		name = name,
		category = BuildingCatalog.categoryOf(name) or "Industry",
		description = spec.description,
		cost = cost,
		output = describeOutput(name),
		staffing = staffing,
		role = role,
		gloryRequired = spec.gloryRequired,
	}
	cache[name] = entry
	return entry
end

local categoryLookup: { [string]: string } = {}
for category, names in CATEGORIES do
	for _, name in names do
		categoryLookup[name] = category
	end
end

function BuildingCatalog.categoryOf(name: string): string?
	return categoryLookup[name]
end

function BuildingCatalog.getCategories(): { string }
	return table.clone(CATEGORY_ORDER)
end

function BuildingCatalog.getCategoryIcon(category: string): string
	return CATEGORY_ICON[category] or "•"
end

--- Entries for one category, skipping any name that is not in BuildingsData
--- (so a typo in the list above degrades to a missing card, not an error).
function BuildingCatalog.getCategory(category: string): { Entry }
	-- Loud on an unknown category. A "Defence"/"Defense" spelling mismatch
	-- against HUDStore silently produced an empty build bar, which looks like a
	-- broken menu rather than a bad key.
	if not CATEGORIES[category] then
		warn(("[BuildingCatalog] unknown category %q -- no buildings will show"):format(tostring(category)))
	end

	local out: { Entry } = {}
	for _, name in CATEGORIES[category] or {} do
		local entry = BuildingCatalog.get(name)
		if entry then
			table.insert(out, entry)
		end
	end
	return out
end

--- Can the player pay for this right now? Returns affordability plus the set
--- of resources that fall short, so the card can mark exactly which chip is
--- the blocker rather than just dimming the whole row.
function BuildingCatalog.affordability(
	entry: Entry,
	resources: { [string]: number }
): (boolean, { [string]: boolean })
	local short: { [string]: boolean } = {}
	local affordable = true
	for _, chip in entry.cost do
		if (resources[chip.resource] or 0) < chip.amount then
			short[chip.resource] = true
			affordable = false
		end
	end
	return affordable, short
end

--- Prestige buildings are gated on lifetime Glory, which is a separate lock
--- from affordability and needs its own message on the card.
function BuildingCatalog.isUnlocked(entry: Entry, gloryLifetime: number): boolean
	return entry.gloryRequired <= 0 or gloryLifetime >= entry.gloryRequired
end

return BuildingCatalog
