-- EconomyIntegration.spec.luau
-- Simulates one economy tick and verifies food consumption, starvation,
-- seasonal multipliers, and tax collection all wire up correctly.
-- These are the core loops that run every 30s in a live game.

return function()
	local Helper           = require(script.Parent.IntegrationHelper)
	local PlayerManager    = require(script.Parent.Parent.Managers.PlayerManager)
	local ConsumptionManager = require(script.Parent.Parent.Managers.ConsumptionManager)
	local SeasonManager    = require(script.Parent.Parent.Managers.SeasonManager)
	local TaxManager       = require(script.Parent.Parent.Managers.TaxManager)

	local fake

	beforeEach(function()
		fake = Helper.setup(888100)
	end)

	afterEach(function()
		Helper.teardown(fake)
	end)

	-- ─────────────────────────────────────────────────────────────
	-- Food consumption
	-- ─────────────────────────────────────────────────────────────
	describe("food consumption tick", function()
		it("does not consume food when player has no population", function()
			PlayerManager.addResources(fake, { Food = 100 })
			ConsumptionManager.consumeFood(fake)
			local pd = PlayerManager.get(fake)
			expect(pd.Resources.Food).to.equal(100) -- nothing consumed
		end)

		it("deducts food proportional to peasant population", function()
			-- 10 peasants × 0.1 food/peasant = 1 food per tick (Normal season)
			Helper.addPeasants(fake, 10)
			PlayerManager.addResources(fake, { Food = 100 })
			ConsumptionManager.consumeFood(fake)
			local pd = PlayerManager.get(fake)
			-- Seasonal multiplier may shift this slightly; just confirm food decreased
			expect(pd.Resources.Food < 100).to.equal(true)
		end)

		it("returns true when food is sufficient", function()
			Helper.addPeasants(fake, 5)
			PlayerManager.addResources(fake, { Food = 500 })
			local result = ConsumptionManager.consumeFood(fake)
			expect(result).to.equal(true)
		end)

		it("returns false and starts starvation when food runs out", function()
			Helper.addPeasants(fake, 5)
			-- No food at all
			local result = ConsumptionManager.consumeFood(fake)
			expect(result).to.equal(false)
			expect(ConsumptionManager.isStarving(fake)).to.equal(true)
		end)

		it("starvation duration accumulates across multiple starving ticks", function()
			Helper.addPeasants(fake, 5)
			ConsumptionManager.consumeFood(fake) -- tick 1, no food → 30s
			ConsumptionManager.consumeFood(fake) -- tick 2 → 60s
			local duration = ConsumptionManager.getStarvationDuration(fake)
			expect(duration).to.equal(60)
		end)

		it("starvation resets when food is available again", function()
			Helper.addPeasants(fake, 5)
			ConsumptionManager.consumeFood(fake) -- starve once
			PlayerManager.addResources(fake, { Food = 500 })
			ConsumptionManager.consumeFood(fake) -- fed now
			expect(ConsumptionManager.isStarving(fake)).to.equal(false)
		end)
	end)

	-- ─────────────────────────────────────────────────────────────
	-- Seasonal multipliers affect consumption
	-- ─────────────────────────────────────────────────────────────
	describe("seasonal food consumption multipliers", function()
		it("Winter consumes more food than Summer for the same population", function()
			Helper.addPeasants(fake, 10)

			local sd = SeasonManager.get(fake)
			if not sd then return end

			sd.currentSeason = "Summer" :: any
			local summerAmount = ConsumptionManager.getTotalConsumption(fake)

			sd.currentSeason = "Winter" :: any
			local winterAmount = ConsumptionManager.getTotalConsumption(fake)

			expect(winterAmount > summerAmount).to.equal(true)
		end)

		it("Spring produces more on farms than Autumn (via SeasonManager)", function()
			local sd = SeasonManager.get(fake)
			if not sd then return end

			sd.currentSeason = "Spring" :: any
			local springFarm = SeasonManager.getFarmProductionMultiplier(fake)

			sd.currentSeason = "Autumn" :: any
			local autumnFarm = SeasonManager.getFarmProductionMultiplier(fake)

			expect(springFarm > autumnFarm).to.equal(true)
		end)
	end)

	-- ─────────────────────────────────────────────────────────────
	-- Tax collection
	-- ─────────────────────────────────────────────────────────────
	describe("tax collection", function()
		it("collecting taxes with 0 population gives 0 gold", function()
			TaxManager.setTaxRate(fake, 0.5)
			TaxManager.collectTaxes(fake)
			local pd = PlayerManager.get(fake)
			expect(pd.Resources.Gold).to.equal(0)
		end)

		it("gold earned scales with population and tax rate", function()
			Helper.addPeasants(fake, 20) -- 20 units
			TaxManager.setTaxRate(fake, 0.5) -- 50% rate → 10 gold (floor)
			TaxManager.collectTaxes(fake)
			local pd = PlayerManager.get(fake)
			expect(pd.Resources.Gold).to.equal(10)
		end)

		it("0% tax rate produces no gold", function()
			Helper.addPeasants(fake, 20)
			TaxManager.setTaxRate(fake, 0)
			TaxManager.collectTaxes(fake)
			local pd = PlayerManager.get(fake)
			expect(pd.Resources.Gold).to.equal(0)
		end)

		it("accumulated gold from multiple collections", function()
			Helper.addPeasants(fake, 10)
			TaxManager.setTaxRate(fake, 0.1) -- 1 gold per collection
			TaxManager.collectTaxes(fake)
			TaxManager.collectTaxes(fake)
			local pd = PlayerManager.get(fake)
			expect(pd.Resources.Gold).to.equal(2)
		end)
	end)
end
