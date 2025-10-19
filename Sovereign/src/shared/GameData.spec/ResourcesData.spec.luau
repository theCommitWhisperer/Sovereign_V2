-- Sovereign_V2/src/shared/GameData.spec/ResourcesData.spec.luau

return function()
	local ResourcesData = require(script.Parent.Parent.GameData.ResourcesData)

	describe("ResourcesData", function()
		it("should load and be a non-empty table", function()
			expect(typeof(ResourcesData)).to.equal("table")
			expect(next(ResourcesData)).to.be.ok()
		end)

		it("should contain essential resources like Wood and Gold", function()
			expect(ResourcesData.Wood).to.be.a("table")
			expect(ResourcesData.Gold).to.be.a("table")
		end)

		it("should have correct data types for its entries", function()
			local woodData = ResourcesData.Wood
			expect(typeof(woodData.type)).to.equal("string")
			expect(typeof(woodData.subtype)).to.equal("string")
			expect(typeof(woodData.category)).to.equal("string")
			expect(typeof(woodData.description)).to.equal("string")
		end)
	end)
end
