-- Sovereign/src/shared/GameData.spec/BuildingsData.spec.luau

return function()
	-- Now require the GameData folder (which has init.luau)
	local GameData = require(script.Parent.Parent.GameData)
	local BuildingsData = GameData.Buildings

	describe("BuildingsData", function()
		it("should load and be a non-empty table", function()
			expect(typeof(BuildingsData)).to.equal("table")
			expect(next(BuildingsData)).to.be.ok()
		end)

		it("should contain essential buildings like Keep", function()
			expect(BuildingsData.Keep).to.be.a("table")
		end)

		it("should have a 'cost' table for the Keep", function()
			local keepData = BuildingsData.Keep
			expect(keepData.cost).to.be.a("table")
			expect(keepData.cost.Wood).to.be.a("number")
		end)

		it("should define components for the Keep", function()
			local keepData = BuildingsData.Keep
			expect(keepData.components).to.be.a("table")
		end)
	end)
end
