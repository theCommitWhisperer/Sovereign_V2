-- CaravanManager.spec.luau
-- Tests for the trade-enabled flag and caravan data initialisation.

return function()
	local CaravanManager = require(script.Parent.CaravanManager)
	local PlayerManager = require(script.Parent.PlayerManager)

	local fakePlayer = { UserId = 777002, Name = "CaravanTestPlayer" } :: any

	beforeEach(function()
		PlayerManager.remove(fakePlayer)
		PlayerManager.create(fakePlayer)
		-- Reset trade flag to default
		CaravanManager.setTradeEnabled(true)
	end)

	describe("setTradeEnabled / isTradeEnabled", function()
		it("defaults to enabled", function()
			expect(CaravanManager.isTradeEnabled()).to.equal(true)
		end)

		it("can be disabled", function()
			CaravanManager.setTradeEnabled(false)
			expect(CaravanManager.isTradeEnabled()).to.equal(false)
		end)

		it("can be re-enabled after disabling", function()
			CaravanManager.setTradeEnabled(false)
			CaravanManager.setTradeEnabled(true)
			expect(CaravanManager.isTradeEnabled()).to.equal(true)
		end)

		it("reflects the lobby 'Ability to Trade = false' setting", function()
			-- Simulates lobby setting abilityToTrade = false
			CaravanManager.setTradeEnabled(false)
			expect(CaravanManager.isTradeEnabled()).to.equal(false)
		end)
	end)

	describe("create and get", function()
		it("creates caravan data for a player without erroring", function()
			expect(function()
				CaravanManager.create(fakePlayer)
			end).never.to.throw()
		end)

		it("get returns data after create", function()
			CaravanManager.create(fakePlayer)
			local data = CaravanManager.get(fakePlayer)
			expect(data).to.be.ok()
		end)

		it("initial completedTrades is 0", function()
			CaravanManager.create(fakePlayer)
			local data = CaravanManager.get(fakePlayer)
			expect(data.completedTrades).to.equal(0)
		end)

		it("initial caravansLost is 0", function()
			CaravanManager.create(fakePlayer)
			local data = CaravanManager.get(fakePlayer)
			expect(data.caravansLost).to.equal(0)
		end)
	end)

	describe("sendCaravan when trade is disabled", function()
		it("sendCaravan returns false (blocked) when trade is disabled", function()
			CaravanManager.create(fakePlayer)
			CaravanManager.setTradeEnabled(false)
			local result = CaravanManager.sendCaravan(fakePlayer, "Dublin")
			expect(result).to.equal(false)
		end)
	end)
end
