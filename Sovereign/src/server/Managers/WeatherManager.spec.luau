-- WeatherManager.spec.luau
-- Tests for weather data initialisation and effect multipliers.

return function()
	local WeatherManager = require(script.Parent.WeatherManager)
	local PlayerManager = require(script.Parent.PlayerManager)
	local SeasonManager = require(script.Parent.SeasonManager)

	local fakePlayer = { UserId = 777003, Name = "WeatherTestPlayer" } :: any

	beforeEach(function()
		PlayerManager.remove(fakePlayer)
		PlayerManager.create(fakePlayer)
		SeasonManager.create(fakePlayer) -- WeatherManager uses SeasonManager for multipliers
		WeatherManager.create(fakePlayer)
	end)

	describe("create and get", function()
		it("creates weather data without erroring", function()
			expect(function()
				WeatherManager.create(fakePlayer)
			end).never.to.throw()
		end)

		it("get returns data after create", function()
			local data = WeatherManager.get(fakePlayer)
			expect(data).to.be.ok()
		end)

		it("initial weather is a valid WeatherType string", function()
			local weather = WeatherManager.getCurrentWeather(fakePlayer)
			local valid = { Clear = true, Rain = true, Drought = true, Storm = true }
			expect(valid[weather]).to.equal(true)
		end)
	end)

	describe("getFarmProductionMultiplier", function()
		it("returns a positive number", function()
			local mult = WeatherManager.getFarmProductionMultiplier(fakePlayer)
			expect(mult > 0).to.equal(true)
		end)

		it("returns a number (not nil) even before any weather change", function()
			expect(WeatherManager.getFarmProductionMultiplier(fakePlayer)).to.be.a("number")
		end)
	end)

	describe("getMiningProductionMultiplier", function()
		it("returns a positive number", function()
			local mult = WeatherManager.getMiningProductionMultiplier(fakePlayer)
			expect(mult > 0).to.equal(true)
		end)
	end)

	describe("getWeatherEffects", function()
		it("returns an effects table with expected fields", function()
			local effects = WeatherManager.getWeatherEffects(fakePlayer)
			expect(effects).to.be.a("table")
			expect(effects.farmProductionMultiplier).to.be.a("number")
			expect(effects.miningProductionMultiplier).to.be.a("number")
			expect(effects.description).to.be.a("string")
		end)

		it("Clear weather has farm multiplier of 1.0", function()
			-- Set weather data directly to Clear and check effects
			local data = WeatherManager.get(fakePlayer)
			if data then
				data.currentWeather = "Clear"
				local effects = WeatherManager.getWeatherEffects(fakePlayer)
				expect(effects.farmProductionMultiplier).to.equal(1.0)
				expect(effects.miningProductionMultiplier).to.equal(1.0)
			end
		end)

		it("Rain boosts farm production above 1.0", function()
			local data = WeatherManager.get(fakePlayer)
			if data then
				data.currentWeather = "Rain"
				local effects = WeatherManager.getWeatherEffects(fakePlayer)
				expect(effects.farmProductionMultiplier > 1.0).to.equal(true)
			end
		end)

		it("Drought reduces farm production below 1.0", function()
			local data = WeatherManager.get(fakePlayer)
			if data then
				data.currentWeather = "Drought"
				local effects = WeatherManager.getWeatherEffects(fakePlayer)
				expect(effects.farmProductionMultiplier < 1.0).to.equal(true)
			end
		end)

		it("Storm reduces mining production below 1.0", function()
			local data = WeatherManager.get(fakePlayer)
			if data then
				data.currentWeather = "Storm"
				local effects = WeatherManager.getWeatherEffects(fakePlayer)
				expect(effects.miningProductionMultiplier < 1.0).to.equal(true)
			end
		end)
	end)
end
