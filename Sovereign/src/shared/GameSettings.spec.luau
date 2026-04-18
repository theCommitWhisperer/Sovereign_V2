-- GameSettings.spec.luau
-- Tests for the shared GameSettings module (game speed multiplier logic).
-- These run automatically via TestRunner.server.luau on every Play in Studio.

return function()
	local GameSettings = require(script.Parent.GameSettings)

	-- Reset to Normal between test groups so tests don't bleed into each other
	beforeEach(function()
		GameSettings.setGameSpeed("Normal")
	end)

	describe("setGameSpeed / getSpeedMultiplier", function()
		it("defaults to Normal (1.0x) before any call", function()
			expect(GameSettings.getSpeedMultiplier()).to.equal(1.0)
		end)

		it("sets Slow to 0.5x", function()
			GameSettings.setGameSpeed("Slow")
			expect(GameSettings.getSpeedMultiplier()).to.equal(0.5)
		end)

		it("sets Normal to 1.0x", function()
			GameSettings.setGameSpeed("Normal")
			expect(GameSettings.getSpeedMultiplier()).to.equal(1.0)
		end)

		it("sets Fast to 2.0x", function()
			GameSettings.setGameSpeed("Fast")
			expect(GameSettings.getSpeedMultiplier()).to.equal(2.0)
		end)

		it("falls back to 1.0x for unknown speed strings", function()
			GameSettings.setGameSpeed("Turbo") -- not a real option
			expect(GameSettings.getSpeedMultiplier()).to.equal(1.0)
		end)

		it("falls back to 1.0x for nil input", function()
			GameSettings.setGameSpeed(nil :: any)
			expect(GameSettings.getSpeedMultiplier()).to.equal(1.0)
		end)
	end)

	describe("waitInterval", function()
		it("returns base seconds unchanged at Normal speed", function()
			GameSettings.setGameSpeed("Normal")
			expect(GameSettings.waitInterval(30)).to.equal(30)
			expect(GameSettings.waitInterval(10)).to.equal(10)
		end)

		it("doubles wait time at Slow speed (ticks less often)", function()
			GameSettings.setGameSpeed("Slow")
			-- 30s base / 0.5x = 60s wait (systems tick slower)
			expect(GameSettings.waitInterval(30)).to.equal(60)
		end)

		it("halves wait time at Fast speed (ticks more often)", function()
			GameSettings.setGameSpeed("Fast")
			-- 30s base / 2.0x = 15s wait
			expect(GameSettings.waitInterval(30)).to.equal(15)
		end)

		it("scales ConsumptionSystem cycle correctly across all speeds", function()
			local BASE_CYCLE = 30 -- ConsumptionSystem's base interval
			GameSettings.setGameSpeed("Slow")
			expect(GameSettings.waitInterval(BASE_CYCLE)).to.equal(60)
			GameSettings.setGameSpeed("Normal")
			expect(GameSettings.waitInterval(BASE_CYCLE)).to.equal(30)
			GameSettings.setGameSpeed("Fast")
			expect(GameSettings.waitInterval(BASE_CYCLE)).to.equal(15)
		end)

		it("handles fractional base seconds", function()
			GameSettings.setGameSpeed("Fast")
			expect(GameSettings.waitInterval(1)).to.equal(0.5)
		end)
	end)
end
