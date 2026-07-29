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

		-- Iterate via getAllKeys(), not pairs(ResourcesData): the module now
		-- exposes helper functions (get, getAllKeys, buildStartingTable...)
		-- alongside the resource entries, so a raw pairs() walk hits a function
		-- and dies on data.is_tradeable.
		it("should have positive max_carry_amount for tradeable resources", function()
			for _, key in ResourcesData.getAllKeys() do
				local data = ResourcesData.get(key)
				if data and data.is_tradeable then
					expect(data.max_carry_amount > 0).to.equal(true)
				end
			end
		end)

		it("every registered resource is retrievable and well-formed", function()
			local keys = ResourcesData.getAllKeys()
			expect(#keys > 0).to.equal(true)
			for _, key in keys do
				local data = ResourcesData.get(key)
				expect(data).to.be.ok()
				expect(typeof(data.display_name)).to.equal("string")
				expect(typeof(data.tier)).to.equal("string")
			end
		end)

		-- Guards the bug this registry was built to fix: addResources only
		-- credits keys already present, so a missing key silently discards the
		-- resource. Every registered resource must be seeded.
		it("buildStartingTable seeds every registered resource", function()
			local stock = ResourcesData.buildStartingTable()
			for _, key in ResourcesData.getAllKeys() do
				expect(stock[key]).to.equal(0)
			end
		end)
	end)
end
