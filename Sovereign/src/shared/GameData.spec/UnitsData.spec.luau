return function()
	local GameData = require(script.Parent.Parent.GameData)
	local UnitsData = GameData.Units

	describe("UnitsData", function()
		it("should load and be a non-empty table", function()
			expect(typeof(UnitsData)).to.equal("table")
			expect(next(UnitsData)).to.be.ok()
		end)

		it("should contain core units like Peasant and King", function()
			expect(UnitsData.Peasant).to.be.a("table")
			expect(UnitsData.King).to.be.a("table")
		end)

		it("should have a 'cost' table for the Peasant unit", function()
			local peasantData = UnitsData.Peasant
			expect(peasantData.cost).to.be.a("table")
			expect(peasantData.cost.Gold).to.be.a("number")
		end)

		it("should have correct data types for a combat unit", function()
			local kingData = UnitsData.King
			expect(typeof(kingData.hit_points)).to.equal("number")
			expect(typeof(kingData.attack_damage)).to.equal("number")
			expect(typeof(kingData.movement.speed_meters_per_second)).to.equal("number")
		end)
	end)
end
