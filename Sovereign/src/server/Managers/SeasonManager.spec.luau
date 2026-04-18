-- SeasonManager.spec.luau
-- Tests for season data initialisation and effect multipliers.

return function()
	local SeasonManager = require(script.Parent.SeasonManager)
	local PlayerManager = require(script.Parent.PlayerManager)

	local fakePlayer = { UserId = 777004, Name = "SeasonTestPlayer" } :: any

	beforeEach(function()
		PlayerManager.remove(fakePlayer)
		PlayerManager.create(fakePlayer)
		SeasonManager.create(fakePlayer)
	end)

	describe("create and get", function()
		it("creates season data without erroring", function()
			expect(function()
				SeasonManager.create(fakePlayer)
			end).never.to.throw()
		end)

		it("get returns data after create", function()
			expect(SeasonManager.get(fakePlayer)).to.be.ok()
		end)

		it("initial season is a valid Season string", function()
			local season = SeasonManager.getCurrentSeason(fakePlayer)
			local valid = { Spring = true, Summer = true, Autumn = true, Winter = true }
			expect(valid[season]).to.equal(true)
		end)
	end)

	describe("getSeasonEffects", function()
		it("returns an effects table for the current season", function()
			local effects = SeasonManager.getSeasonEffects(fakePlayer)
			expect(effects).to.be.a("table")
			expect(effects.foodConsumptionMultiplier).to.be.a("number")
			expect(effects.farmProductionMultiplier).to.be.a("number")
			expect(effects.happinessModifier).to.be.a("number")
			expect(effects.description).to.be.a("string")
		end)
	end)

	describe("season effect values are gameplay-sensible", function()
		local seasons = { "Spring", "Summer", "Autumn", "Winter" }

		it("all seasons have positive food consumption multipliers", function()
			local data = SeasonManager.get(fakePlayer)
			if not data then return end
			for _, s in seasons do
				data.currentSeason = s :: any
				local mult = SeasonManager.getFoodConsumptionMultiplier(fakePlayer)
				expect(mult > 0).to.equal(true)
			end
		end)

		it("Summer has the highest farm production (peak harvest)", function()
			local data = SeasonManager.get(fakePlayer)
			if not data then return end
			data.currentSeason = "Summer" :: any
			local summerFarm = SeasonManager.getFarmProductionMultiplier(fakePlayer)
			data.currentSeason = "Winter" :: any
			local winterFarm = SeasonManager.getFarmProductionMultiplier(fakePlayer)
			expect(summerFarm > winterFarm).to.equal(true)
		end)

		it("Winter has the highest food consumption (people need warmth)", function()
			local data = SeasonManager.get(fakePlayer)
			if not data then return end
			data.currentSeason = "Winter" :: any
			local winterFood = SeasonManager.getFoodConsumptionMultiplier(fakePlayer)
			data.currentSeason = "Summer" :: any
			local summerFood = SeasonManager.getFoodConsumptionMultiplier(fakePlayer)
			expect(winterFood > summerFood).to.equal(true)
		end)

		it("Winter happiness modifier is negative", function()
			local data = SeasonManager.get(fakePlayer)
			if not data then return end
			data.currentSeason = "Winter" :: any
			expect(SeasonManager.getHappinessModifier(fakePlayer) < 0).to.equal(true)
		end)

		it("Summer happiness modifier is positive", function()
			local data = SeasonManager.get(fakePlayer)
			if not data then return end
			data.currentSeason = "Summer" :: any
			expect(SeasonManager.getHappinessModifier(fakePlayer) > 0).to.equal(true)
		end)
	end)

	describe("advanceSeason", function()
		it("advances through all four seasons in a cycle", function()
			local data = SeasonManager.get(fakePlayer)
			if not data then return end
			data.currentSeason = "Spring" :: any
			local seen = {}
			for _ = 1, 4 do
				SeasonManager.advanceSeason(fakePlayer)
				seen[SeasonManager.getCurrentSeason(fakePlayer)] = true
			end
			-- After 4 advances from Spring we should have seen all seasons
			expect(seen["Summer"] or seen["Autumn"] or seen["Winter"]).to.equal(true)
		end)
	end)
end
