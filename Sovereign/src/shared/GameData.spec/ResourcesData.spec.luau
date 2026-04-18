-- ResourcesData.spec.luau

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
			-- Actual fields in ResourcesData: display_name, icon, is_tradeable, max_carry_amount
			expect(typeof(woodData.display_name)).to.equal("string")
			expect(typeof(woodData.is_tradeable)).to.equal("boolean")
			expect(typeof(woodData.max_carry_amount)).to.equal("number")
		end)

		it("should have positive max_carry_amount for tradeable resources", function()
			for name, data in ResourcesData do
				if data.is_tradeable then
					expect(data.max_carry_amount > 0).to.equal(true)
				end
			end
		end)
	end)
end
