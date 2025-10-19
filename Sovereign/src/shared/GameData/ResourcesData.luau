--!strict
-- Sovereign_V2/src/shared/GameData/ResourcesData.luau

-- Defines all game resources, their types, and descriptions.

export type ResourceData = {
	type: string,
	subtype: string,
	category: string,
	description: string,
}

export type ResourcesData = { [string]: ResourceData }

local resources: ResourcesData = {
	["Wood"] = {
		type = "Resource",
		subtype = "Construction Material",
		category = "materials",
		description = "Basic construction material, gathered from trees.",
	},
	["Stone"] = {
		type = "Resource",
		subtype = "Construction Material",
		category = "materials",
		description = "Durable building material, gathered from stone deposits.",
	},
	["Iron_Ore"] = {
		type = "Resource",
		subtype = "Raw Material",
		category = "materials",
		description = "Raw ore, processed into iron bars for weapons and armor.",
	},
	["Iron_Bars"] = {
		type = "Resource",
		subtype = "Processed Material",
		category = "military",
		description = "Processed iron, used in crafting advanced weapons and armor.",
	},
	["Wheat"] = {
		type = "Resource",
		subtype = "Food (Raw)",
		category = "food",
		description = "Grain, processed into flour for bread.",
	},
	["Flour"] = {
		type = "Resource",
		subtype = "Food (Processed)",
		category = "food",
		description = "Milled wheat, baked into bread.",
	},
	["Bread"] = {
		type = "Resource",
		subtype = "Food (Finished)",
		category = "food",
		description = "Staple food item, highly boosts peasant popularity.",
	},
	["Apples"] = {
		type = "Resource",
		subtype = "Food (Finished)",
		category = "food",
		description = "Fresh fruit, provides a basic popularity boost.",
	},
	["Cheese"] = {
		type = "Resource",
		subtype = "Food (Finished)",
		category = "food",
		description = "Dairy product, provides a moderate popularity boost.",
	},
	["Meat"] = {
		type = "Resource",
		subtype = "Food (Finished)",
		category = "food",
		description = "Hunting game, provides a good popularity boost.",
	},
	["Hops"] = { type = "Resource", subtype = "Crop", category = "food", description = "Plant used to brew ale." },
	["Ale"] = {
		type = "Resource",
		subtype = "Beverage",
		category = "food",
		description = "Brewed hops, consumed by peasants for significant popularity boost.",
	},
	["Pitch"] = {
		type = "Resource",
		subtype = "Military Resource",
		category = "military",
		description = "Flammable material used for defensive purposes.",
	},
	["Weapons"] = {
		type = "Resource",
		subtype = "Military Gear",
		category = "military",
		description = "Basic weapons for training military units.",
	},
	["Armor"] = {
		type = "Resource",
		subtype = "Military Gear",
		category = "military",
		description = "Basic armor for training military units.",
	},
	["Gold"] = {
		type = "Resource",
		subtype = "Currency",
		category = "currency",
		description = "Primary currency for trade and upkeep.",
	},
	["Horses"] = {
		type = "Resource",
		subtype = "Strategic",
		category = "strategic",
		description = "Mounts required for training cavalry units.",
	},
	["Honor"] = {
		type = "Resource",
		subtype = "Strategic",
		category = "strategic",
		description = "A measure of piety and valor, required for elite and blessed units.",
	},
}

return resources
