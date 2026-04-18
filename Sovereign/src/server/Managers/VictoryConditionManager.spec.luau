-- VictoryConditionManager.spec.luau
-- Tests for victory mode selection and the exported API surface.
-- Because VictoryConditionManager depends on PlayerManager/PopulationManager etc.,
-- we focus on the parts we can test without live player data:
--   • setVictoryMode doesn't error for any lobby option
--   • getVictoryConditions returns a non-empty table
--   • setGameStarted and create don't error given a fake player object

return function()
	local VictoryConditionManager = require(script.Parent.VictoryConditionManager)

	-- Build a minimal fake Player object that satisfies UserId checks
	local fakePlayer = {
		UserId = 999999,
		Name = "TestPlayer",
	} :: any

	describe("setVictoryMode", function()
		it("accepts all valid lobby victory condition values", function()
			local modes = { "Conquest", "Wonder", "Score", "Regicide" }
			for _, mode in modes do
				-- Should not throw
				expect(function()
					VictoryConditionManager.setVictoryMode(mode)
				end).never.to.throw()
			end
		end)

		it("accepts nil/unknown without erroring (defaults to Score)", function()
			expect(function()
				VictoryConditionManager.setVictoryMode(nil :: any)
			end).never.to.throw()

			expect(function()
				VictoryConditionManager.setVictoryMode("NotARealMode")
			end).never.to.throw()
		end)
	end)

	describe("getVictoryConditions", function()
		it("returns a non-empty table", function()
			local conditions = VictoryConditionManager.getVictoryConditions()
			expect(conditions).to.be.a("table")
			expect(#conditions > 0).to.equal(true)
		end)

		it("each condition has name, description, and check fields", function()
			local conditions = VictoryConditionManager.getVictoryConditions()
			for _, condition in conditions do
				expect(condition.name).to.be.a("string")
				expect(condition.description).to.be.a("string")
				expect(condition.check).to.be.a("function")
			end
		end)
	end)

	describe("getLossConditions", function()
		it("returns a non-empty table", function()
			local conditions = VictoryConditionManager.getLossConditions()
			expect(conditions).to.be.a("table")
			expect(#conditions > 0).to.equal(true)
		end)

		it("each condition has name, description, and check fields", function()
			local conditions = VictoryConditionManager.getLossConditions()
			for _, condition in conditions do
				expect(condition.name).to.be.a("string")
				expect(condition.description).to.be.a("string")
				expect(condition.check).to.be.a("function")
			end
		end)

		it("includes Population Extinction and Keep Destroyed conditions", function()
			local conditions = VictoryConditionManager.getLossConditions()
			local names = {}
			for _, c in conditions do
				names[c.name] = true
			end
			expect(names["Population Extinction"]).to.equal(true)
			expect(names["Keep Destroyed"]).to.equal(true)
		end)
	end)

	describe("create and setGameStarted", function()
		it("create initialises data for a player without erroring", function()
			expect(function()
				VictoryConditionManager.create(fakePlayer)
			end).never.to.throw()
		end)

		it("get returns the initialised data after create", function()
			VictoryConditionManager.create(fakePlayer)
			local data = VictoryConditionManager.get(fakePlayer)
			expect(data).to.be.ok()
			expect(data.hasWon).to.equal(false)
			expect(data.hasLost).to.equal(false)
			expect(data.peaceTimeSeconds).to.equal(0)
		end)

		it("setGameStarted records peace time without erroring", function()
			VictoryConditionManager.create(fakePlayer)
			expect(function()
				VictoryConditionManager.setGameStarted(fakePlayer, 300) -- 5 minute peace time
			end).never.to.throw()

			local data = VictoryConditionManager.get(fakePlayer)
			expect(data).to.be.ok()
			expect(data.peaceTimeSeconds).to.equal(300)
			expect(data.gameStartTime).to.be.ok() -- should be set to tick()
		end)

		it("setGameStarted with 0 stores peaceTimeSeconds as 0", function()
			VictoryConditionManager.create(fakePlayer)
			VictoryConditionManager.setGameStarted(fakePlayer, 0)
			local data = VictoryConditionManager.get(fakePlayer)
			-- peaceTimeSeconds = 0 means no grace period; defeat checks run immediately
			expect(data.peaceTimeSeconds).to.equal(0)
			-- gameStartTime is still stamped (used for other potential future checks)
			expect(data.gameStartTime).to.be.ok()
		end)
	end)
end
