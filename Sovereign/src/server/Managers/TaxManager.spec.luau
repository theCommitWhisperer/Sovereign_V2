-- TaxManager.spec.luau
-- Tests for tax rate management and collection logic.

return function()
	local TaxManager = require(script.Parent.TaxManager)
	local PlayerManager = require(script.Parent.PlayerManager)

	local fakePlayer = { UserId = 777005, Name = "TaxTestPlayer" } :: any

	beforeEach(function()
		PlayerManager.remove(fakePlayer)
		PlayerManager.create(fakePlayer)
		TaxManager.create(fakePlayer)
	end)

	describe("create and get", function()
		it("creates tax data without erroring", function()
			expect(function()
				TaxManager.create(fakePlayer)
			end).never.to.throw()
		end)

		it("get returns data after create", function()
			expect(TaxManager.get(fakePlayer)).to.be.ok()
		end)

		it("initial tax rate is 0.1 (10%)", function()
			local data = TaxManager.get(fakePlayer)
			expect(data.taxRate).to.equal(0.1)
		end)
	end)

	describe("setTaxRate", function()
		it("sets a valid tax rate", function()
			TaxManager.setTaxRate(fakePlayer, 0.25)
			expect(TaxManager.get(fakePlayer).taxRate).to.equal(0.25)
		end)

		it("clamps tax rate to a maximum of 1.0 (100%)", function()
			TaxManager.setTaxRate(fakePlayer, 1.5)
			expect(TaxManager.get(fakePlayer).taxRate).to.equal(1.0)
		end)

		it("clamps tax rate to a minimum of 0.0 (0%)", function()
			TaxManager.setTaxRate(fakePlayer, -0.5)
			expect(TaxManager.get(fakePlayer).taxRate).to.equal(0.0)
		end)

		it("0% tax rate stores correctly", function()
			TaxManager.setTaxRate(fakePlayer, 0)
			expect(TaxManager.get(fakePlayer).taxRate).to.equal(0)
		end)

		it("100% tax rate stores correctly", function()
			TaxManager.setTaxRate(fakePlayer, 1.0)
			expect(TaxManager.get(fakePlayer).taxRate).to.equal(1.0)
		end)
	end)

	describe("collectTaxes", function()
		it("does not error when collecting taxes", function()
			expect(function()
				TaxManager.collectTaxes(fakePlayer)
			end).never.to.throw()
		end)

		it("adds gold to player resources based on unit count and tax rate", function()
			-- Give the player 10 units (population) and a 10% tax rate
			local playerData = PlayerManager.get(fakePlayer)
			for _ = 1, 10 do
				local fakeUnit = Instance.new("Part") -- Minimal fake unit
				table.insert(playerData.Units, fakeUnit)
			end
			TaxManager.setTaxRate(fakePlayer, 0.1)
			TaxManager.collectTaxes(fakePlayer)
			-- 10 units * 0.1 = 1 gold (floor)
			expect(playerData.Resources.Gold).to.equal(1)
			-- Clean up
			for _, u in playerData.Units do u:Destroy() end
			playerData.Units = {}
		end)
	end)
end
