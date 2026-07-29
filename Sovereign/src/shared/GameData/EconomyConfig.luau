--!strict
-- EconomyConfig: Single source of truth for tunable economy-loop values.
--
-- CORE LOOP (all numbers live here, systems only read them):
--   Keep placed -> Lord + Peasants spawn -> Granary/Storehouse store resources
--   -> Food Rations policy scales consumption (ConsumptionManager)
--   -> Rations + food supply drive Popularity/Happiness (HappinessSystem)
--   -> Popularity gates Tax income in Gold (TaxSystem/TaxManager)
--
-- Values below mirror the balance that already shipped in the individual
-- managers (0.1 food/peasant/cycle, 30s consumption cycle, 60s tax cycle,
-- 10% default tax) — do not change one side without checking the loop.

export type RationsPolicy = {
	-- Multiplier applied to total food consumption for this rations level
	consumptionMultiplier: number,
	-- Flat happiness modifier while this rations level is active
	happinessModifier: number,
}

export type TaxPolicy = {
	rate: number, -- 0..1 tax rate this policy sets
}

local EconomyConfig = {}

-- ============================================================
-- CONSUMPTION
-- ============================================================
EconomyConfig.Consumption = {
	cycleSeconds = 30, -- ConsumptionSystem tick (scaled by GameSettings.waitInterval)
	foodPerPeasant = 0.1, -- food per person per cycle (pre-rations, pre-season)
}

-- ============================================================
-- FOOD RATIONS POLICIES (names match ui/screens/Policies/Policies.luau)
-- ============================================================
EconomyConfig.DefaultRationsPolicy = "Normal Rations"
EconomyConfig.RationsPolicies = {
	["Double Rations"] = { consumptionMultiplier = 2.0, happinessModifier = 20 } :: RationsPolicy,
	["Extra Rations"] = { consumptionMultiplier = 1.5, happinessModifier = 10 } :: RationsPolicy,
	["Normal Rations"] = { consumptionMultiplier = 1.0, happinessModifier = 0 } :: RationsPolicy,
	["Half Rations"] = { consumptionMultiplier = 0.5, happinessModifier = -15 } :: RationsPolicy,
} :: { [string]: RationsPolicy }

-- ============================================================
-- TAXATION
-- ============================================================
EconomyConfig.Tax = {
	cycleSeconds = 60, -- TaxManager collection interval (scaled by game speed)
	defaultRate = 0.1, -- initial 10% tax
	-- Happiness penalties for tax pressure (used by HappinessSystem)
	heavyTaxThreshold = 0.5, -- above this rate...
	heavyTaxPenalty = -30, -- ...this happiness penalty
	moderateTaxThreshold = 0.2,
	moderateTaxPenalty = -15,
}

-- Tax policy presets (names match ui/screens/Policies/Policies.luau)
--
-- Tax is how you SPEND popularity. Income scales with population, so the wide-
-- and-loyal kingdom earns most from a punishing rate -- but only if it has
-- bought enough popularity headroom (rations, ale, faith) to survive it. That
-- trade is the core of the economy; see docs/EconomyRedesign.md section 3.1.
EconomyConfig.DefaultTaxPolicy = "Normal Tax"
EconomyConfig.TaxPolicies = {
	-- Negative rate = you PAY your subjects. Buys popularity with gold, which
	-- is how a rich industrial kingdom converts trade profit back into headroom.
	["Generous Gifts"] = { rate = -0.05 } :: TaxPolicy,
	["No Tax"] = { rate = 0.0 } :: TaxPolicy,
	["Low Tax"] = { rate = 0.05 } :: TaxPolicy,
	["Normal Tax"] = { rate = 0.1 } :: TaxPolicy,
	["High Tax"] = { rate = 0.3 } :: TaxPolicy,
	-- The greed option. Enormous income, but -50 popularity means only a
	-- kingdom running double rations AND ale AND churches can hold it, and
	-- one bad harvest tips it straight into revolt.
	["Extortionate"] = { rate = 0.45 } :: TaxPolicy,
} :: { [string]: TaxPolicy }

-- ============================================================
-- POPULARITY SOURCES
--
-- The budget the tax rate is spent against. Each source has a cap so no single
-- one can carry an Extortionate rate alone -- you need several running at once,
-- and every one of them costs food, buildings or workers.
-- ============================================================
EconomyConfig.Popularity = {
	-- Ale served at taverns/inns. The strongest buyable popularity, and the
	-- reason the Grain -> Ale chain competes with Grain -> Flour -> Bread.
	aleMaxBonus = 20,
	alePerServingBuilding = 5,

	-- Faith from churches/chapels/monasteries. Cheapest per point (no goods
	-- consumed) but capped low, so it is a floor-raiser, not a strategy.
	faithMaxBonus = 15,
	faithPerBuilding = 5,

	-- Crowding: housing filled beyond comfort costs popularity.
	crowdingThreshold = 0.9, -- population / housing capacity above this...
	crowdingPenaltyPerTenth = -4, -- ...costs this per 10% over

	-- Food variety: eating nothing but potatoes is miserable. Counts DISTINCT
	-- edible resources in stock, which is what makes the fish/bread branches
	-- worth building even once you have enough raw calories.
	varietyBonusPerType = 4,
	varietyMaxBonus = 12,
}

-- Popularity gate on tax income: unhappy subjects pay less (or nothing).
-- Checked top-down; first entry whose minHappiness <= happiness wins.
EconomyConfig.TaxPopularityGate = {
	{ minHappiness = 80, incomeMultiplier = 1.25 }, -- loyal subjects pay a bonus
	{ minHappiness = 50, incomeMultiplier = 1.0 },
	{ minHappiness = 30, incomeMultiplier = 0.5 },
	{ minHappiness = 15, incomeMultiplier = 0.25 },
	{ minHappiness = 0, incomeMultiplier = 0.0 }, -- open revolt: nobody pays
}

-- Returns the tax income multiplier for a happiness value (0-100)
function EconomyConfig.getTaxPopularityMultiplier(happiness: number): number
	for _, tier in EconomyConfig.TaxPopularityGate do
		if happiness >= tier.minHappiness then
			return tier.incomeMultiplier
		end
	end
	return 0
end

-- ============================================================
-- ESTATES (capturable neutral territory)
-- Studio setup: place Models (or lone BaseParts) named "EstateFlagpole"
-- anywhere under Workspace (a "Estates" folder inside the map folder is the
-- convention). Each flagpole becomes one capturable estate. The flag mesh(es)
-- to tint should be named "Flag"/"Banner" (same rule as Keep banners); if
-- none exist the flagpole part itself is tinted.
-- ============================================================
EconomyConfig.Estates = {
	flagpoleName = "EstateFlagpole",
	captureRadius = 30, -- studs: units within this radius of the flag contest it
	captureSeconds = 10, -- uncontested seconds near a flag to flip ownership
	tickSeconds = 1, -- capture-check interval
	neutralColor = Color3.fromRGB(200, 200, 200),

	-- Supply cart deliveries from owned estates to the owner's Keep
	cartIntervalSeconds = 90, -- one cart per estate per interval (game-speed scaled)
	cartSpeed = 10, -- studs/second straight-line travel
	cartYield = { Stone = 10, Iron_Ore = 5, Food = 15 } :: { [string]: number },
}

return EconomyConfig
