-- Sovereign_V2/src/shared/GameData.spec/BuildingsData.spec.luau

return function()
	local BuildingsData = require(script.Parent.Parent.GameData.BuildingsData)

	describe("BuildingsData", function()
		it("should load and be a non-empty table", function()
			expect(typeof(BuildingsData)).to.equal("table")
			expect(next(BuildingsData)).to.be.ok()
		end)

		it("should contain essential buildings like Keep and Barracks", function()
			expect(BuildingsData.Keep).to.be.a("table")
			expect(BuildingsData.Barracks).to.be.a("table")
		end)

		it("should have a 'cost' table for the Keep", function()
			local keepData = BuildingsData.Keep
			expect(keepData.cost).to.be.a("table")
			expect(keepData.cost.Wood).to.be.a("number")
		end)

		it("should define components for the Barracks", function()
			local barracksData = BuildingsData.Barracks
			expect(barracksData.components).to.be.a("table")
			expect(barracksData.components[1].name).to.equal("UnitTrainer")
			expect(#barracksData.components[1].units > 0).to.equal(true)
		end)
	end)
end
