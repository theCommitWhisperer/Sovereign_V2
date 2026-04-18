-- PlayerManager.spec.luau
-- Tests for the foundational player data store that all other managers depend on.

return function()
	local PlayerManager = require(script.Parent.PlayerManager)

	local fakePlayer = { UserId = 777001, Name = "TestPlayer" } :: any

	beforeEach(function()
		-- Clean slate for each test
		PlayerManager.remove(fakePlayer)
	end)

	describe("create and get", function()
		it("creates player data and retrieves it by UserId", function()
			local data = PlayerManager.create(fakePlayer)
			expect(data).to.be.ok()
			expect(PlayerManager.get(fakePlayer)).to.equal(data)
		end)

		it("initialises GameState to MainMenu", function()
			local data = PlayerManager.create(fakePlayer)
			expect(data.GameState).to.equal("MainMenu")
		end)

		it("initialises all resource slots to 0", function()
			local data = PlayerManager.create(fakePlayer)
			local resources = { "Wood", "Stone", "Gold", "Food", "Weapons", "Iron_Bars", "Iron_Ore" }
			for _, r in resources do
				expect(data.Resources[r]).to.equal(0)
			end
		end)

		it("initialises Buildings and Units as empty tables", function()
			local data = PlayerManager.create(fakePlayer)
			expect(#data.Buildings).to.equal(0)
			expect(#data.Units).to.equal(0)
		end)

		it("returns nil for a player that has not been created", function()
			expect(PlayerManager.get(fakePlayer)).never.to.be.ok()
		end)
	end)

	describe("remove", function()
		it("removes player data so get returns nil", function()
			PlayerManager.create(fakePlayer)
			PlayerManager.remove(fakePlayer)
			expect(PlayerManager.get(fakePlayer)).never.to.be.ok()
		end)

		it("remove on unknown player does not error", function()
			expect(function()
				PlayerManager.remove(fakePlayer)
			end).never.to.throw()
		end)
	end)

	describe("addResources", function()
		it("adds resources to existing totals", function()
			local data = PlayerManager.create(fakePlayer)
			PlayerManager.addResources(fakePlayer, { Wood = 50, Gold = 100 })
			expect(data.Resources.Wood).to.equal(50)
			expect(data.Resources.Gold).to.equal(100)
		end)

		it("accumulates across multiple calls", function()
			local data = PlayerManager.create(fakePlayer)
			PlayerManager.addResources(fakePlayer, { Food = 30 })
			PlayerManager.addResources(fakePlayer, { Food = 20 })
			expect(data.Resources.Food).to.equal(50)
		end)

		it("ignores unknown resource keys without erroring", function()
			PlayerManager.create(fakePlayer)
			expect(function()
				PlayerManager.addResources(fakePlayer, { MagicDust = 999 })
			end).never.to.throw()
		end)
	end)

	describe("deductResources", function()
		it("subtracts resources correctly", function()
			local data = PlayerManager.create(fakePlayer)
			PlayerManager.addResources(fakePlayer, { Wood = 100 })
			PlayerManager.deductResources(fakePlayer, { Wood = 40 })
			expect(data.Resources.Wood).to.equal(60)
		end)

		it("clamps at 0 — never goes negative", function()
			local data = PlayerManager.create(fakePlayer)
			PlayerManager.deductResources(fakePlayer, { Wood = 9999 })
			expect(data.Resources.Wood).to.equal(0)
		end)
	end)

	describe("hasEnoughResources", function()
		it("returns true when player has enough of each resource", function()
			PlayerManager.create(fakePlayer)
			PlayerManager.addResources(fakePlayer, { Wood = 50, Stone = 30 })
			expect(PlayerManager.hasEnoughResources(fakePlayer, { Wood = 50, Stone = 30 })).to.equal(true)
		end)

		it("returns false when a resource is insufficient", function()
			PlayerManager.create(fakePlayer)
			PlayerManager.addResources(fakePlayer, { Wood = 10 })
			expect(PlayerManager.hasEnoughResources(fakePlayer, { Wood = 50 })).to.equal(false)
		end)

		it("returns false when player has none of a required resource", function()
			PlayerManager.create(fakePlayer)
			expect(PlayerManager.hasEnoughResources(fakePlayer, { Gold = 1 })).to.equal(false)
		end)

		it("returns false for a player with no data", function()
			-- fakePlayer was removed in beforeEach, not created yet
			expect(PlayerManager.hasEnoughResources(fakePlayer, { Wood = 1 })).to.equal(false)
		end)
	end)
end
