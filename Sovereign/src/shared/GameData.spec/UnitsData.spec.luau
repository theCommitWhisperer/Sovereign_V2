return function()
	local GameData = require(script.Parent.Parent.GameData)
	local UnitsData = GameData.Units

	describe("UnitsData", function()
		it("should load and be a non-empty table", function()
			expect(UnitsData).to.be.a("table")
			expect(next(UnitsData)).to.be.ok()
		end)

		it("should contain core units like Peasant and King", function()
			expect(UnitsData.Peasant).to.be.ok()
			expect(UnitsData.King).to.be.ok()
		end)

		it("should have a 'cost' table for the Peasant unit", function()
			local peasantUnit = UnitsData.Peasant
			expect(peasantUnit).to.be.a("table")
			expect(peasantUnit.cost).to.be.a("table")
			expect(next(peasantUnit.cost)).to.be.ok()
		end)

		it("should have correct data types for a combat unit", function()
			local knightUnit = UnitsData.Knight
			expect(knightUnit).to.be.a("table")
			expect(knightUnit.type).to.equal("Unit")

			-- Health
			expect(knightUnit.health).to.be.a("table")
			expect(knightUnit.health.max_health).to.be.a("number")
			expect(knightUnit.health.current_health).to.be.a("number")

			-- Movement
			expect(knightUnit.movement).to.be.a("table")
			expect(knightUnit.movement.speed_meters_per_second).to.be.a("number")

			-- Combat (optional)
			if knightUnit.combat then
				expect(knightUnit.combat).to.be.a("table")
				expect(knightUnit.combat.attack_damage).to.be.a("number")
				expect(knightUnit.combat.attack_range).to.be.a("number")
			end

			-- Training time (optional)
			if knightUnit.training_time_seconds then
				expect(knightUnit.training_time_seconds).to.be.a("number")
			end

			-- Population cost (optional)
			if knightUnit.population_cost then
				expect(knightUnit.population_cost).to.be.a("number")
			end
		end)
	end)
end
