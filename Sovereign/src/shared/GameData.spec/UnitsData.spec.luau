return function()
	local GameData = require(script.Parent.Parent.GameData)
	local UnitsData = GameData.Units

	-- Every field of the flat unit schema (required unless marked optional)
	local REQUIRED_FIELDS = {
		display_name = "string",
		subtype = "string",
		faction = "string",
		description = "string",
		cost = "table",
		training_time_seconds = "number",
		population_cost = "number",
		max_health = "number",
		move_speed = "number",
		attack_damage = "number",
		attack_speed = "number",
		attack_range = "number",
		armor = "number",
		sight_range = "number",
		carry_capacity = "number",
	}

	describe("UnitsData", function()
		it("should load and be a non-empty table", function()
			expect(UnitsData).to.be.a("table")
			expect(next(UnitsData)).to.be.ok()
		end)

		it("should contain core units like Peasant and King", function()
			expect(UnitsData.Peasant).to.be.ok()
			expect(UnitsData.King).to.be.ok()
		end)

		it("should contain the standard corps: Archer, Pikeman, MenAtArms, Knight and siege", function()
			expect(UnitsData.Archer).to.be.ok()
			expect(UnitsData.Pikeman).to.be.ok()
			expect(UnitsData.MenAtArms).to.be.ok()
			expect(UnitsData.Knight).to.be.ok()
			expect(UnitsData.BatteringRam).to.be.ok()
			expect(UnitsData.Catapult).to.be.ok()
		end)

		it("should have a 'cost' table for the Peasant unit", function()
			local peasantUnit = UnitsData.Peasant
			expect(peasantUnit).to.be.a("table")
			expect(peasantUnit.cost).to.be.a("table")
			expect(next(peasantUnit.cost)).to.be.ok()
		end)

		it("every unit is a FLAT record with all required fields", function()
			for unitId, unit in UnitsData do
				for field, expectedType in REQUIRED_FIELDS do
					local value = (unit :: any)[field]
					if typeof(value) ~= expectedType then
						error(`{unitId}.{field} should be {expectedType}, got {typeof(value)}`)
					end
				end
				-- No legacy nested tables allowed
				expect((unit :: any).health).never.to.be.ok()
				expect((unit :: any).movement).never.to.be.ok()
				expect((unit :: any).combat).never.to.be.ok()
			end
		end)

		it("should have correct flat data for a combat unit", function()
			local knightUnit = UnitsData.Knight
			expect(knightUnit).to.be.a("table")
			expect(knightUnit.max_health).to.be.a("number")
			expect(knightUnit.move_speed).to.be.a("number")
			expect(knightUnit.attack_damage).to.be.a("number")
			expect(knightUnit.attack_range).to.be.a("number")
			expect(knightUnit.training_time_seconds).to.be.a("number")
			expect(knightUnit.population_cost).to.be.a("number")
		end)

		it("workers keep the Worker subtype used by WorkerManager and UI", function()
			for _, workerId in { "Peasant", "Farmer", "Woodcutter", "Stonemason", "Miner", "Baker" } do
				expect(UnitsData[workerId].subtype).to.equal("Worker")
			end
		end)
	end)
end
