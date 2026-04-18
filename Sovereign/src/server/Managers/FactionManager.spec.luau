-- FactionManager.spec.luau
-- Tests for faction creation and relationship logic (no player data needed).

return function()
	local FactionManager = require(script.Parent.FactionManager)

	-- init() sets up default factions and relationships — call once before tests
	FactionManager.init()

	describe("createFaction", function()
		it("creates a faction without erroring", function()
			expect(function()
				FactionManager.createFaction("TestFaction")
			end).never.to.throw()
		end)

		it("calling createFaction twice on the same name does not error", function()
			expect(function()
				FactionManager.createFaction("TestFaction")
				FactionManager.createFaction("TestFaction")
			end).never.to.throw()
		end)
	end)

	describe("setRelationship and getRelationship", function()
		it("defaults to Neutral for unset faction pairs", function()
			FactionManager.createFaction("Alpha")
			FactionManager.createFaction("Beta")
			expect(FactionManager.getRelationship("Alpha", "Beta")).to.equal("Neutral")
		end)

		it("sets and retrieves a relationship", function()
			FactionManager.createFaction("Alpha")
			FactionManager.createFaction("Beta")
			FactionManager.setRelationship("Alpha", "Beta", "Enemy")
			expect(FactionManager.getRelationship("Alpha", "Beta")).to.equal("Enemy")
		end)

		it("relationship is symmetric — A→B equals B→A", function()
			FactionManager.createFaction("Alpha")
			FactionManager.createFaction("Beta")
			FactionManager.setRelationship("Alpha", "Beta", "Enemy")
			expect(FactionManager.getRelationship("Beta", "Alpha")).to.equal("Enemy")
		end)

		it("returns Neutral for completely unknown factions", function()
			expect(FactionManager.getRelationship("Nobody", "Nobody2")).to.equal("Neutral")
		end)
	end)

	describe("areEnemies", function()
		it("returns true when relationship is Enemy", function()
			FactionManager.createFaction("FactionX")
			FactionManager.createFaction("FactionY")
			FactionManager.setRelationship("FactionX", "FactionY", "Enemy")
			expect(FactionManager.areEnemies("FactionX", "FactionY")).to.equal(true)
		end)

		it("returns false for Neutral factions", function()
			FactionManager.createFaction("FactionX")
			FactionManager.createFaction("FactionZ")
			-- No relationship set — defaults to Neutral
			expect(FactionManager.areEnemies("FactionX", "FactionZ")).to.equal(false)
		end)
	end)

	describe("default init() relationships", function()
		it("Player and Rebel are enemies", function()
			expect(FactionManager.areEnemies("Player", "Rebel")).to.equal(true)
		end)

		it("Player and Viking are enemies", function()
			expect(FactionManager.areEnemies("Player", "Viking")).to.equal(true)
		end)

		it("all four player factions are enemies with each other", function()
			local pf = { "Kingdom", "Empire", "Tribes", "IronLegion" }
			for i = 1, #pf do
				for j = i + 1, #pf do
					expect(FactionManager.areEnemies(pf[i], pf[j])).to.equal(true)
				end
			end
		end)
	end)
end
