--!strict
-- ResourcesData: Definitions for all resources

local ResourcesData = {}

export type ResourceData = {
	display_name: string,
	icon: string?,
	is_tradeable: boolean,
	max_carry_amount: number,
}

ResourcesData.Wood = {
	display_name = "Wood",
	icon = "🌲",
	is_tradeable = true,
	max_carry_amount = 100,
} :: ResourceData

ResourcesData.Stone = {
	display_name = "Stone",
	icon = "🪨",
	is_tradeable = true,
	max_carry_amount = 100,
} :: ResourceData

ResourcesData.Gold = {
	display_name = "Gold",
	icon = "💰",
	is_tradeable = true,
	max_carry_amount = 1000,
} :: ResourceData

ResourcesData.Food = {
	display_name = "Food",
	icon = "🌾",
	is_tradeable = true,
	max_carry_amount = 200,
} :: ResourceData

ResourcesData.Iron_Bars = {
	display_name = "Iron Bars",
	icon = "🔩",
	is_tradeable = true,
	max_carry_amount = 50,
} :: ResourceData

ResourcesData.Weapons = {
	display_name = "Weapons",
	icon = "⚔️",
	is_tradeable = true,
	max_carry_amount = 50,
} :: ResourceData

ResourcesData.Iron_Ore = {
	display_name = "Iron Ore",
	icon = "⛏️",
	is_tradeable = true,
	max_carry_amount = 100,
} :: ResourceData

ResourcesData.Bread = {
	display_name = "Bread",
	icon = "🍞",
	is_tradeable = true,
	max_carry_amount = 200,
} :: ResourceData

ResourcesData.Ale = {
	display_name = "Ale",
	icon = "🍺",
	is_tradeable = true,
	max_carry_amount = 150,
} :: ResourceData

return ResourcesData
