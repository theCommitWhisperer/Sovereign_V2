--!strict
-- ResourcesData: the single registry of every resource in the game.
--
-- WHY THIS IS THE ONLY LIST
-- -------------------------
-- PlayerManager.addResources used to credit a resource only if that key was
-- already present in the player's Resources table, and that table was seeded
-- from a hand-written literal listing nine resources. Flour, Leather, Furniture,
-- Coal, Manuscripts and Siege_Equipment were produced by buildings but never
-- seeded, so every attempt to credit them was silently dropped -- no error, no
-- warning, no log. Six production chains fed a black hole.
--
-- Everything that needs "the set of resources" now derives it from here:
--   PlayerManager   seeds Resources from ResourcesData.buildStartingTable()
--   TradeManager    derives base prices from .base_price
--   UI              derives icons/labels from .display_name / .icon
--
-- Adding a resource is a single entry in this file.

local ResourcesData = {}

-- Tier drives UI grouping and the market's glut curve: finished goods are worth
-- more but their prices move faster, so dumping volume hurts more.
export type ResourceTier = "Raw" | "Refined" | "Finished" | "Abstract"

export type ResourceData = {
	display_name: string,
	icon: string?,
	tier: ResourceTier,
	is_tradeable: boolean,
	base_price: number, -- gold per unit at neutral market conditions
	max_carry_amount: number, -- per-worker carry cap
	edible: boolean?, -- counts toward the food supply for rations
	starting_amount: number?, -- seeded into a new player's stock
}

local entries: { [string]: ResourceData } = {}

local function define(key: string, data: ResourceData)
	entries[key] = data
end

-- ============================================================
-- RAW -- gathered from world nodes by Gatherer workers
-- ============================================================
define("Wood", {
	display_name = "Wood",
	icon = "🌲",
	tier = "Raw",
	is_tradeable = true,
	base_price = 1.0,
	max_carry_amount = 100,
})

define("Stone", {
	display_name = "Stone",
	icon = "🪨",
	tier = "Raw",
	is_tradeable = true,
	base_price = 1.5,
	max_carry_amount = 100,
})

define("Iron_Ore", {
	display_name = "Iron Ore",
	icon = "⛏️",
	tier = "Raw",
	is_tradeable = true,
	base_price = 2.0,
	max_carry_amount = 100,
})

define("Coal", {
	display_name = "Coal",
	icon = "🪨",
	tier = "Raw",
	is_tradeable = true,
	base_price = 1.8,
	max_carry_amount = 100,
})

define("Grain", {
	display_name = "Grain",
	icon = "🌾",
	tier = "Raw",
	is_tradeable = true,
	base_price = 0.5,
	max_carry_amount = 150,
	edible = false, -- must be milled and baked before it feeds anyone
})

define("Hide", {
	display_name = "Hide",
	icon = "🐄",
	tier = "Raw",
	is_tradeable = true,
	base_price = 1.0,
	max_carry_amount = 100,
})

define("Food", {
	display_name = "Food",
	icon = "🥔",
	tier = "Raw",
	is_tradeable = true,
	base_price = 0.8,
	max_carry_amount = 200,
	edible = true,
})

define("Fish", {
	display_name = "Fish",
	icon = "🐟",
	tier = "Raw",
	is_tradeable = true,
	base_price = 1.0,
	max_carry_amount = 150,
	edible = true,
})

-- ============================================================
-- REFINED -- one Producer step away from raw
-- ============================================================
define("Iron_Bars", {
	display_name = "Iron Bars",
	icon = "🔩",
	tier = "Refined",
	is_tradeable = true,
	base_price = 4.0,
	max_carry_amount = 50,
})

define("Flour", {
	display_name = "Flour",
	icon = "🌾",
	tier = "Refined",
	is_tradeable = true,
	base_price = 1.2,
	max_carry_amount = 100,
})

define("Leather", {
	display_name = "Leather",
	icon = "🟫",
	tier = "Refined",
	is_tradeable = true,
	base_price = 2.5,
	max_carry_amount = 80,
})

define("Vellum", {
	display_name = "Vellum",
	icon = "📜",
	tier = "Refined",
	is_tradeable = true,
	base_price = 3.0,
	max_carry_amount = 60,
})

-- ============================================================
-- FINISHED -- end of a chain; where the money is
-- ============================================================
define("Weapons", {
	display_name = "Weapons",
	icon = "⚔️",
	tier = "Finished",
	is_tradeable = true,
	base_price = 8.0,
	max_carry_amount = 50,
})

define("Bread", {
	display_name = "Bread",
	icon = "🍞",
	tier = "Finished",
	is_tradeable = true,
	base_price = 2.4,
	max_carry_amount = 200,
	edible = true,
})

define("Ale", {
	display_name = "Ale",
	icon = "🍺",
	tier = "Finished",
	is_tradeable = true,
	base_price = 3.0,
	max_carry_amount = 150,
})

define("Furniture", {
	display_name = "Furniture",
	icon = "🪑",
	tier = "Finished",
	is_tradeable = true,
	base_price = 6.0,
	max_carry_amount = 40,
})

define("Manuscripts", {
	display_name = "Manuscripts",
	icon = "📖",
	tier = "Finished",
	is_tradeable = true,
	base_price = 10.0, -- the luxury good: slow, worker-hungry, very profitable
	max_carry_amount = 30,
})

define("Siege_Equipment", {
	display_name = "Siege Equipment",
	icon = "🏹",
	tier = "Finished",
	is_tradeable = false, -- strategic: must be built, cannot be bought
	base_price = 15.0,
	max_carry_amount = 10,
})

-- ============================================================
-- ABSTRACT -- not physical goods, never hauled or stored in buildings
-- ============================================================
define("Gold", {
	display_name = "Gold",
	icon = "💰",
	tier = "Abstract",
	is_tradeable = false, -- gold IS the currency; it is not traded against itself
	base_price = 1.0,
	max_carry_amount = 1000,
	starting_amount = 500,
})

define("Honor", {
	display_name = "Honor",
	icon = "🛡️",
	tier = "Abstract",
	is_tradeable = false,
	base_price = 0,
	max_carry_amount = 0,
})

-- ============================================================
-- DERIVED VIEWS
-- ============================================================

local allKeys: { string } = {}
for key in entries do
	table.insert(allKeys, key)
end
table.sort(allKeys)

-- Expose each resource as a direct field so existing call sites that read
-- ResourcesData.Wood keep working unchanged.
for key, data in entries do
	(ResourcesData :: any)[key] = data
end

function ResourcesData.getAllKeys(): { string }
	return allKeys
end

function ResourcesData.get(key: string): ResourceData?
	return entries[key]
end

function ResourcesData.isValid(key: string): boolean
	return entries[key] ~= nil
end

-- Builds a fresh, fully-populated stock table. EVERY resource is present and
-- zeroed, which is what makes addResources safe: there is no key it can fail
-- to find, so nothing can be silently dropped.
function ResourcesData.buildStartingTable(): { [string]: number }
	local stock: { [string]: number } = {}
	for key, data in entries do
		stock[key] = data.starting_amount or 0
	end
	return stock
end

-- Resources that count toward feeding the population.
function ResourcesData.getEdibleKeys(): { string }
	local edible: { string } = {}
	for _, key in allKeys do
		local data = entries[key]
		if data and data.edible then
			table.insert(edible, key)
		end
	end
	return edible
end

-- Base prices for the market, derived rather than duplicated in TradeManager.
function ResourcesData.getBasePrices(): { [string]: number }
	local prices: { [string]: number } = {}
	for key, data in entries do
		if data.is_tradeable then
			prices[key] = data.base_price
		end
	end
	return prices
end

return ResourcesData
