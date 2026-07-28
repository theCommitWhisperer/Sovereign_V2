--!strict
-- MonetizationConfig: Cosmetic catalogs + Hero ability tree structure.
--
-- ROBLOX POLICY COMPLIANCE: everything sold here is cosmetic (skins, banner
-- styles) or progression-shaped (ability tree unlocks paid with the in-game
-- Glory currency). Nothing modifies base unit stats — no pay-to-win.
--
-- TODO: replace every `productId = 0` / `gamePassId = 0` placeholder with the
-- real IDs from the Creator Dashboard before shipping.

export type CosmeticSkin = {
	id: string, -- stable internal id (persisted — never rename)
	name: string, -- player-facing name
	description: string,
	-- How the skin is obtained:
	--   "Free"      — everyone owns it (defaults)
	--   "GamePass"  — owned while the gamepass is owned (gamePassId)
	--   "DevProduct"— one-time purchase, persisted (productId)
	acquisition: "Free" | "GamePass" | "DevProduct",
	gamePassId: number?, -- TODO real id
	productId: number?, -- TODO real id
	-- Cosmetic payload: either a model swap or a tint (both optional)
	modelFolder: string?, -- e.g. Assets/Skins/<modelFolder> variant rig to swap in
	tintColor: Color3?, -- applied to the unit/lord primary parts
}

export type BannerStyle = {
	id: string,
	name: string,
	description: string,
	acquisition: "Free" | "GamePass" | "DevProduct",
	gamePassId: number?,
	productId: number?,
	primaryColor: Color3?,
	pattern: string?, -- decal/texture name in Assets/Banners (TODO: create assets)
}

export type AbilityNode = {
	id: string, -- stable internal id (persisted)
	name: string,
	description: string,
	abilityId: string, -- AbilityManager ability this node unlocks/upgrades
	maxRank: number, -- ranks beyond 1 upgrade the ability (cooldown/duration, never base stats)
	gloryCostPerRank: { number }, -- in-game Glory cost for rank 1..maxRank
	prerequisites: { string }, -- node ids that must be at rank >= 1 first
}

local MonetizationConfig = {}

-- ============================================================
-- LORD SKINS (cosmetic only — swaps/tints the Lord character rig)
-- ============================================================
MonetizationConfig.LordSkins = {
	{
		id = "lord_default",
		name = "Lord of the Tuath",
		description = "The classic lord's garb.",
		acquisition = "Free",
	} :: CosmeticSkin,
	{
		id = "lord_highking",
		name = "High King Regalia",
		description = "Gilded cloak and circlet of the High Kings of Tara.",
		acquisition = "GamePass",
		gamePassId = 0, -- TODO: real GamePass id
		tintColor = Color3.fromRGB(218, 165, 32),
	} :: CosmeticSkin,
	{
		id = "lord_seawolf",
		name = "Sea-Wolf Raider",
		description = "Furs and iron of the Norse sea-kings of Dublin.",
		acquisition = "DevProduct",
		productId = 0, -- TODO: real DevProduct id
		modelFolder = "LordSeaWolf", -- TODO: create Assets/Skins/LordSeaWolf rig
	} :: CosmeticSkin,
}

-- ============================================================
-- UNIT SKINS (cosmetic only — applied per unit type across the army)
-- ============================================================
MonetizationConfig.UnitSkins = {
	{
		id = "units_default",
		name = "Levy Cloth",
		description = "Standard issue for the working folk.",
		acquisition = "Free",
	} :: CosmeticSkin,
	{
		id = "units_emerald",
		name = "Emerald Host",
		description = "Deep green cloaks for the whole army.",
		acquisition = "GamePass",
		gamePassId = 0, -- TODO: real GamePass id
		tintColor = Color3.fromRGB(20, 120, 60),
	} :: CosmeticSkin,
	{
		id = "units_gallowglass",
		name = "Gallowglass Mail",
		description = "Mercenary mail-coat look for melee units.",
		acquisition = "DevProduct",
		productId = 0, -- TODO: real DevProduct id
		modelFolder = "UnitsGallowglass", -- TODO: create Assets/Skins/UnitsGallowglass variants
	} :: CosmeticSkin,
}

-- ============================================================
-- BANNER STYLES (cosmetic — Keep/estate flag patterns, stacks with lobby color)
-- ============================================================
MonetizationConfig.BannerStyles = {
	{
		id = "banner_plain",
		name = "Plain Banner",
		description = "A simple field of your kingdom color.",
		acquisition = "Free",
	} :: BannerStyle,
	{
		id = "banner_knotwork",
		name = "Celtic Knotwork",
		description = "Interlaced knotwork border.",
		acquisition = "DevProduct",
		productId = 0, -- TODO: real DevProduct id
		pattern = "Knotwork", -- TODO: create Assets/Banners/Knotwork texture
	} :: BannerStyle,
	{
		id = "banner_raven",
		name = "Raven Standard",
		description = "The dread raven of the northern sea-kings.",
		acquisition = "DevProduct",
		productId = 0, -- TODO: real DevProduct id
		pattern = "Raven", -- TODO: create Assets/Banners/Raven texture
	} :: BannerStyle,
}

-- ============================================================
-- HERO ABILITY TREE
-- Nodes unlock/upgrade hero ABILITIES (cast effects, cooldowns, durations).
-- Base hero stats are never touched — progression, not power-selling.
-- Costs are paid in Glory (earned in-game; see GloryManager).
-- ============================================================
MonetizationConfig.HeroAbilityTree = {
	{
		id = "node_rally",
		name = "Rallying Cry",
		description = "Unlock the Rally ability: nearby units regroup on the hero.",
		abilityId = "Rally",
		maxRank = 3, -- ranks 2-3 reduce cooldown
		gloryCostPerRank = { 100, 250, 500 },
		prerequisites = {},
	} :: AbilityNode,
	{
		id = "node_warhorn",
		name = "War Horn",
		description = "Unlock the War Horn: briefly boosts army morale (visual/morale only).",
		abilityId = "WarHorn",
		maxRank = 2,
		gloryCostPerRank = { 200, 400 },
		prerequisites = { "node_rally" },
	} :: AbilityNode,
	{
		id = "node_earthshake",
		name = "Earthshaker",
		description = "Unlock Earthshaker: a dramatic ground-slam taunt that draws enemy focus.",
		abilityId = "Earthshaker",
		maxRank = 3,
		gloryCostPerRank = { 300, 600, 1000 },
		prerequisites = { "node_warhorn" },
	} :: AbilityNode,
	{
		id = "node_beacon",
		name = "Beacon of Tara",
		description = "Unlock the Beacon: marks a rally point visible to your whole army.",
		abilityId = "Beacon",
		maxRank = 1,
		gloryCostPerRank = { 150 },
		prerequisites = { "node_rally" },
	} :: AbilityNode,
}

-- ============================================================
-- LOOKUP HELPERS
-- ============================================================

function MonetizationConfig.findSkin(category: string, skinId: string): CosmeticSkin?
	local catalog: { CosmeticSkin }? = if category == "LordSkins"
		then MonetizationConfig.LordSkins
		elseif category == "UnitSkins" then MonetizationConfig.UnitSkins
		else nil
	if not catalog then
		return nil
	end
	for _, skin in catalog do
		if skin.id == skinId then
			return skin
		end
	end
	return nil
end

function MonetizationConfig.findBannerStyle(styleId: string): BannerStyle?
	for _, style in MonetizationConfig.BannerStyles do
		if style.id == styleId then
			return style
		end
	end
	return nil
end

function MonetizationConfig.findAbilityNode(nodeId: string): AbilityNode?
	for _, node in MonetizationConfig.HeroAbilityTree do
		if node.id == nodeId then
			return node
		end
	end
	return nil
end

-- Find any catalog entry by its DevProduct id (used by ProcessReceipt)
function MonetizationConfig.findByProductId(productId: number): (string?, string?)
	if productId == 0 then
		return nil, nil
	end
	for _, skin in MonetizationConfig.LordSkins do
		if skin.productId == productId then
			return "LordSkins", skin.id
		end
	end
	for _, skin in MonetizationConfig.UnitSkins do
		if skin.productId == productId then
			return "UnitSkins", skin.id
		end
	end
	for _, style in MonetizationConfig.BannerStyles do
		if style.productId == productId then
			return "BannerStyles", style.id
		end
	end
	return nil, nil
end

return MonetizationConfig
