-- Sovereign_V2/src/shared/GameData.spec/UnitsData.spec.luau

return function()
	local UnitsData = require(script.Parent.Parent.GameData.UnitsData)

	describe("UnitsData", function()
		it("should load and be a non-empty table", function()
			expect(typeof(UnitsData)).to.equal("table")
			expect(next(UnitsData)).to.be.ok()
		end)

		it("should contain core units like Peasant and Knight", function()
			expect(UnitsData.Peasant).to.be.a("table")
			expect(UnitsData.Knight).to.be.a("table")
		end)

		it("should have a 'cost' table for the Peasant unit", function()
			local peasantData = UnitsData.Peasant
			expect(peasantData.cost).to.be.a("table")
			expect(peasantData.cost.Gold).to.be.a("number")
		end)

		it("should have correct data types for a combat unit", function()
			local knightData = UnitsData.Knight
			expect(typeof(knightData.hit_points)).to.equal("number")
			expect(typeof(knightData.attack_damage)).to.equal("number")
			expect(typeof(knightData.movement.speed_meters_per_second)).to.equal("number")
		end)
	end)
end
